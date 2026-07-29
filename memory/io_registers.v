// =============================================================================
//  io_registers.v
//  GBA memory-mapped IO register file for 0x04000000-0x040003FF.
//
//  The CPU/DMA port is byte addressed and 32 bits wide. Register storage uses
//  16-bit `regs[hw_idx]` entries; named DMA, PPU, interrupt, serial, and sound
//  outputs are combinational views of those entries. Reads are registered with
//  one cycle of latency, matching the other local bus regions.
//
//  The register set follows CowBite section 10 / gba.h. These categories need
//  special semantics:
//
//    1.  Read-only, hardware-driven:
//          VCOUNT (0x006), KEY (0x130).
//        Writes ignored, reads return the corresponding `_i` input.
//
//    2.  Mixed read-only / read-write:
//          DISPSTAT bits 0-2  → vblank/hblank/vcount-match status (RO).
//          SOUNDCNT_X bits 0-3 → DMG sound channel play status (RO).
//        Writes affect the writable bits; reads splice in hardware bits.
//
//    3.  IF — write-1-to-clear:
//          Hardware pulses on `irq_request_i` set bits; CPU writes with bit=1
//          clear them. Hardware-set takes priority on a same-cycle collision.
//
//    4.  FIFO_A / FIFO_B (Direct Sound):
//          Write-only, no storage — drive `fifo_*_we_o` + `fifo_*_data_o`
//          strobes for the sound DMA path to consume.
//
//    5.  Misalignment:
//          Halfword (size=01) requires addr[0]=0; word (size=10) requires
//          addr[1:0]=00. Misalign sets `misalign_fault` and gates `we`.
//
//    6.  Affine reference reload:
//          A write to either half of BG2X/BG2Y/BG3X/BG3Y emits a one-cycle
//          `write_aff_*_o` pulse so the PPU reloads its internal reference.
// =============================================================================

`timescale 1ns / 1ps

module io_registers (
    input  wire        clk,
    input  wire        reset_n,

    // ---------------- CPU bus ----------------
    input  wire [9:0]  addr,           // byte address within 1 KB IO space
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,           // 00=byte 01=half 10=word
    input  wire        sign_extend,
    output wire        ready,
    output reg         misalign_fault,

    // ---------------- Hardware-driven read fields ----------------
    input  wire [15:0] vcount_i,           // REG_VCOUNT (only low 8 bits meaningful)
    input  wire        vblank_status_i,    // DISPSTAT bit 0 (W)
    input  wire        hblank_status_i,    // DISPSTAT bit 1 (G)
    input  wire        vcount_match_i,     // DISPSTAT bit 2 (Z)
    input  wire [15:0] keypad_i,           // REG_KEY (active low)
    input  wire [13:0] irq_request_i,      // pulses set the IF bits
    input  wire [3:0]  sound_status_i,     // SOUNDCNT_X bits 0-3
    input  wire [15:0] serial_data0_i,     // SCD0 (received)
    input  wire [15:0] serial_data1_i,     // SCD1
    input  wire [15:0] serial_data2_i,     // SCD2
    input  wire [15:0] serial_data3_i,     // SCD3

    // ---------------- Direct Sound FIFO write strobes ----------------
    output wire        fifo_a_we_o,
    output wire        fifo_b_we_o,
    output wire [3:0]  fifo_a_byteena_o,
    output wire [3:0]  fifo_b_byteena_o,
    output wire [31:0] fifo_a_data_o,
    output wire [31:0] fifo_b_data_o,

    // ---------------- Display ----------------
    output wire [15:0] dispcnt_o,
    output wire [15:0] dispstat_o,

    // ---------------- Backgrounds ----------------
    output wire [15:0] bg0cnt_o, bg1cnt_o, bg2cnt_o, bg3cnt_o,
    output wire [15:0] bg0hofs_o, bg0vofs_o,
    output wire [15:0] bg1hofs_o, bg1vofs_o,
    output wire [15:0] bg2hofs_o, bg2vofs_o,
    output wire [15:0] bg3hofs_o, bg3vofs_o,
    output wire [15:0] bg2pa_o, bg2pb_o, bg2pc_o, bg2pd_o,
    output wire [15:0] bg3pa_o, bg3pb_o, bg3pc_o, bg3pd_o,
    output wire [31:0] bg2x_o, bg2y_o,
    output wire [31:0] bg3x_o, bg3y_o,
    output reg  [1:0]  write_aff_x_o,
    output reg  [1:0]  write_aff_y_o,

    // ---------------- Window ----------------
    output wire [15:0] win0h_o, win1h_o, win0v_o, win1v_o,
    output wire [15:0] winin_o, winout_o,

    // ---------------- Effects ----------------
    output wire [31:0] mosaic_o,
    output wire [15:0] bldmod_o, colev_o, coley_o,

    // ---------------- Sound (master only — channel regs read via CPU) ----------------
    output wire [15:0] soundcnt_l_o, soundcnt_h_o, soundcnt_x_o, soundbias_o,

    // ---------------- DMA ----------------
    output wire [31:0] dma0sad_o, dma0dad_o,
    output wire [15:0] dma0cnt_l_o, dma0cnt_h_o,
    output wire [31:0] dma1sad_o, dma1dad_o,
    output wire [15:0] dma1cnt_l_o, dma1cnt_h_o,
    output wire [31:0] dma2sad_o, dma2dad_o,
    output wire [15:0] dma2cnt_l_o, dma2cnt_h_o,
    output wire [31:0] dma3sad_o, dma3dad_o,
    output wire [15:0] dma3cnt_l_o, dma3cnt_h_o,

    // ---------------- Timers ----------------
    output wire [15:0] tm0d_o, tm0cnt_o,
    output wire [15:0] tm1d_o, tm1cnt_o,
    output wire [15:0] tm2d_o, tm2cnt_o,
    output wire [15:0] tm3d_o, tm3cnt_o,

    // ---------------- Serial ----------------
    output wire [15:0] sccnt_l_o, sccnt_h_o,

    // ---------------- Keypad ----------------
    output wire [15:0] p1cnt_o,

    // ---------------- Link / JOY-bus ----------------
    output wire [15:0] r_o,
    output wire [15:0] hs_ctrl_o,
    output wire [31:0] joyre_o,
    output wire [31:0] joytr_o,
    output wire [31:0] jstat_o,

    // ---------------- Interrupts ----------------
    output wire [15:0] ie_o,
    output wire [15:0] if_o,
    output wire [15:0] wscnt_o,
    output wire [15:0] ime_o
);

    // -------------------------------------------------------------------------
    //  Halfword index constants (byte-address >> 1)
    // -------------------------------------------------------------------------
    localparam HW_DISPCNT      = 9'h000;
    localparam HW_GREENSWAP    = 9'h001;   // undocumented; reserved.
    localparam HW_DISPSTAT     = 9'h002;
    localparam HW_VCOUNT       = 9'h003;
    localparam HW_BG0CNT       = 9'h004;
    localparam HW_BG1CNT       = 9'h005;
    localparam HW_BG2CNT       = 9'h006;
    localparam HW_BG3CNT       = 9'h007;
    localparam HW_BG0HOFS      = 9'h008;
    localparam HW_BG0VOFS      = 9'h009;
    localparam HW_BG1HOFS      = 9'h00A;
    localparam HW_BG1VOFS      = 9'h00B;
    localparam HW_BG2HOFS      = 9'h00C;
    localparam HW_BG2VOFS      = 9'h00D;
    localparam HW_BG3HOFS      = 9'h00E;
    localparam HW_BG3VOFS      = 9'h00F;
    localparam HW_BG2PA        = 9'h010;
    localparam HW_BG2PB        = 9'h011;
    localparam HW_BG2PC        = 9'h012;
    localparam HW_BG2PD        = 9'h013;
    localparam HW_BG2X_L       = 9'h014;
    localparam HW_BG2X_H       = 9'h015;
    localparam HW_BG2Y_L       = 9'h016;
    localparam HW_BG2Y_H       = 9'h017;
    localparam HW_BG3PA        = 9'h018;
    localparam HW_BG3PB        = 9'h019;
    localparam HW_BG3PC        = 9'h01A;
    localparam HW_BG3PD        = 9'h01B;
    localparam HW_BG3X_L       = 9'h01C;
    localparam HW_BG3X_H       = 9'h01D;
    localparam HW_BG3Y_L       = 9'h01E;
    localparam HW_BG3Y_H       = 9'h01F;
    localparam HW_WIN0H        = 9'h020;
    localparam HW_WIN1H        = 9'h021;
    localparam HW_WIN0V        = 9'h022;
    localparam HW_WIN1V        = 9'h023;
    localparam HW_WININ        = 9'h024;
    localparam HW_WINOUT       = 9'h025;
    localparam HW_MOSAIC_L     = 9'h026;
    localparam HW_MOSAIC_H     = 9'h027;
    localparam HW_BLDMOD       = 9'h028;
    localparam HW_COLEV        = 9'h029;
    localparam HW_COLEY        = 9'h02A;
    localparam HW_SOUND1CNT_L  = 9'h030;
    localparam HW_SOUND1CNT_H  = 9'h031;
    localparam HW_SOUND1CNT_X  = 9'h032;
    localparam HW_SOUND2CNT_L  = 9'h034;
    localparam HW_SOUND2CNT_H  = 9'h036;
    localparam HW_SOUND3CNT_L  = 9'h038;
    localparam HW_SOUND3CNT_H  = 9'h039;
    localparam HW_SOUND3CNT_X  = 9'h03A;
    localparam HW_SOUND4CNT_L  = 9'h03C;
    localparam HW_SOUND4CNT_H  = 9'h03E;
    localparam HW_SOUNDCNT_L   = 9'h040;
    localparam HW_SOUNDCNT_H   = 9'h041;
    localparam HW_SOUNDCNT_X   = 9'h042;
    localparam HW_SOUNDBIAS    = 9'h044;
    localparam HW_WAVE_RAM0_L  = 9'h048;
    localparam HW_WAVE_RAM0_H  = 9'h049;
    localparam HW_WAVE_RAM1_L  = 9'h04A;
    localparam HW_WAVE_RAM1_H  = 9'h04B;
    localparam HW_WAVE_RAM2_L  = 9'h04C;
    localparam HW_WAVE_RAM2_H  = 9'h04D;
    localparam HW_WAVE_RAM3_L  = 9'h04E;
    localparam HW_WAVE_RAM3_H  = 9'h04F;
    localparam HW_FIFO_A_L     = 9'h050;
    localparam HW_FIFO_A_H     = 9'h051;
    localparam HW_FIFO_B_L     = 9'h052;
    localparam HW_FIFO_B_H     = 9'h053;
    localparam HW_DMA0SAD_L    = 9'h058;
    localparam HW_DMA0SAD_H    = 9'h059;
    localparam HW_DMA0DAD_L    = 9'h05A;
    localparam HW_DMA0DAD_H    = 9'h05B;
    localparam HW_DMA0CNT_L    = 9'h05C;
    localparam HW_DMA0CNT_H    = 9'h05D;
    localparam HW_DMA1SAD_L    = 9'h05E;
    localparam HW_DMA1SAD_H    = 9'h05F;
    localparam HW_DMA1DAD_L    = 9'h060;
    localparam HW_DMA1DAD_H    = 9'h061;
    localparam HW_DMA1CNT_L    = 9'h062;
    localparam HW_DMA1CNT_H    = 9'h063;
    localparam HW_DMA2SAD_L    = 9'h064;
    localparam HW_DMA2SAD_H    = 9'h065;
    localparam HW_DMA2DAD_L    = 9'h066;
    localparam HW_DMA2DAD_H    = 9'h067;
    localparam HW_DMA2CNT_L    = 9'h068;
    localparam HW_DMA2CNT_H    = 9'h069;
    localparam HW_DMA3SAD_L    = 9'h06A;
    localparam HW_DMA3SAD_H    = 9'h06B;
    localparam HW_DMA3DAD_L    = 9'h06C;
    localparam HW_DMA3DAD_H    = 9'h06D;
    localparam HW_DMA3CNT_L    = 9'h06E;
    localparam HW_DMA3CNT_H    = 9'h06F;
    localparam HW_TM0D         = 9'h080;
    localparam HW_TM0CNT       = 9'h081;
    localparam HW_TM1D         = 9'h082;
    localparam HW_TM1CNT       = 9'h083;
    localparam HW_TM2D         = 9'h084;
    localparam HW_TM2CNT       = 9'h085;
    localparam HW_TM3D         = 9'h086;
    localparam HW_TM3CNT       = 9'h087;
    localparam HW_SCD0         = 9'h090;
    localparam HW_SCD1         = 9'h091;
    localparam HW_SCD2         = 9'h092;
    localparam HW_SCD3         = 9'h093;
    localparam HW_SCCNT_L      = 9'h094;
    localparam HW_SCCNT_H      = 9'h095;
    localparam HW_KEY          = 9'h098;
    localparam HW_P1CNT        = 9'h099;
    localparam HW_R            = 9'h09A;   // 0x134 — link-port lines
    localparam HW_HS_CTRL      = 9'h0A0;   // 0x140
    localparam HW_JOYRE_L      = 9'h0A8;   // 0x150
    localparam HW_JOYRE_H      = 9'h0A9;
    localparam HW_JOYTR_L      = 9'h0AA;   // 0x154
    localparam HW_JOYTR_H      = 9'h0AB;
    localparam HW_JSTAT_L      = 9'h0AC;   // 0x158
    localparam HW_JSTAT_H      = 9'h0AD;
    localparam HW_IE           = 9'h100;
    localparam HW_IF           = 9'h101;
    localparam HW_WSCNT        = 9'h102;
    localparam HW_IME          = 9'h104;
    localparam HW_PAUSE        = 9'h180;

    // -------------------------------------------------------------------------
    //  Storage
    // -------------------------------------------------------------------------
    reg [15:0] regs [0:511];        // 512 halfwords = 1 KB
    reg [15:0] if_r;                // IF — special W1C semantics

    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1) regs[i] = 16'h0;
        if_r = 16'h0;
    end

    // -------------------------------------------------------------------------
    //  Address decode (mirrors sram.v)
    // -------------------------------------------------------------------------
    wire [8:0] hw_idx_lo = {addr[9:2], 1'b0};
    wire [8:0] hw_idx_hi = {addr[9:2], 1'b1};
    wire [1:0] byte_lane = addr[1:0];

    wire misalign_comb = (((size == 2'b01) && addr[0]) || ((size == 2'b10) && |addr[1:0])) && (we||rden);
    assign ready = ~misalign_comb;

    reg [3:0] byteena;
    always @(*) begin
        case (size)
            2'b00: begin
                case (byte_lane)
                    2'b00: byteena = 4'b0001;
                    2'b01: byteena = 4'b0010;
                    2'b10: byteena = 4'b0100;
                    2'b11: byteena = 4'b1000;
                endcase
            end
            2'b01: byteena = addr[1] ? 4'b1100 : 4'b0011;
            2'b10: byteena = 4'b1111;
            default: byteena = 4'b0000;
        endcase
    end

    reg [31:0] wdata_shifted;
    always @(*) begin
        case (size)
            2'b00: wdata_shifted = {4{wdata[7:0]}};
            2'b01: wdata_shifted = addr[1] ? {wdata[15:0], 16'h0000}
                                           : {16'h0000, wdata[15:0]};
            2'b10: wdata_shifted = wdata;
            default: wdata_shifted = 32'h0;
        endcase
    end

    wire write_en = we & ~misalign_comb;

    // -------------------------------------------------------------------------
    //  Per-halfword write/clear masks ("which bytes are being written this
    //  cycle to the lower / upper halfword of the targeted word?")
    // -------------------------------------------------------------------------
    wire we_lo_b0 = write_en & byteena[0];
    wire we_lo_b1 = write_en & byteena[1];
    wire we_hi_b0 = write_en & byteena[2];
    wire we_hi_b1 = write_en & byteena[3];

    // -------------------------------------------------------------------------
    //  IF (write-1-clear)
    // -------------------------------------------------------------------------
    wire        writes_if_lo  = we_lo_b0 | we_lo_b1;
    wire        writes_if_hi  = we_hi_b0 | we_hi_b1;
    wire        writes_if     = (hw_idx_lo == HW_IF && writes_if_lo) ||
                                (hw_idx_hi == HW_IF && writes_if_hi);

    wire [15:0] if_clr_value  = (hw_idx_hi == HW_IF) ? wdata_shifted[31:16]
                                                    : wdata_shifted[15:0];
    wire [1:0]  if_clr_be     = (hw_idx_hi == HW_IF) ? {we_hi_b1, we_hi_b0}
                                                    : {we_lo_b1, we_lo_b0};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            if_r <= 16'h0;
        end else begin
            // hardware sets first ...
            if_r[13:0] <= if_r[13:0] | irq_request_i;
            // ... then CPU 1-bits clear (per byte enable)
            if (writes_if) begin
                if (if_clr_be[0])
                    if_r[7:0]  <= (if_r[7:0]  | {2'b0, irq_request_i[7:0] & 8'hFF})
                                & ~if_clr_value[7:0];
                if (if_clr_be[1])
                    if_r[15:8] <= (if_r[15:8] | {2'b00, irq_request_i[13:8]})
                                & ~if_clr_value[15:8];
            end
        end
    end

    // -------------------------------------------------------------------------
    //  Generic register-array write
    //  Skips IF (handled above) and FIFO_A_L/H, FIFO_B_L/H (no storage; those
    //  drive `fifo_*_we_o`/`fifo_*_data_o` strobes instead).
    // -------------------------------------------------------------------------
    function automatic is_special_hw;
        input [8:0] idx;
        begin
            is_special_hw = (idx == HW_IF)        ||
                            (idx == HW_FIFO_A_L)  || (idx == HW_FIFO_A_H) ||
                            (idx == HW_FIFO_B_L)  || (idx == HW_FIFO_B_H);
        end
    endfunction

    wire commit_lo = write_en && |byteena[1:0] && !is_special_hw(hw_idx_lo);
    wire commit_hi = write_en && |byteena[3:2] && !is_special_hw(hw_idx_hi);

    wire writes_bg2x = (commit_lo && (hw_idx_lo == HW_BG2X_L))
                    || (commit_hi && (hw_idx_hi == HW_BG2X_H));
    wire writes_bg2y = (commit_lo && (hw_idx_lo == HW_BG2Y_L))
                    || (commit_hi && (hw_idx_hi == HW_BG2Y_H));
    wire writes_bg3x = (commit_lo && (hw_idx_lo == HW_BG3X_L))
                    || (commit_hi && (hw_idx_hi == HW_BG3X_H));
    wire writes_bg3y = (commit_lo && (hw_idx_lo == HW_BG3Y_L))
                    || (commit_hi && (hw_idx_hi == HW_BG3Y_H));

    always @(posedge clk) begin
        if (commit_lo) begin
            if (we_lo_b0) regs[hw_idx_lo][7:0]  <= wdata_shifted[7:0];
            if (we_lo_b1) regs[hw_idx_lo][15:8] <= wdata_shifted[15:8];
        end
        if (commit_hi) begin
            if (we_hi_b0) regs[hw_idx_hi][7:0]  <= wdata_shifted[23:16];
            if (we_hi_b1) regs[hw_idx_hi][15:8] <= wdata_shifted[31:24];
        end
    end

    // A write to either half of an affine reference reloads the PPU's
    // corresponding internal reference point.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_aff_x_o <= 2'b00;
            write_aff_y_o <= 2'b00;
        end else begin
            write_aff_x_o <= {writes_bg3x, writes_bg2x};
            write_aff_y_o <= {writes_bg3y, writes_bg2y};
        end
    end

    // -------------------------------------------------------------------------
    //  Direct Sound FIFO write strobes
    // -------------------------------------------------------------------------
    assign fifo_a_we_o      = write_en && ((hw_idx_lo == HW_FIFO_A_L && |byteena[1:0]) ||
                                           (hw_idx_hi == HW_FIFO_A_H && |byteena[3:2]) ||
                                           (hw_idx_lo == HW_FIFO_A_H && |byteena[1:0]));
    assign fifo_b_we_o      = write_en && ((hw_idx_lo == HW_FIFO_B_L && |byteena[1:0]) ||
                                           (hw_idx_hi == HW_FIFO_B_H && |byteena[3:2]) ||
                                           (hw_idx_lo == HW_FIFO_B_H && |byteena[1:0]));
    assign fifo_a_data_o    = wdata_shifted;
    assign fifo_b_data_o    = wdata_shifted;
    assign fifo_a_byteena_o = byteena;
    assign fifo_b_byteena_o = byteena;

    // -------------------------------------------------------------------------
    //  Pipelined CPU-side qualifiers (line up with the registered read mux)
    // -------------------------------------------------------------------------
    reg [1:0] size_q;
    reg [1:0] byte_lane_q;
    reg       sign_extend_q;
    reg       misalign_q;
    reg       we_q;
    reg [8:0] hw_idx_lo_q, hw_idx_hi_q;

    always @(posedge clk) begin
        size_q        <= size;
        byte_lane_q   <= byte_lane;
        sign_extend_q <= sign_extend;
        misalign_q    <= misalign_comb;
        we_q          <= we;
        if (rden) begin
            hw_idx_lo_q   <= hw_idx_lo;
            hw_idx_hi_q   <= hw_idx_hi;
        end
    end

    // -------------------------------------------------------------------------
    //  Read mux — combinational, then registered into `rdata`.
    //  Hardware-driven overrides (VCOUNT, KEY, IF, DISPSTAT.0-2,
    //  SOUNDCNT_X.0-3) are applied here so the registered data is correct.
    // -------------------------------------------------------------------------
    function automatic [15:0] read_hword;
        input [8:0] idx;
        input [15:0] base;
        begin
            case (idx)
                HW_VCOUNT:    read_hword = vcount_i;
                HW_KEY:       read_hword = keypad_i;
                HW_IF:        read_hword = if_r;
                HW_DISPSTAT:  read_hword = {base[15:3],
                                            vcount_match_i,
                                            hblank_status_i,
                                            vblank_status_i};
                HW_SOUNDCNT_X:read_hword = {base[15:4], sound_status_i};
                HW_SCD0:      read_hword = serial_data0_i;
                HW_SCD1:      read_hword = serial_data1_i;
                HW_SCD2:      read_hword = serial_data2_i;
                HW_SCD3:      read_hword = serial_data3_i;
                default:      read_hword = base;
            endcase
        end
    endfunction

    wire [15:0] rd_lo_q = read_hword(hw_idx_lo_q, regs[hw_idx_lo_q]);
    wire [15:0] rd_hi_q = read_hword(hw_idx_hi_q, regs[hw_idx_hi_q]);
    wire [31:0] rd_word = {rd_hi_q, rd_lo_q};

    // ARM-style size + sign extension on the registered data
    reg  [7:0]  byte_sel;
    reg  [15:0] half_sel;
    always @(*) begin
        case (byte_lane_q)
            2'b00: byte_sel = rd_word[ 7: 0];
            2'b01: byte_sel = rd_word[15: 8];
            2'b10: byte_sel = rd_word[23:16];
            2'b11: byte_sel = rd_word[31:24];
        endcase
        half_sel = byte_lane_q[1] ? rd_word[31:16] : rd_word[15:0];

        case (size_q)
            2'b00: rdata = sign_extend_q ? {{24{byte_sel[7]}},  byte_sel}
                                         : {24'h0,  byte_sel};
            2'b01: rdata = sign_extend_q ? {{16{half_sel[15]}}, half_sel}
                                         : {16'h0,  half_sel};
            2'b10: rdata = rd_word;
            default: rdata = 32'h0;
        endcase

        misalign_fault = misalign_q & we_q;
    end

    // -------------------------------------------------------------------------
    //  Named outputs (combinational view of the storage)
    // -------------------------------------------------------------------------
    assign dispcnt_o   = regs[HW_DISPCNT];
    assign dispstat_o  = {regs[HW_DISPSTAT][15:3],
                          vcount_match_i, hblank_status_i, vblank_status_i};

    assign bg0cnt_o    = regs[HW_BG0CNT];
    assign bg1cnt_o    = regs[HW_BG1CNT];
    assign bg2cnt_o    = regs[HW_BG2CNT];
    assign bg3cnt_o    = regs[HW_BG3CNT];
    assign bg0hofs_o   = regs[HW_BG0HOFS];
    assign bg0vofs_o   = regs[HW_BG0VOFS];
    assign bg1hofs_o   = regs[HW_BG1HOFS];
    assign bg1vofs_o   = regs[HW_BG1VOFS];
    assign bg2hofs_o   = regs[HW_BG2HOFS];
    assign bg2vofs_o   = regs[HW_BG2VOFS];
    assign bg3hofs_o   = regs[HW_BG3HOFS];
    assign bg3vofs_o   = regs[HW_BG3VOFS];
    assign bg2pa_o     = regs[HW_BG2PA];
    assign bg2pb_o     = regs[HW_BG2PB];
    assign bg2pc_o     = regs[HW_BG2PC];
    assign bg2pd_o     = regs[HW_BG2PD];
    assign bg3pa_o     = regs[HW_BG3PA];
    assign bg3pb_o     = regs[HW_BG3PB];
    assign bg3pc_o     = regs[HW_BG3PC];
    assign bg3pd_o     = regs[HW_BG3PD];
    assign bg2x_o      = {regs[HW_BG2X_H], regs[HW_BG2X_L]};
    assign bg2y_o      = {regs[HW_BG2Y_H], regs[HW_BG2Y_L]};
    assign bg3x_o      = {regs[HW_BG3X_H], regs[HW_BG3X_L]};
    assign bg3y_o      = {regs[HW_BG3Y_H], regs[HW_BG3Y_L]};

    assign win0h_o     = regs[HW_WIN0H];
    assign win1h_o     = regs[HW_WIN1H];
    assign win0v_o     = regs[HW_WIN0V];
    assign win1v_o     = regs[HW_WIN1V];
    assign winin_o     = regs[HW_WININ];
    assign winout_o    = regs[HW_WINOUT];

    assign mosaic_o    = {regs[HW_MOSAIC_H], regs[HW_MOSAIC_L]};
    assign bldmod_o    = regs[HW_BLDMOD];
    assign colev_o     = regs[HW_COLEV];
    assign coley_o     = regs[HW_COLEY];

    assign soundcnt_l_o = regs[HW_SOUNDCNT_L];
    assign soundcnt_h_o = regs[HW_SOUNDCNT_H];
    assign soundcnt_x_o = {regs[HW_SOUNDCNT_X][15:4], sound_status_i};
    assign soundbias_o  = regs[HW_SOUNDBIAS];

    assign dma0sad_o    = {regs[HW_DMA0SAD_H], regs[HW_DMA0SAD_L]};
    assign dma0dad_o    = {regs[HW_DMA0DAD_H], regs[HW_DMA0DAD_L]};
    assign dma0cnt_l_o  = regs[HW_DMA0CNT_L];
    assign dma0cnt_h_o  = regs[HW_DMA0CNT_H];
    assign dma1sad_o    = {regs[HW_DMA1SAD_H], regs[HW_DMA1SAD_L]};
    assign dma1dad_o    = {regs[HW_DMA1DAD_H], regs[HW_DMA1DAD_L]};
    assign dma1cnt_l_o  = regs[HW_DMA1CNT_L];
    assign dma1cnt_h_o  = regs[HW_DMA1CNT_H];
    assign dma2sad_o    = {regs[HW_DMA2SAD_H], regs[HW_DMA2SAD_L]};
    assign dma2dad_o    = {regs[HW_DMA2DAD_H], regs[HW_DMA2DAD_L]};
    assign dma2cnt_l_o  = regs[HW_DMA2CNT_L];
    assign dma2cnt_h_o  = regs[HW_DMA2CNT_H];
    assign dma3sad_o    = {regs[HW_DMA3SAD_H], regs[HW_DMA3SAD_L]};
    assign dma3dad_o    = {regs[HW_DMA3DAD_H], regs[HW_DMA3DAD_L]};
    assign dma3cnt_l_o  = regs[HW_DMA3CNT_L];
    assign dma3cnt_h_o  = regs[HW_DMA3CNT_H];

    assign tm0d_o       = regs[HW_TM0D];
    assign tm0cnt_o     = regs[HW_TM0CNT];
    assign tm1d_o       = regs[HW_TM1D];
    assign tm1cnt_o     = regs[HW_TM1CNT];
    assign tm2d_o       = regs[HW_TM2D];
    assign tm2cnt_o     = regs[HW_TM2CNT];
    assign tm3d_o       = regs[HW_TM3D];
    assign tm3cnt_o     = regs[HW_TM3CNT];

    assign sccnt_l_o    = regs[HW_SCCNT_L];
    assign sccnt_h_o    = regs[HW_SCCNT_H];

    assign p1cnt_o      = regs[HW_P1CNT];

    assign r_o          = regs[HW_R];
    assign hs_ctrl_o    = regs[HW_HS_CTRL];
    assign joyre_o      = {regs[HW_JOYRE_H], regs[HW_JOYRE_L]};
    assign joytr_o      = {regs[HW_JOYTR_H], regs[HW_JOYTR_L]};
    assign jstat_o      = {regs[HW_JSTAT_H], regs[HW_JSTAT_L]};

    assign ie_o         = regs[HW_IE];
    assign if_o         = if_r;
    assign wscnt_o      = regs[HW_WSCNT];
    assign ime_o        = regs[HW_IME];

endmodule
