// =============================================================================
//  sdram_controller_top.v
//  CPU-clock to SDRAM-clock wrapper around `sdram_controller`.
//
//  Host interface uses a 28-bit byte address, 32-bit data, `MAS` access size,
//  and CPU `sign_extend`. It remaps EWRAM and PAK ROM apertures into SDRAM
//  halfword addresses, derives byte masks for subword writes, formats byte and
//  halfword reads, and requests two SDRAM half-beats for 32-bit word transfers.
//
//  The CPU and SDRAM clocks are related PLL outputs. A new host beat is sampled
//  on the first following SDRAM edge, then held until the core accepts it. The
//  completion flag is retimed on the SDRAM falling edge so it is stable before
//  the inverse-CPU-clock edge that updates `nWAIT`.
// =============================================================================

module sdram_controller_top (
    input   wire        clock,        // CPU / core frequency
    input   wire        clock_sdram,  // SDRAM frequency
    input   wire        nrst,

    input   wire        rd_en,
    input   wire        wr_en,
    input   wire [1:0]  MAS,          // active master size: 00=byte 01=half 10=word
    input   wire        sign_extend,  // CPU sign_f, for byte loads

	input   wire [27:0] addr,
    input   wire [31:0] wr_data,
    output  wire [31:0] rd_data,
    output  wire        busy,

    output  wire [12:0] SA,
    output  wire [1:0]  BA,
    output  wire        CS_N,
    output  wire        CKE,
    output  wire        RAS_N,
    output  wire        CAS_N,
    output  wire        WE_N,
    inout   wire [15:0] DQ,
    output  wire [1:0]  DQM
);

wire is_ewram = addr[27:24] == 4'h2;
wire is_byte  = (MAS == 2'b00);
wire is_word  = MAS[1];            // MAS: 10=word, 01=half, 00=byte

wire        access   = rd_en || wr_en;
reg  [29:0] acc_q = 0;
wire [29:0] acc      = {addr, rd_en, wr_en};
wire        new_beat = access && (acc != acc_q);
always @(posedge clock) acc_q <= acc;

// Minimum GBA-visible access length, counted at inverse CPU-clock edges. The
// first edge after launch loads count 1; the final threshold is visible before
// the edge that releases `nWAIT`. PAK accesses use default non-sequential time.
wire [2:0] min_wait_edges = is_ewram ? (is_word ? 3'd5 : 3'd2)
                                      : (is_word ? 3'd7 : 3'd4);
reg [2:0] wait_edges = 0;
always @(posedge clock or negedge nrst)
    if (!nrst)            wait_edges <= 0;
    else if (!access)     wait_edges <= 0;
    else if (new_beat)    wait_edges <= 3'd1;
    else if (wait_edges != 3'd7)
        wait_edges <= wait_edges + 1'b1;

wire timing_ready = wait_edges >= min_wait_edges;

// `clock` is the inverse 17 MHz host clock and `clock_sdram` is its related
// 68 MHz PLL output. `new_beat` is therefore stable by the next SDRAM edge.
reg beat_seen = 0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst) beat_seen <= 0;
    else       beat_seen <= new_beat;

wire beat_start    = new_beat && !beat_seen;
wire rd_start_fast = beat_start && rd_en;
wire wr_start_fast = beat_start && wr_en;

wire [24:0] mapped_addr = is_ewram
                        ? {8'b0, addr[17:1]}
                        : {1'b1, addr[24:1]};
wire [31:0] mapped_wr_data = is_byte
                           ? {16'b0, {2{wr_data[7:0]}}}
                           : wr_data;
wire [1:0] mapped_byte_mask = is_byte
                            ? (addr[0] ? 2'b10 : 2'b01)
                            : 2'b00;

reg [24:0] addr_r = 0;
reg [31:0] wr_data_r = 0;
reg [1:0]  byte_mask_r = 2'b00;   // DQM {low,high} for the latched write beat
reg        word_r = 0;            // 32-bit access: core does two SDRAM half-beats

// Read-beat qualifiers, latched at request time, used to format read data.
reg        rd_byte_r = 0;   // this beat is a byte load
reg        rd_lane_r = 0;   // addr[0]: which byte within the halfword
reg        rd_sign_r = 0;   // sign-extend the loaded byte

always @(posedge clock_sdram or negedge nrst) begin
    if (!nrst) begin
        addr_r      <= 0;
        wr_data_r   <= 0;
        byte_mask_r <= 2'b00;
        word_r      <= 0;
        rd_byte_r   <= 0;
        rd_lane_r   <= 0;
        rd_sign_r   <= 0;
    end else if (beat_start) begin
        addr_r <= mapped_addr;
        word_r <= is_word;

        if (wr_en) begin
            // Byte: replicate into the low lane (core uses [15:0]); DQM picks
            // the addressed byte. Half/word: pass the full 32 bits; the core
            // writes the low half then the high half on a word access.
            wr_data_r   <= mapped_wr_data;
            byte_mask_r <= mapped_byte_mask;
        end
        if (rd_en) begin
            rd_byte_r <= is_byte;
            rd_lane_r <= addr[0];
            rd_sign_r <= sign_extend;
        end
    end
end

// On the beat-start edge the controller must see the live payload; the
// registered copy holds it stable if refresh delays acceptance.
wire [24:0] core_addr      = beat_start ? mapped_addr      : addr_r;
wire [31:0] core_wr_data   = beat_start ? mapped_wr_data   : wr_data_r;
wire [1:0]  core_byte_mask = beat_start ? mapped_byte_mask : byte_mask_r;
wire        core_word      = beat_start ? is_word          : word_r;

// Read Data

wire [31:0] rd_data_i;
wire        rd_ready;
reg [31:0]  rd_data_r = 0;

always @(posedge clock_sdram or negedge nrst)
    if (!nrst)         rd_data_r <= 0;
    else if (rd_ready) rd_data_r <= rd_data_i;

// Word loads return the full 32 bits the core assembled (low half in [15:0],
// high half in [31:16]). Byte loads select the addressed lane of the low half
// and optionally sign-extend. Halfword loads zero-extend the low half.
wire [7:0]  rd_byte     = rd_lane_r ? rd_data_r[15:8] : rd_data_r[7:0];
wire [31:0] rd_byte_ext = rd_sign_r ? {{24{rd_byte[7]}}, rd_byte} : {24'b0, rd_byte};
assign rd_data = word_r    ? rd_data_r
               : rd_byte_r ? rd_byte_ext
               :             {rd_sign_r ? {16{rd_data_r[15]}} : 16'b0, rd_data_r[15:0]};

///////////////////////////////////////////////////////////////////////

// "accept" = core enters a transaction; "busy_end" = core leaves one.
wire core_busy;
reg core_busy_d = 0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst) core_busy_d <= 0;
    else       core_busy_d <= core_busy;
wire accept    =  core_busy && !core_busy_d;
wire busy_end  = !core_busy &&  core_busy_d;

// Hold each request until the core accepts it.
reg rd_req = 0, wr_req = 0;
always @(posedge clock_sdram)
    if (!nrst) begin
        rd_req <= 0;
        wr_req <= 0;
    end else begin
        if (rd_start_fast)                    rd_req <= 1;
        else if (accept && rd_req)            rd_req <= 0;

        if (wr_start_fast)                    wr_req <= 1;
        else if (accept && !rd_req && wr_req) wr_req <= 0;
    end

wire rd_en_pulse = rd_req || rd_start_fast;
wire wr_en_pulse = wr_req || wr_start_fast;

//////////////////////////////////////////

reg done_fast = 0;
reg done_phase = 0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst)                               done_fast <= 0;
    else if (rd_start_fast || wr_start_fast) done_fast <= 0;
    else if (rd_ready || busy_end)           done_fast <= 1;

// The falling-edge retime gives the following `clock_n` edge half an SDRAM
// cycle of setup margin, avoiding the nearly coincident rising edges.
always @(negedge clock_sdram or negedge nrst)
    if (!nrst) done_phase <= 0;
    else       done_phase <= done_fast;

assign busy = access && !(done_phase && timing_ready && !new_beat);

// ======================================================================
// SDRAM controller core (clock_sdram domain)
// ======================================================================
sdram_controller sdram_controlleri (
    /* HOST INTERFACE */
    .wr_addr       (core_addr),
    .wr_data       (core_wr_data),
    .byte_mask     (core_byte_mask),
    .word          (core_word),
    .wr_enable     (wr_en_pulse),

    .rd_addr       (core_addr),
    .rd_data       (rd_data_i),
    .rd_ready      (rd_ready),
    .rd_enable     (rd_en_pulse),

    .busy          (core_busy),
    .rst_n         (nrst),
    .clk           (clock_sdram),

    /* SDRAM SIDE */
    .addr          (SA),
    .bank_addr     (BA),
    .data          (DQ),
    .clock_enable  (CKE),
    .cs_n          (CS_N),
    .ras_n         (RAS_N),
    .cas_n         (CAS_N),
    .we_n          (WE_N),
    .data_mask_low (DQM[0]),
    .data_mask_high(DQM[1])
);

endmodule // sdram_controller_top
