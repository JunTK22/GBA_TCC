// =============================================================================
//  sdram_controller.v
//  SDRAM clock-domain command engine for the DE1-SoC 16-bit SDRAM.
//
//  OpenCores-derived single-clock controller with initialization, periodic
//  refresh, activate/read/write/precharge sequencing, and a simple host request
//  interface. The host side presents halfword addresses. Byte writes use DQM via
//  `byte_mask`; word transfers (`word == 1`) are performed as two sequential
//  16-bit beats and assembled into `rd_data[31:0]` on reads.
//
//  `busy` is asserted while the command FSM owns an active read or write
//  sequence. `rd_ready` pulses when read data is valid; for word reads this is
//  after the high halfword is captured.
// =============================================================================

module sdram_controller (
    /* HOST INTERFACE */
    wr_addr,
    wr_data,
    wr_enable,
    byte_mask,
    word,

    rd_addr,
    rd_data,
    rd_ready,
    rd_enable,

    busy, rst_n, clk,

    /* SDRAM SIDE */
    addr, bank_addr, data, clock_enable, cs_n, ras_n, cas_n, we_n,
    data_mask_low, data_mask_high
);

/* Internal Parameters */
parameter ROW_WIDTH = 13;
parameter COL_WIDTH = 10;
parameter BANK_WIDTH = 2;

parameter SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH;
parameter HADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;

parameter CLK_FREQUENCY = 68;  // Mhz
parameter REFRESH_TIME =  64;   // ms     (how often we need to refresh)
parameter REFRESH_COUNT = 8192; // cycles (how many refreshes required per refresh time)

// clk / refresh =  clk / sec
//                , sec / refbatch
//                , ref / refbatch
localparam CYCLES_BETWEEN_REFRESH = ( CLK_FREQUENCY
                                      * 1_000
                                      * REFRESH_TIME
                                    ) / REFRESH_COUNT;

// STATES - State
localparam IDLE      = 5'b00000;

localparam INIT_NOP1 = 5'b01000,
           INIT_PRE1 = 5'b01001,
           INIT_NOP1_1=5'b00101,
           INIT_REF1 = 5'b01010,
           INIT_NOP2 = 5'b01011,
           INIT_REF2 = 5'b01100,
           INIT_NOP3 = 5'b01101,
           INIT_LOAD = 5'b01110,
           INIT_NOP4 = 5'b01111;

localparam REF_PRE  =  5'b00001,
           REF_NOP1 =  5'b00010,
           REF_REF  =  5'b00011,
           REF_NOP2 =  5'b00100;

localparam READ_ACT  = 5'b10000,
           READ_NOP1 = 5'b10001,
           READ_CAS  = 5'b10010,
           READ_NOP2 = 5'b10011,
           READ_READ = 5'b10100;

localparam WRIT_ACT  = 5'b11000,
           WRIT_NOP1 = 5'b11001,
           WRIT_CAS  = 5'b11010,
           WRIT_NOP2 = 5'b11011;

// Commands              CCRCWBBA
//                       ESSSE100
localparam CMD_PALL = 8'b10010001,
           CMD_REF  = 8'b10001000,
           CMD_NOP  = 8'b10111000,
           CMD_MRS  = 8'b1000000x,
           CMD_BACT = 8'b10011xxx,
           CMD_READ = 8'b10101xx1,
           CMD_WRIT = 8'b10100xx1;

/* Interface Definition */
/* HOST INTERFACE */
input  [HADDR_WIDTH-1:0]   wr_addr;
input  [31:0]              wr_data;
input                      wr_enable;
input  [1:0]               byte_mask;   // write DQM {low,high}; 0=enable lane
input                      word;        // 1 = 32-bit access (two SDRAM half-beats)

input  [HADDR_WIDTH-1:0]   rd_addr;
output [31:0]              rd_data;
input                      rd_enable;
output                     rd_ready;

output                     busy;
input                      rst_n;
input                      clk;

/* SDRAM SIDE */
output [SDRADDR_WIDTH-1:0] addr;
output [BANK_WIDTH-1:0]    bank_addr;
inout  [15:0]              data;
output                     clock_enable;
output                     cs_n;
output                     ras_n;
output                     cas_n;
output                     we_n;
output                     data_mask_low;
output                     data_mask_high;

/* I/O Registers */

reg  [HADDR_WIDTH-1:0]   haddr_r;
reg  [31:0]              wr_data_r;
reg  [1:0]               byte_mask_r;
reg                      word_r;       // latched: this access is 32-bit
reg                      beat;         // 0 = low half, 1 = high half
reg  [31:0]              rd_data_r;
reg                      busy;
reg                      data_mask_low_r;
reg                      data_mask_high_r;
reg [SDRADDR_WIDTH-1:0]  addr_r;
reg [BANK_WIDTH-1:0]     bank_addr_r;
reg                      rd_ready_r;

wire [15:0]              data_output;
wire                     data_mask_low, data_mask_high;

assign data_mask_high = data_mask_high_r;
assign data_mask_low  = data_mask_low_r;
assign rd_data        = rd_data_r;

/* Internal Wiring */
reg [3:0] state_cnt;
reg [9:0] refresh_cnt;

reg [7:0] command;
reg [4:0] state;

// TODO output addr[6:4] when programming mode register

reg [7:0] command_nxt;
reg [3:0] state_cnt_nxt;
reg [4:0] next;

assign {clock_enable, cs_n, ras_n, cas_n, we_n} = command[7:3];
// state[4] will be set if mode is read/write
assign bank_addr      = (state[4]) ? bank_addr_r : command[2:1];
assign addr           = (state[4] | state == INIT_LOAD) ? addr_r : { {SDRADDR_WIDTH-11{1'b0}}, command[0], 10'd0 };

assign data = (state == WRIT_CAS) ? (beat ? wr_data_r[31:16] : wr_data_r[15:0]) : 16'bz;
assign rd_ready = rd_ready_r;

// A word access advances to its high half when the low half's terminal state
// completes (READ_READ, or WRIT_NOP2 once its hold counter expires). `!beat`
// makes this self-clearing so it can only fire once per word.
wire second_beat_go = word_r && !beat &&
                      ( (state == READ_READ) ||
                        (state == WRIT_NOP2 && state_cnt == 4'd0) );

// HOST INTERFACE
// all registered on posedge
always @ (posedge clk)
  if (~rst_n)
    begin
    state <= INIT_NOP1;
    command <= CMD_NOP;
    state_cnt <= 4'hf;

    haddr_r <= {HADDR_WIDTH{1'b0}};
    wr_data_r <= 32'b0;
    byte_mask_r <= 2'b00;
    word_r <= 1'b0;
    beat <= 1'b0;
    rd_data_r <= 32'b0;
    busy <= 1'b0;
    end
  else
    begin

    state <= next;
    command <= command_nxt;

    if (!state_cnt)
      state_cnt <= state_cnt_nxt;
    else
      state_cnt <= state_cnt - 1'b1;

    if (wr_enable)
      begin
      wr_data_r <= wr_data;
      byte_mask_r <= byte_mask;
      end

    // Capture the read half belonging to the current beat. For a word
    // access rd_ready is asserted only after the high half (beat 1).
    if (state == READ_READ)
      begin
      if (beat) rd_data_r[31:16] <= data;
      else      rd_data_r[15:0]  <= data;
      rd_ready_r <= word_r ? beat : 1'b1;
      end
    else
      rd_ready_r <= 1'b0;

    busy <= state[4];

    // Address / beat sequencing. A new access latches the base address,
    // captures its size, and clears the beat counter. A word access then
    // advances to the high half (col+1, fresh ACT) when the low half ends.
    if (rd_enable || wr_enable)
      begin
      haddr_r <= rd_enable ? rd_addr : wr_addr;
      word_r  <= word;
      beat    <= 1'b0;
      end
    else if (second_beat_go)
      begin
      haddr_r <= haddr_r + 1'b1;
      beat    <= 1'b1;
      end

    end

// Handle refresh counter
always @ (posedge clk)
 if (~rst_n)
   refresh_cnt <= 10'b0;
 else
   if (state == REF_NOP2)
     refresh_cnt <= 10'b0;
   else
     refresh_cnt <= refresh_cnt + 1'b1;


/* Handle logic for sending addresses to SDRAM based on current state*/
always @*
begin
    if (state[4])
      // state[3] distinguishes WRIT_* (11xxx) from READ_* (10xxx).
      // Writes honour the per-beat byte mask (DQM); reads enable both lanes.
      {data_mask_low_r, data_mask_high_r} = state[3] ? byte_mask_r : 2'b00;
    else
      {data_mask_low_r, data_mask_high_r} = 2'b11;

   bank_addr_r = 2'b00;
   addr_r = {SDRADDR_WIDTH{1'b0}};

   if (state == READ_ACT | state == WRIT_ACT)
     begin
     bank_addr_r = haddr_r[HADDR_WIDTH-1:HADDR_WIDTH-(BANK_WIDTH)];
     addr_r = haddr_r[HADDR_WIDTH-(BANK_WIDTH+1):HADDR_WIDTH-(BANK_WIDTH+ROW_WIDTH)];
     end
   else if (state == READ_CAS | state == WRIT_CAS)
     begin
     // Send Column Address
     // Set bank to bank to precharge
     bank_addr_r = haddr_r[HADDR_WIDTH-1:HADDR_WIDTH-(BANK_WIDTH)];

     // Examples for math
     //               BANK  ROW    COL
     // HADDR_WIDTH   2 +   13 +   9   = 24
     // SDRADDR_WIDTH 13

     // Set CAS address to:
     //   0s,
     //   1 (A10 is always for auto precharge),
     //   0s,
     //   column address
     addr_r = {
               {SDRADDR_WIDTH-(11){1'b0}},
               1'b1,                       /* A10 */
               {10-COL_WIDTH{1'b0}},
               haddr_r[COL_WIDTH-1:0]
              };
     end
   else if (state == INIT_LOAD)
     begin
     // Program mode register during load cycle
     //                                       B  C  SB
     //                                       R  A  EUR
     //                                       S  S-3Q ST
     //                                       T  654L210
     addr_r = {{SDRADDR_WIDTH-10{1'b0}}, 10'b1000110000};
     end
end

// Next state logic
always @*
begin
   state_cnt_nxt = 4'd0;
   command_nxt = CMD_NOP;
   if (state == IDLE)
        // Monitor for refresh or hold
        if (refresh_cnt >= CYCLES_BETWEEN_REFRESH)
          begin
          next = REF_PRE;
          command_nxt = CMD_PALL;
          end
        else if (rd_enable)
          begin
          next = READ_ACT;
          command_nxt = CMD_BACT;
          end
        else if (wr_enable)
          begin
          next = WRIT_ACT;
          command_nxt = CMD_BACT;
          end
        else
          begin
          // HOLD
          next = IDLE;
          end
    else
      if (!state_cnt)
        case (state)
          // INIT ENGINE
          INIT_NOP1:
            begin
            next = INIT_PRE1;
            command_nxt = CMD_PALL;
            end
          INIT_PRE1:
            begin
            next = INIT_NOP1_1;
            end
          INIT_NOP1_1:
            begin
            next = INIT_REF1;
            command_nxt = CMD_REF;
            end
          INIT_REF1:
            begin
            next = INIT_NOP2;
            state_cnt_nxt = 4'd7;
            end
          INIT_NOP2:
            begin
            next = INIT_REF2;
            command_nxt = CMD_REF;
            end
          INIT_REF2:
            begin
            next = INIT_NOP3;
            state_cnt_nxt = 4'd7;
            end
          INIT_NOP3:
            begin
            next = INIT_LOAD;
            command_nxt = CMD_MRS;
            end
          INIT_LOAD:
            begin
            next = INIT_NOP4;
            state_cnt_nxt = 4'd1;
            end
          // INIT_NOP4: default - IDLE

          // REFRESH
          REF_PRE:
            begin
            next = REF_NOP1;
            end
          REF_NOP1:
            begin
            next = REF_REF;
            command_nxt = CMD_REF;
            end
          REF_REF:
            begin
            next = REF_NOP2;
            state_cnt_nxt = 4'd7;
            end
          // REF_NOP2: default - IDLE

          // WRITE
          WRIT_ACT:
            begin
            next = WRIT_NOP1;
            state_cnt_nxt = 4'd1;
            end
          WRIT_NOP1:
            begin
            next = WRIT_CAS;
            command_nxt = CMD_WRIT;
            end
          WRIT_CAS:
            begin
            next = WRIT_NOP2;
            state_cnt_nxt = 4'd1;
            end
          WRIT_NOP2:
            // Word access: re-activate for the high half; else finish.
            if (word_r && !beat)
              begin
              next = WRIT_ACT;
              command_nxt = CMD_BACT;
              end
            else
              next = IDLE;

          // READ
          READ_ACT:
            begin
            next = READ_NOP1;
            state_cnt_nxt = 4'd1;
            end
          READ_NOP1:
            begin
            next = READ_CAS;
            command_nxt = CMD_READ;
            end
          READ_CAS:
            begin
            next = READ_NOP2;
            state_cnt_nxt = 4'd1;
            end
          READ_NOP2:
            begin
            next = READ_READ;
            end
          READ_READ:
            // Word access: re-activate for the high half; else finish.
            if (word_r && !beat)
              begin
              next = READ_ACT;
              command_nxt = CMD_BACT;
              end
            else
              next = IDLE;

          default:
            begin
            next = IDLE;
            end
          endcase
      else
        begin
        // Counter Not Reached - HOLD
        next = state;
        command_nxt = command;
        end
end

endmodule
