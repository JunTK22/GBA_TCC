// =============================================================================
//  gba_rev0.v
//  DE1-SoC synthesis top for the ARM7TDMI/GBA bring-up system.
//
//  Active system paths:
//      ARM7TDMI + DMA0..3 -> bus_arbiter -> bus_controller -> memory regions
//      IO registers + timers -> IF/IE/IME, DMA control, WAITCNT, and HALTCNT
//      IO register controls -> PPU -> VRAM/OAM/palette fetch ports
//      DE1-SoC KEY[1:3] -> synchronized GBA KEYINPUT A/B/Start bits
//      GPIO_1[35:32] -> debounced GBA KEYINPUT Up/Left/Right/Down bits
//
//  The CPU, DMA engines, and PPU use the 17 MHz PLL `clock_cpu` output. Local
//  memories, the IO register file, and the SDRAM host wrapper use the dedicated
//  inverse output, `clock_cpu_n`, for the synchronous-read timing convention.
//  PPU-RAM ready is sampled for DMA so an inverse-edge collision wait remains
//  visible at the next DMA state-machine edge. Registered CPU `nWAIT`
//  additionally accounts for DMA pending/active ownership and HALT state.
//
//  The bus preserves the last accepted CPU opcode for GBA open-bus reads and
//  BIOS protection. DMA breaks the CPU sequential stream, so the first accepted
//  CPU cycle after DMA is exposed as non-sequential. A BIOS-qualified HALTCNT
//  write stops the gated core clock; DMA-originated HALT retains the parked CPU
//  bus cycle for two extra inverse-clock recovery edges after wake.
//
//  The PPU drives DISPSTAT/VCOUNT state, video IRQ requests, and VBlank/HBlank
//  DMA start events. Its rendered pixel and blanking outputs are not yet routed
//  to the board VGA pins.
//
//  The default build keeps EWRAM, writable PAK ROM, and Cart RAM in SDRAM.
//  `USE_ONCHIP_GAMEPAK` selects the M10K-backed, WAITCNT-timed ROM used by the
//  exact-top hw-test harness. Access size, SEQ, and sign-extension controls come
//  from the currently selected CPU or DMA master.
// =============================================================================

module gba_rev0(

	//////////// Audio //////////
	input 		          		AUD_ADCDAT,
	inout 		          		AUD_ADCLRCK,
	inout 		          		AUD_BCLK,
	output		          		AUD_DACDAT,
	inout 		          		AUD_DACLRCK,
	output		          		AUD_XCK,

	//////////// CLOCK //////////
	input 		          		CLOCK2_50,
	input 		          		CLOCK3_50,
	input 		          		CLOCK4_50,
	input 		          		CLOCK_50,

	//////////// SDRAM //////////
	output		    [12:0]		DRAM_ADDR,
	output		     [1:0]		DRAM_BA,
	output		          		DRAM_CAS_N,
	output		          		DRAM_CKE,
	output		          		DRAM_CLK,
	output		          		DRAM_CS_N,
	inout 		    [15:0]		DRAM_DQ,
	output		          		DRAM_LDQM,
	output		          		DRAM_RAS_N,
	output		          		DRAM_UDQM,
	output		          		DRAM_WE_N,

	//////////// I2C for Audio and Video-In //////////
	output		          		FPGA_I2C_SCLK,
	inout 		          		FPGA_I2C_SDAT,

	//////////// SEG7 //////////
	output		     [6:0]		HEX0,
	output		     [6:0]		HEX1,
	output		     [6:0]		HEX2,
	output		     [6:0]		HEX3,
	output		     [6:0]		HEX4,
	output		     [6:0]		HEX5,

	//////////// KEY //////////
	input 		     [3:0]		KEY,

	//////////// LED //////////
	output		     [9:0]		LEDR,

	//////////// SW //////////
	input 		     [9:0]		SW,

	//////////// VGA //////////
	output		          		VGA_BLANK_N,
	output		     [7:0]		VGA_B,
	output		          		VGA_CLK,
	output		     [7:0]		VGA_G,
	output		          		VGA_HS,
	output		     [7:0]		VGA_R,
	output		          		VGA_SYNC_N,
	output		          		VGA_VS,

	//////////// GPIO_0, GPIO_0 connect to GPIO Default //////////
	inout 		    [35:0]		GPIO_0,

	//////////// GPIO_1, GPIO_1 connect to GPIO Default //////////
	inout 		    [35:0]		GPIO_1
);

// The default profile preserves the existing synthetic-BIOS and writable
// SDRAM-backed PAK regression. Authentic cartridge builds override all three
// parameters with the retail BIOS MIF, one converted .gba MIF, and enable=1.
//
// Converted hw-test Game Pak images live in code/hw-test/mif/ (gitignored).
// Only one MIF is baked into the M10K per bitstream, so select a test by
// pointing GAMEPAK_INIT_FILE at one of these localparams and recompiling.
localparam MIF_128KB_BOUNDARY   = "code/hw-test/mif/128kb-boundary.mif";
localparam MIF_BGPD             = "code/hw-test/mif/bgpd.mif";
localparam MIF_BGX              = "code/hw-test/mif/bgx.mif";
localparam MIF_BURST_INTO_TEARS = "code/hw-test/mif/burst-into-tears.mif";
localparam MIF_DISPCNT_LATCH    = "code/hw-test/mif/dispcnt-latch.mif";
localparam MIF_FORCE_NSEQ_ACCESS= "code/hw-test/mif/force-nseq-access.mif";
localparam MIF_GREENSWAP        = "code/hw-test/mif/greenswap.mif";
localparam MIF_HALTCNT          = "code/hw-test/mif/haltcnt.mif";
localparam MIF_IRQ_DELAY        = "code/hw-test/mif/irq-delay.mif";
localparam MIF_LATCH            = "code/hw-test/mif/latch.mif";
localparam MIF_RAM_ACCESS_TIMING= "code/hw-test/mif/ram-access-timing.mif";
localparam MIF_RELOAD           = "code/hw-test/mif/reload.mif";
localparam MIF_SPRITE_HMOSAIC   = "code/hw-test/mif/sprite-hmosaic.mif";
localparam MIF_START_DELAY      = "code/hw-test/mif/start-delay.mif";
localparam MIF_START_STOP       = "code/hw-test/mif/start-stop.mif";
localparam MIF_STATUS_IRQ_DMA   = "code/hw-test/mif/status-irq-dma.mif";
localparam MIF_VRAM_MIRROR      = "code/hw-test/mif/vram-mirror.mif";

parameter BIOS_INIT_FILE = "code/hw-test/mif/GBA_bios.mif";
parameter GAMEPAK_INIT_FILE = MIF_RAM_ACCESS_TIMING;  // <-- select hw-test here
parameter USE_ONCHIP_GAMEPAK = 1'b1;

//=======================================================
//  REG/WIRE declarations
//=======================================================

wire clock_cpu;
wire clock_cpu_n;
wire clock_sdram;
wire clock_sdram_d;
wire pll_lock;
reg test_clk = 0;

wire clock = clock_cpu;
wire clock_n = clock_cpu_n;
//assign clock = CLOCK_50;
//assign clock_n = !CLOCK_50;
//wire clock = clock_cpu;
//wire clock_n = !clock_cpu;

wire nrst;

wire tap_en;

// The DE1-SoC push-buttons are active-low and asynchronous to clock_n. The
// board debounces them in hardware; these two stages provide metastability
// containment before KEYINPUT is sampled by io_registers on clock_n.
(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON"} *)
reg [2:0] keypad_meta_n;
(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON"} *)
reg [2:0] keypad_sync_n;

always @(posedge clock_n or negedge nrst) begin
    if (!nrst) begin
        keypad_meta_n <= 3'b111;
        keypad_sync_n <= 3'b111;
    end else begin
        keypad_meta_n <= KEY[3:1];
        keypad_sync_n <= keypad_meta_n;
    end
end

// D-pad on GPIO_1[35:32] = {Up, Left, Right, Down}: external push-buttons to
// GND with the FPGA weak pull-ups (QSF), so active-low like KEY. They are not
// debounced on the board: after the two synchronizer stages, a new state is
// accepted only once it has been stable for 2^16 clock_n cycles (~3.9 ms).
(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON"} *)
reg [3:0] dpad_meta_n;
(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON"} *)
reg [3:0] dpad_sync_n;
reg [3:0] dpad_n;
reg [15:0] dpad_stable_count;

always @(posedge clock_n or negedge nrst) begin
    if (!nrst) begin
        dpad_meta_n <= 4'b1111;
        dpad_sync_n <= 4'b1111;
        dpad_n <= 4'b1111;
        dpad_stable_count <= 16'd0;
    end else begin
        dpad_meta_n <= GPIO_1[35:32];
        dpad_sync_n <= dpad_meta_n;
        if (dpad_sync_n == dpad_n)
            dpad_stable_count <= 16'd0;
        else if (&dpad_stable_count) begin
            dpad_n <= dpad_sync_n;
            dpad_stable_count <= 16'd0;
        end else
            dpad_stable_count <= dpad_stable_count + 16'd1;
    end
end

// KEYINPUT bits: 0=A, 1=B, 3=Start, 4=Right, 5=Left, 6=Up, 7=Down.
// Select and the shoulder buttons remain released.
wire [15:0] keypad_input = {6'b000000, 2'b11,
                            dpad_n[0], dpad_n[3], dpad_n[2], dpad_n[1],
                            keypad_sync_n[2], 1'b1,
                            keypad_sync_n[1:0]};

wire [31:0] r [0:15];

wire [31:0] din;
wire [31:0] addr_bus;
wire [31:0] addr_cpu;
wire [31:0] addr_src_dma0, addr_dst_dma0;
wire [31:0] addr_src_dma1, addr_dst_dma1;
wire [31:0] addr_src_dma2, addr_dst_dma2;
wire [31:0] addr_src_dma3, addr_dst_dma3;

wire [31:0] CPSR;

wire nRW;
wire nRW_CPU;
wire nMREQ_cpu;
wire SEQ_cpu;
wire nOPC_cpu;
wire SEQ;
wire [1:0] MAS;
wire [1:0] MAS_cpu;

wire sign_extend;

wire [31:0] data_bus;
wire [31:0] data_bios;
wire [31:0] data_ewram;
wire [31:0] data_iwram;
wire [31:0] data_ioram;
wire [31:0] data_palram;
wire [31:0] data_vram;
wire [31:0] data_oam;
wire [31:0] data_pakrom;
wire [31:0] data_cartram;
wire [31:0] data_main;
wire [31:0] data_cpu;
wire [31:0] data_dma0;
wire [31:0] data_dma1;
wire [31:0] data_dma2;
wire [31:0] data_dma3;

wire [31:0] data_sdram;
wire [31:0] data_gamepak;
reg  [31:0] cpu_open_bus = 32'd0;
reg         cpu_exec_bios = 1'b0;
reg         cpu_exec_gamepak = 1'b0;

wire        rden_bios;
wire        rden_ewram;
wire        rden_iwram;
wire        rden_ioram;
wire        rden_palram;
wire        rden_vram;
wire        rden_oam;
wire        rden_pakrom;
wire        rden_cartram;

wire		we_ewram;
wire		we_iwram;
wire		we_ioram;
wire		we_palram;
wire		we_vram;
wire		we_oam;
wire		we_pakrom; // Used to load Game ROM
wire		we_cartram;

// DMA control registers (io_registers -> dma)
wire [3:0]  dma_active;
wire [3:0]  dma_pending;
wire [3:0]  dma_request;
wire [3:0]  dma_disable;

wire [31:0]	dma0sad_o;
wire [31:0]	dma0dad_o;
wire [15:0]	dma0cnt_l_o;
wire [15:0]	dma0cnt_h_o;
wire        wr_en_dma0;
wire		nirq_dma0;

wire [31:0]	dma1sad_o;
wire [31:0]	dma1dad_o;
wire [15:0]	dma1cnt_l_o;
wire [15:0]	dma1cnt_h_o;
wire        wr_en_dma1;
wire		nirq_dma1;

wire [31:0]	dma2sad_o;
wire [31:0]	dma2dad_o;
wire [15:0]	dma2cnt_l_o;
wire [15:0]	dma2cnt_h_o;
wire        wr_en_dma2;
wire		nirq_dma2;

wire [31:0]	dma3sad_o;
wire [31:0]	dma3dad_o;
wire [15:0]	dma3cnt_l_o;
wire [15:0]	dma3cnt_h_o;
wire        wr_en_dma3;
wire		nirq_dma3;

wire [1:0] MAS_dma0;
wire [1:0] MAS_dma1;
wire [1:0] MAS_dma2;
wire [1:0] MAS_dma3;
wire       SEQ_dma0;
wire       SEQ_dma1;
wire       SEQ_dma2;
wire       SEQ_dma3;

// A pending or active higher-priority DMA pauses lower channels in place.
// Direction must likewise come only from the fixed-priority selected owner;
// otherwise a held lower STORE can turn a higher-priority LOAD into a write.
wire [3:0] dma_ownership = dma_pending | dma_active;
wire [3:0] dma_priority_hold = {|dma_ownership[2:0],
                                |dma_ownership[1:0],
                                dma_ownership[0], 1'b0};
wire dma_write_phase = dma_active[0] ? wr_en_dma0 :
                       dma_active[1] ? wr_en_dma1 :
                       dma_active[2] ? wr_en_dma2 :
                       dma_active[3] ? wr_en_dma3 : 1'b0;

// PPU register values from io_registers. These are written on clock_n and are
// stable for half a CPU cycle before the PPU samples them on clock.
wire [15:0] ppu_dispcnt;
wire        ppu_greenswap;
wire [15:0] ppu_dispstat;
wire [15:0] ppu_bg0cnt, ppu_bg1cnt, ppu_bg2cnt, ppu_bg3cnt;
wire [15:0] ppu_bg0hofs, ppu_bg0vofs;
wire [15:0] ppu_bg1hofs, ppu_bg1vofs;
wire [15:0] ppu_bg2hofs, ppu_bg2vofs;
wire [15:0] ppu_bg3hofs, ppu_bg3vofs;
wire [15:0] ppu_bg2pa, ppu_bg2pb, ppu_bg2pc, ppu_bg2pd;
wire [15:0] ppu_bg3pa, ppu_bg3pb, ppu_bg3pc, ppu_bg3pd;
wire [31:0] ppu_bg2x, ppu_bg2y, ppu_bg3x, ppu_bg3y;
wire [1:0]  ppu_write_aff_x, ppu_write_aff_y;
wire [15:0] ppu_win0h, ppu_win1h, ppu_win0v, ppu_win1v;
wire [15:0] ppu_winin, ppu_winout;
wire [31:0] ppu_mosaic;
wire [15:0] ppu_bldmod, ppu_colev, ppu_coley;

wire        ppu_bg_vram_read;
wire        ppu_bg_vram_contention;
wire [16:0] ppu_bg_vram_address;
wire [15:0] ppu_bg_vram_read_data;
wire        ppu_obj_vram_read;
wire [14:0] ppu_obj_vram_address;
wire [15:0] ppu_obj_vram_read_data;
wire        ppu_oam_read;
wire [7:0]  ppu_oam_address;
wire [31:0] ppu_oam_read_data;
wire        ppu_palette_read;
wire [8:0]  ppu_palette_address;
wire [15:0] ppu_palette_read_data;
wire [10:0] ppu_tick;
wire [7:0]  ppu_scanline;

// CPU-visible LCD timing leads the renderer's scanline rollover. VCOUNT and
// VBlank advance during the final eight renderer cycles; HBlank has its own
// measured status window. IRQ and DMA request phases are kept separate below
// because they do not coincide with every visible flag edge.
wire [7:0] ppu_vcount = (ppu_tick >= 11'd1224)
                      ? ((ppu_scanline == 8'd227)
                         ? 8'd0 : ppu_scanline + 1'b1)
                      : ppu_scanline;
wire ppu_vblank_status = (ppu_vcount >= 8'd160)
                       && (ppu_vcount <= 8'd226);
wire ppu_hblank_status = (ppu_tick >= 11'd999)
                       && (ppu_tick < 11'd1224);
wire ppu_vcount_match = ppu_vcount == ppu_dispstat[15:8];
wire ppu_vblank_start = (ppu_tick == 11'd1226)
                      && (ppu_scanline == 8'd159);
wire ppu_hblank_start = ppu_tick == 11'd1001;
wire ppu_hblank_dma_start = (ppu_tick == 11'd1001)
                           && (ppu_scanline < 8'd160);
wire ppu_frame_start = (ppu_tick == 11'd1228)
                     && (ppu_scanline == 8'd227);
wire ppu_video_line_start = (ppu_tick == 11'd1229)
                          && (ppu_scanline >= 8'd1)
                          && (ppu_scanline <= 8'd160);
reg ppu_video_dma_armed = 1'b0;

// DMA3 video capture is enabled for a frame only if special timing was already
// programmed when that frame began. Requests then cover VCOUNT 2 through 161;
// enabling DMA3 after VCOUNT becomes 0 therefore waits until the next frame.
always @(posedge clock or negedge nrst) begin
    if (!nrst)
        ppu_video_dma_armed <= 1'b0;
    else if (ppu_frame_start)
        ppu_video_dma_armed <= dma3cnt_h_o[15] &&
                               (dma3cnt_h_o[13:12] == 2'b11);
end

wire ppu_video_dma_start = ppu_video_dma_armed && ppu_video_line_start;

reg ppu_vcount_match_q;
reg ppu_vcount_match_qq;
reg ppu_vcount_match_qqq;
reg ppu_vcount_irq;
always @(posedge clock) begin
    if (!nrst) begin
        ppu_vcount_match_q <= 1'b0;
        ppu_vcount_match_qq <= 1'b0;
        ppu_vcount_match_qqq <= 1'b0;
        ppu_vcount_irq <= 1'b0;
    end else begin
        ppu_vcount_match_q <= ppu_vcount_match;
        ppu_vcount_match_qq <= ppu_vcount_match_q;
        ppu_vcount_match_qqq <= ppu_vcount_match_qq;
        ppu_vcount_irq <= ppu_vcount_match_qq && !ppu_vcount_match_qqq;
    end
end

// PPU and DMA event pulses are latched by IF. The CPU sees an active-low IRQ
// only when the corresponding IE bit and IME are enabled. KEY[1:3] are now
// keypad inputs, so the former external IRQ/FIQ/abort sources are inactive.
wire [15:0] ie_reg;
wire [15:0] if_reg;
wire [15:0] wscnt_reg;
wire [15:0] ime_reg;
wire [15:0] tm0_count, tm0_control;
wire [15:0] tm1_count, tm1_control;
wire [15:0] tm2_count, tm2_control;
wire [15:0] tm3_count, tm3_control;
wire [3:0]  timer_irq;
wire        halt_request;
wire        postflg;
wire [13:0] irq_request = {2'b00, ~nirq_dma3, ~nirq_dma2,
                            ~nirq_dma1, ~nirq_dma0, 1'b0, timer_irq,
                            ppu_vcount_irq && ppu_dispstat[5],
                            ppu_hblank_start && ppu_dispstat[4],
                            ppu_vblank_start && ppu_dispstat[3]};
wire        irq_pending = ime_reg[0] && |(ie_reg & if_reg);
wire        nIRQ = !irq_pending;
reg         nIRQ_cpu = 1'b1;
wire        halt_wake = |(ie_reg & if_reg);

// IF, IE, and IME settle on clock_n. Propagate their combined request for one
// full CPU cycle before the decoder's existing nIRQ input synchronizer; HALT
// wake remains tied to enabled IF directly and is therefore unaffected.
always @(posedge clock or negedge nrst) begin
    if (!nrst)
        nIRQ_cpu <= 1'b1;
    else
        nIRQ_cpu <= nIRQ;
end

///////////////////////////////////////

wire busy;
wire [6:0] ready_mem;
reg nWAIT = 0;
reg cpu_halted = 0;
reg halt_transition_wait = 0;
reg halt_request_seen = 0;
reg [1:0] dma_halt_wake_wait = 0;
wire mem_ready = !busy && &ready_mem;
reg dma_ppu_ram_wait_sampled = 1'b0;
wire dma_mem_hold = !mem_ready || dma_ppu_ram_wait_sampled;
wire bus_request = (|dma_request) ||
                   (!(|dma_pending) && !(|dma_active) && !nMREQ_cpu);
wire cpu_cycle_accepted = bus_request && !(|dma_active) && nWAIT;
wire dma_cpu_hold = (|dma_pending) || (|dma_active);
reg dma_forced_nonseq = 0;
wire cpu_seq_bus = SEQ_cpu && !dma_forced_nonseq;
wire halt_new_request = halt_request && !halt_request_seen;
wire halt_entry_request = halt_new_request;
wire halt_delayed_wake = cpu_halted && halt_wake &&
                         !halt_transition_wait;
wire cpu_run_allowed = !halt_entry_request && !halt_transition_wait &&
                       !halt_delayed_wake &&
                       (halt_wake || !cpu_halted);
reg bus_request_toggle = 0;

// DMA breaks the CPU's external sequential stream. Keep the decoder's
// pipeline classification intact, but expose the first accepted CPU bus cycle
// after DMA as non-sequential to every memory region.
always @(posedge clock or negedge nrst) begin
    if (!nrst)
        dma_forced_nonseq <= 1'b0;
    else if (|dma_active)
        dma_forced_nonseq <= 1'b1;
    else if (cpu_cycle_accepted)
        dma_forced_nonseq <= 1'b0;
end

always @(posedge clock_n) begin
    // Palette, VRAM, and OAM can finish a one-wait collision on this inverse
    // edge, before DMA samples `halt`. Retain only those short PPU-RAM waits;
    // Game Pak and SDRAM already hold their live completion signals long enough
    // and include their own DMA bus-cycle accounting.
    dma_ppu_ram_wait_sampled <= (|dma_active) && !(&ready_mem[3:1]);
    // The current core performs architectural reset synchronously on its
    // nWAIT-gated clock, so reset must not hold that clock stopped. HALTCNT is
    // level-held with the stopped CPU bus. Consume each write once, hold the
    // CPU for the two HALT transition cycles, then let an enabled pending
    // interrupt release the held transfer.
    nWAIT <= (!dma_cpu_hold && mem_ready &&
              (!nrst || cpu_run_allowed));
end

always @(posedge clock_n or negedge nrst) begin
    if (!nrst) begin
        cpu_halted <= 1'b0;
        halt_transition_wait <= 1'b0;
        halt_request_seen <= 1'b0;
        dma_halt_wake_wait <= 2'd0;
    end else begin
        // The wake state and registered nWAIT provide the two recovery edges
        // after enabled IF becomes visible. IME does not gate HALT wake.

        if (!halt_request)
            halt_request_seen <= 1'b0;
        else if (halt_new_request)
            halt_request_seen <= 1'b1;

        if (halt_entry_request) begin
            cpu_halted <= 1'b1;
            halt_transition_wait <= 1'b1;
            // A DMA-originated HALTCNT write parks an interrupted CPU bus
            // cycle. Hardware exposes two additional recovery edges before
            // that parked cycle resumes after wake; ordinary HALT is unchanged.
            dma_halt_wake_wait <= (|dma_active) ? 2'd2 : 2'd0;
        end else if (halt_transition_wait) begin
            halt_transition_wait <= 1'b0;
            if (halt_wake && (dma_halt_wake_wait == 0))
                cpu_halted <= 1'b0;
        end else if (halt_wake) begin
            if (dma_halt_wake_wait != 0)
                dma_halt_wake_wait <= dma_halt_wake_wait - 1'b1;
            else
                cpu_halted <= 1'b0;
        end
    end
end

// Every accepted CPU or DMA cycle changes this token before the following
// inverse-clock request edge. It distinguishes identical consecutive Game Pak
// accesses without changing the level-held ready/nWAIT protocol.
always @(posedge clock or negedge nrst) begin
    if (!nrst)
        bus_request_toggle <= 1'b0;
    else if (bus_request && ((|dma_active) ? mem_ready : nWAIT))
        bus_request_toggle <= !bus_request_toggle;
end

// The external bus retains the most recently accepted CPU opcode. Thumb
// fetches occupy only one halfword, so both halves of the 32-bit latch carry
// the fetched opcode. Unmapped and write-only reads expose this value.
always @(posedge clock or negedge nrst) begin
    if (!nrst)
        cpu_open_bus <= 32'd0;
    else if (cpu_cycle_accepted && !nRW_CPU && !nOPC_cpu)
        cpu_open_bus <= (MAS_cpu == 2'b01) ? {2{data_bus[15:0]}}
                                             : data_bus;
end

// Remember the region supplying the accepted CPU opcode. The BIOS origin
// qualifies its protected system-control writes, including DMA transfers that
// run while a BIOS routine owns the stalled CPU. Game Pak prefetch may continue
// during that instruction's internal or non-cartridge data cycles.
always @(posedge clock or negedge nrst) begin
    if (!nrst) begin
        cpu_exec_bios <= 1'b0;
        cpu_exec_gamepak <= 1'b0;
    end else if (cpu_cycle_accepted && !nRW_CPU && !nOPC_cpu) begin
        cpu_exec_bios <= addr_cpu[27:14] == 14'd0;
        cpu_exec_gamepak <= (addr_cpu[27:25] == 3'b100) ||
                            (addr_cpu[27:25] == 3'b101) ||
                            (addr_cpu[27:25] == 3'b110);
    end
end
//=======================================================
//  Structural coding
//=======================================================

arm7tdmi_top arm7tdmi_top(
	.MCLK		(clock),
	.reset_n	(nrst),

	.nWAIT	(nWAIT),

		// DIN and DOUT are separate core ports. During a store the shared system
		// bus carries DOUT, while the decoder still consumes the opcode retained
		// by the preceding accepted fetch.
		.DIN	(nRW_CPU ? cpu_open_bus : data_bus),
	.A		(addr_cpu),
	.DOUT	(data_cpu),
	.nRW	(nRW_CPU),
	.MAS	(MAS_cpu),
	.nMREQ	(nMREQ_cpu),
	.SEQ	(SEQ_cpu),
		.nOPC	(nOPC_cpu),
	.nTRANS	(),

	.nENOUT	(),

	.sign_f	(sign_extend),

	.nIRQ	(nIRQ_cpu),
	.nFIQ	(1'b1),
	.ABORT	(1'b1),

	.tbit_out (LEDR[2]),

	.r0     (r[4'd0]),
    .r1     (r[4'd1]),
    .r2     (r[4'd2]),
    .r3     (r[4'd3]),
    .r4     (r[4'd4]),
    .r5     (r[4'd5]),
    .r6     (r[4'd6]),
    .r7     (r[4'd7]),
    .r8     (r[4'd8]),
    .r9     (r[4'd9]),
    .r10    (r[4'd10]),
    .r11    (r[4'd11]),
    .r12    (r[4'd12]),
    .r13    (r[4'd13]),
    .r14    (r[4'd14]),
    .r15    (r[4'd15]),
    .CPSR_o (CPSR)
);

bus_controller bus_controller(
	// input
	.rd_addr	(addr_bus),
	.nRW 	 	(nRW),
	.request	(bus_request),

	.data_bios   (data_bios),
	.data_ewram  (data_ewram),
	.data_iwram	 (data_iwram),
	.data_ioram	 (data_ioram),
	.data_palram (data_palram),
	.data_vram	 (data_vram),
	.data_oam	 (data_oam),
	.data_pakrom (data_pakrom),
		.data_cartram(data_cartram),
		.data_main	 (data_main),
		.data_open_bus (cpu_open_bus),

	// output
	.data_o		(data_bus),

	.rden_bios		(rden_bios),
	.rden_ewram		(rden_ewram),
	.rden_iwram		(rden_iwram),
	.rden_ioram 	(rden_ioram),
	.rden_palram	(rden_palram),
	.rden_vram		(rden_vram),
	.rden_oam		(rden_oam),
	.rden_pakrom	(rden_pakrom),
	.rden_cartram	(rden_cartram),

	.we_ewram	(we_ewram),
	.we_iwram	(we_iwram),
	.we_ioram	(we_ioram),
	.we_palram	(we_palram),
	.we_vram	(we_vram),
	.we_oam		(we_oam),
	.we_pakrom	(we_pakrom),
	.we_cartram	(we_cartram)
);

bus_arbiter bus_arbiter (
    .addr_cpu      (addr_cpu),
    .addr_src_dma0 (addr_src_dma0), .addr_dst_dma0 (addr_dst_dma0),
    .addr_src_dma1 (addr_src_dma1), .addr_dst_dma1 (addr_dst_dma1),
    .addr_src_dma2 (addr_src_dma2), .addr_dst_dma2 (addr_dst_dma2),
    .addr_src_dma3 (addr_src_dma3), .addr_dst_dma3 (addr_dst_dma3),

    .data_cpu      (data_cpu),
    .data_dma0     (data_dma0),
    .data_dma1     (data_dma1),
    .data_dma2     (data_dma2),
    .data_dma3     (data_dma3),

    .MAS_cpu       (MAS_cpu),
    .MAS_dma0      (MAS_dma0),
    .MAS_dma1      (MAS_dma1),
    .MAS_dma2      (MAS_dma2),
    .MAS_dma3      (MAS_dma3),

    .SEQ_cpu       (cpu_seq_bus),
    .SEQ_dma0      (SEQ_dma0),
    .SEQ_dma1      (SEQ_dma1),
    .SEQ_dma2      (SEQ_dma2),
    .SEQ_dma3      (SEQ_dma3),

    .nRW_CPU       (nRW_CPU),
    .wr_en_dma     (dma_write_phase),
    .dma_active    (dma_active),

    .addr_o        (addr_bus),
    .data_o        (data_main),
    .MAS           (MAS),
    .SEQ           (SEQ),
    .nRW           (nRW)
);

sdram_controller_top sdram_controller(
    .clock      (clock_n),
    .clock_sdram(clock_sdram),
    .nrst       (nrst),
    .MAS        (MAS),
    .sign_extend (sign_extend),
    .sram_wait  (wscnt_reg[1:0]),

    .rd_en      ((!USE_ONCHIP_GAMEPAK && rden_pakrom) ||
                 rden_ewram || rden_cartram),
    .wr_en      ((!USE_ONCHIP_GAMEPAK && we_pakrom) ||
                 we_ewram || we_cartram),
	
    .addr       (addr_bus[27:0]),
    .wr_data    (data_bus),
    .rd_data    (data_sdram),
    .busy       (busy),
    
    .SA         (DRAM_ADDR),
    .BA         (DRAM_BA),
    .CS_N       (DRAM_CS_N),
    .CKE        (DRAM_CKE),
    .RAS_N      (DRAM_RAS_N),
    .CAS_N      (DRAM_CAS_N),
    .WE_N       (DRAM_WE_N),
    .DQ         (DRAM_DQ),
    .DQM        ({DRAM_UDQM,DRAM_LDQM})
);

assign DRAM_CLK = clock_sdram_d;
assign data_pakrom = USE_ONCHIP_GAMEPAK ? data_gamepak : data_sdram;
assign data_ewram = data_sdram;
assign data_cartram = data_sdram;

bios #(
    .INIT_FILE (BIOS_INIT_FILE)
) bios (
    .clk	(clock_n),
    .addr	(addr_bus[13:0]),  // byte address within the 16 KiB BIOS
    .rdata	(data_bios),
    .rden	(rden_bios),
    .size	(MAS),             // 00=byte 01=half 10=word
    .sign_extend (sign_extend),
    .access_allowed (!(|dma_active) &&
                     ((!nOPC_cpu && (addr_cpu[27:14] == 14'd0)) ||
                      (r[15][31:14] == 18'd0))),
    .opcode_fetch   (!(|dma_active) && !nOPC_cpu),
    .ready          (),
    .misalign_fault ()
);

generate
    if (USE_ONCHIP_GAMEPAK) begin : generate_onchip_gamepak
        gamepak_rom #(
            .INIT_FILE (GAMEPAK_INIT_FILE)
        ) gamepak_rom (
            .clk            (clock_n),
            .nrst           (nrst),
            .addr           (addr_bus[27:0]),
            .rden           (rden_pakrom),
            .wren           (we_pakrom),
            .size           (MAS),
            .sign_extend    (sign_extend),
            .seq            (SEQ),
            .opcode_fetch   (!(|dma_active) && !nOPC_cpu),
            .cpu_exec_gamepak (cpu_exec_gamepak),
            .dma_access     (|dma_active),
            .request_toggle (bus_request_toggle),
            .waitcnt        (wscnt_reg),
            .rdata          (data_gamepak),
            .ready          (ready_mem[6])
        );
    end else begin : generate_sdram_gamepak
        assign data_gamepak = 32'd0;
        assign ready_mem[6] = 1'b1;
    end
endgenerate

//ewram ewram (
//    .clk	(clock_n),
//    .addr	(addr_bus),           // 256 KB byte address
//    .wdata	(data_bus),
//    .rdata	(data_ewram),
//    .we		(we_ewram),
//    .rden	(rden_ewram),
//    .size	(MAS),           // 0=byte, 1=halfword
//    .sign_extend (sign_extend),
//    .ready	(),
//    .misalign_fault	()
//);

iwram iwram (
    .clk	(clock_n),
    .addr	(addr_bus[14:0]),     // 32 KB byte address
    .wdata	(data_bus),
    .rdata	(data_iwram),
    .we		(we_iwram),
    .rden	(rden_iwram),
    .size	(MAS),           // 00=byte 01=half 10=word
    .sign_extend (sign_extend),
    .ready	(ready_mem[0]),
    .misalign_fault	()
);

palette_ram palette_ram (
    .clk	(clock_n),
    .addr	(addr_bus[9:0]),      // 1 KB byte address
    .wdata	(data_bus),
    .rdata	(data_palram),
    .we		(we_palram),
    .rden	(rden_palram),
    .size	(MAS),           // 0=byte, 1=halfword
    .sign_extend (sign_extend),
    .ready	(ready_mem[1]),
    .misalign_fault	(),
    .ppu_addr   (ppu_palette_address),
    .ppu_rden   (ppu_palette_read),
    .ppu_rdata  (ppu_palette_read_data),
    .force_blank (ppu_dispcnt[7])
);

vram vram (
    .clk	(clock_n),
    .addr	(addr_bus[16:0]),     // 128 KB byte address
    .wdata	(data_bus),
    .rdata	(data_vram),
    .we		(we_vram),
    .rden	(rden_vram),
    .size	(MAS),           // 0=byte, 1=halfword
    .sign_extend (sign_extend),
    .ready	(ready_mem[2]),
    .misalign_fault	(),
    .bg_addr    (ppu_bg_vram_address),
    .bg_rdata   (ppu_bg_vram_read_data),
    .bg_rden    (ppu_bg_vram_read),
    .bg_contention (ppu_bg_vram_contention),
    .obj_addr   (ppu_obj_vram_address),
    .obj_rdata  (ppu_obj_vram_read_data),
    .obj_rden   (ppu_obj_vram_read),
    .bg_mode    (ppu_dispcnt[2:0]),
    .force_blank (ppu_dispcnt[7])
);

oam oam (
    .clk	(clock_n),
    .addr	(addr_bus[9:0]),       // 1 KB byte address
    .wdata	(data_bus),
    .rdata	(data_oam),
    .we		(we_oam),
    .rden	(rden_oam),
    .size	(MAS),
    .sign_extend (sign_extend),
    .ready	(ready_mem[3]),
    .misalign_fault	(),
    .ppu_addr   (ppu_oam_address),
    .ppu_rden   (ppu_oam_read),
    .ppu_rdata  (ppu_oam_read_data),
    .force_blank (ppu_dispcnt[7])
);

// Cart RAM shares the SDRAM controller's `busy` stall path. Its former local
// ready contribution remains asserted so only the SDRAM completion gates it.
assign ready_mem[4] = 1'b1;

gba_timers gba_timers (
    .clk           (clock_n),
    .reset_n       (nrst),
    .addr          (addr_bus[11:0]),
    .wdata         (data_bus),
    .we            (we_ioram),
    .size          (MAS),
    .tm0_count_o   (tm0_count),
    .tm0_control_o (tm0_control),
    .tm1_count_o   (tm1_count),
    .tm1_control_o (tm1_control),
    .tm2_count_o   (tm2_count),
    .tm2_control_o (tm2_control),
    .tm3_count_o   (tm3_count),
    .tm3_control_o (tm3_control),
    .irq_o         (timer_irq)
);

io_registers io_registers (
    .clk	(clock_n),
    .reset_n	(nrst),
    //---------------- CPU bus ----------------
    .addr	(addr_bus[11:0]),
    .wdata	(data_bus),
    .open_bus_i (cpu_open_bus),
    .system_write_enable_i (cpu_exec_bios),
    .rdata	(data_ioram),
    .we		(we_ioram),
    .rden   (rden_ioram),
    .size	(MAS),             // 00=byte 01=half 10=word
    .sign_extend (sign_extend),
    .ready	(ready_mem[5]),
    .misalign_fault	(),
    //---------------- Hardware-driven read fields ----------------
    .vcount_i	({8'd0, ppu_vcount}),
    .vblank_status_i (ppu_vblank_status),
    .hblank_status_i (ppu_hblank_status),
    .vcount_match_i  (ppu_vcount_match_q),
    .keypad_i	(keypad_input), // REG_KEY (active low): A, B, and Start
    .irq_request_i (irq_request),
    .sound_status_i (4'd0),    // SOUNDCNT_X bits 0-3
    .serial_data0_i (16'd0),   // SCD0 (received)
    .serial_data1_i (16'd0),   // SCD1
    .serial_data2_i (16'd0),   // SCD2
    .serial_data3_i (16'd0),   // SCD3
    .tm0_count_i (tm0_count), .tm0_control_i (tm0_control),
    .tm1_count_i (tm1_count), .tm1_control_i (tm1_control),
    .tm2_count_i (tm2_count), .tm2_control_i (tm2_control),
    .tm3_count_i (tm3_count), .tm3_control_i (tm3_control),
    .dma_disable_i (dma_disable),
    //---------------- Direct Sound FIFO write strobes ----------------
    //  No sound DMA path wired yet — leave outputs open.
    .fifo_a_we_o	(),
    .fifo_b_we_o	(),
    .fifo_a_byteena_o (),
    .fifo_b_byteena_o (),
    .fifo_a_data_o	(),
    .fifo_b_data_o	(),
    //---------------- Display ----------------
    .dispcnt_o	(ppu_dispcnt),
    .greenswap_o (ppu_greenswap),
    .dispstat_o	(ppu_dispstat),
    //---------------- Backgrounds ----------------
    .bg0cnt_o (ppu_bg0cnt), .bg1cnt_o (ppu_bg1cnt),
    .bg2cnt_o (ppu_bg2cnt), .bg3cnt_o (ppu_bg3cnt),
    .bg0hofs_o (ppu_bg0hofs), .bg0vofs_o (ppu_bg0vofs),
    .bg1hofs_o (ppu_bg1hofs), .bg1vofs_o (ppu_bg1vofs),
    .bg2hofs_o (ppu_bg2hofs), .bg2vofs_o (ppu_bg2vofs),
    .bg3hofs_o (ppu_bg3hofs), .bg3vofs_o (ppu_bg3vofs),
    .bg2pa_o (ppu_bg2pa), .bg2pb_o (ppu_bg2pb),
    .bg2pc_o (ppu_bg2pc), .bg2pd_o (ppu_bg2pd),
    .bg3pa_o (ppu_bg3pa), .bg3pb_o (ppu_bg3pb),
    .bg3pc_o (ppu_bg3pc), .bg3pd_o (ppu_bg3pd),
    .bg2x_o (ppu_bg2x), .bg2y_o (ppu_bg2y),
    .bg3x_o (ppu_bg3x), .bg3y_o (ppu_bg3y),
    .write_aff_x_o (ppu_write_aff_x),
    .write_aff_y_o (ppu_write_aff_y),
    //---------------- Window ----------------
    .win0h_o (ppu_win0h), .win1h_o (ppu_win1h),
    .win0v_o (ppu_win0v), .win1v_o (ppu_win1v),
    .winin_o (ppu_winin), .winout_o (ppu_winout),
    //---------------- Effects ----------------
    .mosaic_o	(ppu_mosaic),
    .bldmod_o (ppu_bldmod),
    .colev_o (ppu_colev),
    .coley_o (ppu_coley),
    //---------------- Sound (master only — channel regs read via CPU) ----------------
    .soundcnt_l_o (), .soundcnt_h_o (), .soundcnt_x_o (), .soundbias_o (),
    //---------------- DMA ----------------
    .dma0sad_o      (dma0sad_o),
    .dma0dad_o      (dma0dad_o),
    .dma0cnt_l_o    (dma0cnt_l_o),
    .dma0cnt_h_o    (dma0cnt_h_o),
    .dma1sad_o      (dma1sad_o),
    .dma1dad_o      (dma1dad_o),
    .dma1cnt_l_o    (dma1cnt_l_o),
    .dma1cnt_h_o    (dma1cnt_h_o),
    .dma2sad_o      (dma2sad_o),
    .dma2dad_o      (dma2dad_o),
    .dma2cnt_l_o    (dma2cnt_l_o),
    .dma2cnt_h_o    (dma2cnt_h_o),
    .dma3sad_o      (dma3sad_o),
    .dma3dad_o      (dma3dad_o),
    .dma3cnt_l_o    (dma3cnt_l_o),
    .dma3cnt_h_o    (dma3cnt_h_o),
    //---------------- Timers ----------------
    .tm0d_o (), .tm0cnt_o (),
    .tm1d_o (), .tm1cnt_o (),
    .tm2d_o (), .tm2cnt_o (),
    .tm3d_o (), .tm3cnt_o (),
    //---------------- Serial ----------------
    .sccnt_l_o (), .sccnt_h_o (),
    //---------------- Keypad ----------------
    .p1cnt_o	(),
    //---------------- Link / JOY-bus ----------------
    .r_o		(),
    .hs_ctrl_o	(),
    .joyre_o	(),
    .joytr_o	(),
    .jstat_o	(),
    //---------------- Interrupts ----------------
    .ie_o		(ie_reg),
    .if_o		(if_reg),
    .wscnt_o	(wscnt_reg),
    .ime_o		(ime_reg),
    .halt_request_o (halt_request),
    .postflg_o (postflg)
);

// LCD adapter taps on the composed PPU output (declared before the PPU instance that drives them)
wire        lcd_ppu_valid;
wire [14:0] lcd_ppu_pixel;
wire        lcd_ppu_vblank;

ppu ppu (
    .clock                  (clock),
    .reset                  (!nrst),
    .enable                 (1'b1),
    .display_mode           (ppu_dispcnt[2:0]),
    .display_frame          (ppu_dispcnt[4]),
    .display_force_blank    (ppu_dispcnt[7]),
    .display_green_swap     (ppu_greenswap),
    .display_enable_obj     (ppu_dispcnt[12]),
    .display_enable_bg      (ppu_dispcnt[11:8]),
    .display_window         (ppu_dispcnt[14:13]),
    .display_obj_window     (ppu_dispcnt[15]),
    .display_obj_mapping    (ppu_dispcnt[6]),
    .display_hblank_free    (ppu_dispcnt[5]),
    .bg_size                ({ppu_bg3cnt[15:14], ppu_bg2cnt[15:14],
                              ppu_bg1cnt[15:14], ppu_bg0cnt[15:14]}),
    .bg_affine_wrap         ({ppu_bg3cnt[13], ppu_bg2cnt[13], 2'b00}),
    .bg_screen_base         ({ppu_bg3cnt[12:8], ppu_bg2cnt[12:8],
                              ppu_bg1cnt[12:8], ppu_bg0cnt[12:8]}),
    .bg_bpp8                ({ppu_bg3cnt[7], ppu_bg2cnt[7],
                              ppu_bg1cnt[7], ppu_bg0cnt[7]}),
    .bg_mosaic              ({ppu_bg3cnt[6], ppu_bg2cnt[6],
                              ppu_bg1cnt[6], ppu_bg0cnt[6]}),
    .bg_char_base           ({ppu_bg3cnt[3:2], ppu_bg2cnt[3:2],
                              ppu_bg1cnt[3:2], ppu_bg0cnt[3:2]}),
    .bg_priority            ({ppu_bg3cnt[1:0], ppu_bg2cnt[1:0],
                              ppu_bg1cnt[1:0], ppu_bg0cnt[1:0]}),
    .bg_off_x               ({ppu_bg3hofs, ppu_bg2hofs,
                              ppu_bg1hofs, ppu_bg0hofs}),
    .bg_off_y               ({ppu_bg3vofs, ppu_bg2vofs,
                              ppu_bg1vofs, ppu_bg0vofs}),
    .bg_aff_pa              ({ppu_bg3pa, ppu_bg2pa}),
    .bg_aff_pb              ({ppu_bg3pb, ppu_bg2pb}),
    .bg_aff_pc              ({ppu_bg3pc, ppu_bg2pc}),
    .bg_aff_pd              ({ppu_bg3pd, ppu_bg2pd}),
    .bg_aff_x               ({ppu_bg3x[27:0], ppu_bg2x[27:0]}),
    .bg_aff_y               ({ppu_bg3y[27:0], ppu_bg2y[27:0]}),
    .write_aff_x            (ppu_write_aff_x),
    .write_aff_y            (ppu_write_aff_y),
    .mosaic_bg_x            (ppu_mosaic[3:0]),
    .mosaic_bg_y            (ppu_mosaic[7:4]),
    .mosaic_obj_x           (ppu_mosaic[11:8]),
    .mosaic_obj_y           (ppu_mosaic[15:12]),
    .win0_x_start           (ppu_win0h[15:8]),
    .win0_x_end             (ppu_win0h[7:0]),
    .win0_y_start           (ppu_win0v[15:8]),
    .win0_y_end             (ppu_win0v[7:0]),
    .win1_x_start           (ppu_win1h[15:8]),
    .win1_x_end             (ppu_win1h[7:0]),
    .win1_y_start           (ppu_win1v[15:8]),
    .win1_y_end             (ppu_win1v[7:0]),
    .win0_control           (ppu_winin[5:0]),
    .win1_control           (ppu_winin[13:8]),
    .win_out_control        (ppu_winout[5:0]),
    .win_obj_control        (ppu_winout[13:8]),
    .blend_effect           (ppu_bldmod[7:6]),
    .blend_top_bg           (ppu_bldmod[3:0]),
    .blend_top_obj          (ppu_bldmod[4]),
    .blend_top_backdrop     (ppu_bldmod[5]),
    .blend_bottom_bg        (ppu_bldmod[11:8]),
    .blend_bottom_obj       (ppu_bldmod[12]),
    .blend_bottom_backdrop  (ppu_bldmod[13]),
    .blend_alpha_a          (ppu_colev[4:0]),
    .blend_alpha_b          (ppu_colev[12:8]),
    .blend_fade             (ppu_coley[4:0]),
    .bg_vram_read           (ppu_bg_vram_read),
    .bg_vram_contention      (ppu_bg_vram_contention),
    .bg_vram_address        (ppu_bg_vram_address),
    .bg_vram_read_data      (ppu_bg_vram_read_data),
    .obj_vram_read          (ppu_obj_vram_read),
    .obj_vram_address       (ppu_obj_vram_address),
    .obj_vram_read_data     (ppu_obj_vram_read_data),
    .oam_read               (ppu_oam_read),
    .oam_address            (ppu_oam_address),
    .oam_read_data          (ppu_oam_read_data),
    .palette_read           (ppu_palette_read),
    .palette_address        (ppu_palette_address),
    .palette_read_data      (ppu_palette_read_data),
    .output_valid           (lcd_ppu_valid),
    .output_pixel           (lcd_ppu_pixel),
    .output_hblank          (),
    .output_vblank          (lcd_ppu_vblank),
    .tick                   (ppu_tick),
    .scanline               (ppu_scanline)
);

// ---------------------------------------------------------------------------
// ILI9488 LCD display adapter (passive tap on the composed PPU output).
// This only consumes the previously-open output_valid/output_pixel/output_vblank;
// it adds NO load on GBA VRAM arbitration, DMA ownership, mem_ready, or nWAIT, so
// GBA behaviour (and the hw-test ROMs) is unchanged. Producer side on clock_cpu
// (17 MHz), 8080 write side on the unshifted clock_sdram (68 MHz) PLL output.
// GPIO_0 mapping follows FPGA_LCD_INTEGRATION.md: DB[15:0]=GPIO_0[15:0],
// CSX=[16], DCX=[17], WRX=[18], RESET=[19]. RDX is tied high externally.
wire        lcd_csx, lcd_dcx, lcd_wrx, lcd_rst_n;
wire        lcd_ppu_ready, lcd_frame_dropped, lcd_init_done;
wire [15:0] lcd_db;

lcd_top #(
    .HRES (16'd480),
    .VRES (16'd320),
    .NBUF (32)
) u_lcd (
    .clk_ppu       (clock_cpu),
    .clk_lcd       (clock_sdram),
    .nrst          (nrst),
    .init_en       (1'b1),
    .ppu_pixel     (lcd_ppu_pixel),
    .ppu_valid     (lcd_ppu_valid),
    .ppu_vblank    (lcd_ppu_vblank),
    .ppu_ready     (lcd_ppu_ready),       // advisory; PPU is never stalled
    .frame_dropped (lcd_frame_dropped),
    .lcd_csx       (lcd_csx),
    .lcd_dcx       (lcd_dcx),
    .lcd_wrx       (lcd_wrx),
    .lcd_rst_n     (lcd_rst_n),
    .lcd_db        (lcd_db),
    .init_done     (lcd_init_done)
);

assign GPIO_0[15:0] = lcd_db;
assign GPIO_0[16]   = lcd_csx;
assign GPIO_0[17]   = lcd_dcx;
assign GPIO_0[18]   = lcd_wrx;
assign GPIO_0[19]   = lcd_rst_n;
// GPIO_0[35:20] left unassigned (require QSF pin assignments before synthesis).

// ---------------------------------------------------------------------------
// LCD bring-up dashboard (panel disconnected). OBSERVATION ONLY: touches no LCD
// RTL, clocking, or SDC. All indicators are latched levels or divided-counter
// bits (raw us-wide 8080 strobes are invisible on LEDs).
// ---------------------------------------------------------------------------
// ~1 Hz heartbeat / blink source in the clock_sdram (68 MHz) domain.
reg [26:0] lcd_dbg_div = 27'd0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst) lcd_dbg_div <= 27'd0; else lcd_dbg_div <= lcd_dbg_div + 27'd1;

// Latch 8080 activity on each real write (WRX rising, CSX low), in clock_sdram.
// lcd_wr_count counts ONLY during init -> FREEZES at 0x46 (=70) after init_done,
// which is positive proof the initializer emitted the full sequence.
reg        lcd_wrx_d     = 1'b1;
reg [15:0] lcd_wr_count  = 16'd0;   // frozen at 70 after init
reg [7:0]  lcd_last_cmd  = 8'd0;    // last COMMAND byte: 0x29 after init; 2A/2B/2C while streaming
reg [15:0] lcd_frame_cnt = 16'd0;   // RAMWR (0x2C) count -> one per streamed frame
reg [26:0] lcd_wr_act    = 27'd0;   // per-write free counter -> streaming-activity blink
// Panel-side stream integrity: pixel strobes (DCX=1) between RAMWR (0x2C) and the next
// frame's CASET (0x2A) must be exactly 480*320 = 153600 per streamed frame.
reg [17:0] lcd_panel_pix      = 18'd0;
reg [17:0] lcd_last_panel_pix = 18'd0;
reg [7:0]  lcd_bad_panel_frames = 8'd0;
reg        lcd_panel_armed    = 1'b0;
always @(posedge clock_sdram or negedge nrst) begin
    if (!nrst) begin
        lcd_wrx_d <= 1'b1; lcd_wr_count <= 16'd0; lcd_last_cmd <= 8'd0;
        lcd_frame_cnt <= 16'd0; lcd_wr_act <= 27'd0;
        lcd_panel_pix <= 18'd0; lcd_last_panel_pix <= 18'd0;
        lcd_bad_panel_frames <= 8'd0; lcd_panel_armed <= 1'b0;
    end else begin
        lcd_wrx_d <= lcd_wrx;
        if (lcd_wrx && !lcd_wrx_d && !lcd_csx) begin       // one 8080 write
            lcd_wr_act <= lcd_wr_act + 27'd1;
            if (!lcd_dcx) begin                            // command byte (DCX=0)
                lcd_last_cmd <= lcd_db[7:0];
                if (lcd_db[7:0] == 8'h2C) lcd_frame_cnt <= lcd_frame_cnt + 16'd1;
                if ((lcd_db[7:0] == 8'h2A) && lcd_panel_armed) begin
                    lcd_last_panel_pix <= lcd_panel_pix;
                    if ((lcd_panel_pix != 18'd153600) && (lcd_bad_panel_frames != 8'hff))
                        lcd_bad_panel_frames <= lcd_bad_panel_frames + 8'd1;
                end
                if ((lcd_db[7:0] == 8'h2C) && lcd_init_done) begin
                    lcd_panel_pix   <= 18'd0;
                    lcd_panel_armed <= 1'b1;
                end
            end else begin
                lcd_panel_pix <= lcd_panel_pix + 18'd1;
            end
            if (!lcd_init_done) lcd_wr_count <= lcd_wr_count + 16'd1;
        end
    end
end

// Source-side stream integrity on clock_cpu: every visible scanline must deliver exactly 240
// PPU output pixels and every frame 38400; also count LCD FIFO frame drops. Sticky until reset.
reg [7:0]  lcd_line_q          = 8'd0;
reg        lcd_vbl_q           = 1'b1;
reg        lcd_src_seen        = 1'b0;
reg [8:0]  lcd_line_pix        = 9'd0;
reg [15:0] lcd_src_pix         = 16'd0;
reg [15:0] lcd_last_src_pix    = 16'd0;
reg [7:0]  lcd_bad_src_frames  = 8'd0;
reg [7:0]  lcd_bad_lines       = 8'd0;
reg [7:0]  lcd_bad_line_num    = 8'd0;
reg [8:0]  lcd_bad_line_pix    = 9'd0;
reg        lcd_drop_q          = 1'b0;
reg [7:0]  lcd_drops           = 8'd0;
always @(posedge clock_cpu or negedge nrst) begin
    if (!nrst) begin
        lcd_line_q <= 8'd0; lcd_vbl_q <= 1'b1; lcd_src_seen <= 1'b0;
        lcd_line_pix <= 9'd0; lcd_src_pix <= 16'd0; lcd_last_src_pix <= 16'd0;
        lcd_bad_src_frames <= 8'd0; lcd_bad_lines <= 8'd0;
        lcd_bad_line_num <= 8'd0; lcd_bad_line_pix <= 9'd0;
        lcd_drop_q <= 1'b0; lcd_drops <= 8'd0;
    end else begin
        lcd_line_q <= ppu_scanline;
        lcd_vbl_q  <= lcd_ppu_vblank;
        lcd_drop_q <= lcd_frame_dropped;
        if (lcd_frame_dropped && !lcd_drop_q && (lcd_drops != 8'hff))
            lcd_drops <= lcd_drops + 8'd1;

        if (ppu_scanline != lcd_line_q) begin              // scanline boundary
            if (lcd_src_seen && (lcd_line_q < 8'd160) && (lcd_line_pix != 9'd240)) begin
                if (lcd_bad_lines != 8'hff) lcd_bad_lines <= lcd_bad_lines + 8'd1;
                lcd_bad_line_num <= lcd_line_q;
                lcd_bad_line_pix <= lcd_line_pix;
            end
            lcd_line_pix <= {8'd0, lcd_ppu_valid};
        end else if (lcd_ppu_valid) begin
            lcd_line_pix <= lcd_line_pix + 9'd1;
        end

        if (lcd_vbl_q && !lcd_ppu_vblank) begin            // source frame boundary
            if (lcd_src_seen) begin
                lcd_last_src_pix <= lcd_src_pix;
                if ((lcd_src_pix != 16'd38400) && (lcd_bad_src_frames != 8'hff))
                    lcd_bad_src_frames <= lcd_bad_src_frames + 8'd1;
            end
            lcd_src_seen <= 1'b1;
            lcd_src_pix  <= {15'd0, lcd_ppu_valid};
        end else if (lcd_ppu_valid) begin
            lcd_src_pix <= lcd_src_pix + 16'd1;
        end
    end
end

// HEX word (shown when SW[8]=1). Crossing into the seg_display (clock_cpu) domain
// is an intentional relaxed, display-only path (values are static/slow), not a
// metastability-critical net.
// SW[7:6] selects the LCD view (healthy values in parentheses):
//   00 = {bad source frames, last source-frame pixel count}          (00 9600 = 38400)
//   01 = {bad scanlines, last bad line number, its pixel count[7:0]} (00 00 00)
//   10 = {bad panel frames, last panel-frame strobe count[15:0]}     (00 5800 = 153600 low bits)
//   11 = {FIFO frame drops, last command byte, RAMWR count[7:0]}
wire [23:0] lcd_dbg_sel =
    (SW[7:6] == 2'b00) ? {lcd_bad_src_frames, lcd_last_src_pix} :
    (SW[7:6] == 2'b01) ? {lcd_bad_lines, lcd_bad_line_num, lcd_bad_line_pix[7:0]} :
    (SW[7:6] == 2'b10) ? {lcd_bad_panel_frames, lcd_last_panel_pix[15:0]} :
                         {lcd_drops, lcd_last_cmd, lcd_frame_cnt[7:0]};
wire [31:0] lcd_dbg_word = {8'd0, lcd_dbg_sel};

// CPU debug HEX (shown when SW[8]=0), selectable with SW[7:6] for hw-test ROM bring-up:
//   00 = PC (r15)  : HEX5 = region nibble (8=ROM, 3=IWRAM, ...), HEX4:0 = offset[19:0]
//   01 = r0        : HEX5:0 = r0[23:0]   (result/status register many hw-test ROMs leave here)
//   10 = CPSR      : HEX5:4 = flags[31:24] (N Z C V Q .. T), HEX1:0 = ctrl[7:0] (I F T mode)
//   11 = addr_bus  : HEX5 = region nibble, HEX4:0 = offset[19:0]  (live bus address)
wire [23:0] cpu_dbg_pc   = {r[15][27:24],   r[15][19:0]};
wire [23:0] cpu_dbg_r0   =  r[0][23:0];
wire [23:0] cpu_dbg_cpsr = {CPSR[31:24], 8'h00, CPSR[7:0]};
wire [23:0] cpu_dbg_addr = {addr_bus[27:24], addr_bus[19:0]};
wire [23:0] cpu_dbg_sel  = (SW[7:6] == 2'b00) ? cpu_dbg_pc   :
                           (SW[7:6] == 2'b01) ? cpu_dbg_r0   :
                           (SW[7:6] == 2'b10) ? cpu_dbg_cpsr :
                                                cpu_dbg_addr;

// The panel reset (lcd_rst_n) is asserted low for only ~1.5 us during init, invisible on an LED.
// Make it observable/sticky: cleared while KEY[0] reset is held, set once the reset pulse fires.
// So LEDR[4] goes OFF when you press reset and turns back ON once init has pulsed the panel reset.
reg lcd_rst_seen = 1'b0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst)            lcd_rst_seen <= 1'b0;
    else if (!lcd_rst_n)  lcd_rst_seen <= 1'b1;

// DMA0: 0x040000BA | DMA1: 0x040000C6 | DMA2: 0x040000D2 | DMA3: 0x040000DE
// DMA0 channel
dma dma0 (
    .clock		(clock),
    .dmasad_o	(dma0sad_o),
    .dmadad_o	(dma0dad_o),
    .dmacnt_l_o (dma0cnt_l_o),
    .dmacnt_h_o (dma0cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_dma_start),
    .special    (1'b0),
    .halt       (dma_mem_hold),
    .priority_hold (dma_priority_hold[0]),
    .cpu_cycle_accepted (cpu_cycle_accepted),
    .src_addr	(addr_src_dma0),
    .dst_addr	(addr_dst_dma0),
    .data_o 	(data_dma0),
    .wr_en		(wr_en_dma0),
    .seq		(SEQ_dma0),
    .MAS		(MAS_dma0),
	.dma_pending	(dma_pending[0]),
    .dma_request  (dma_request[0]),
    .dma_disable  (dma_disable[0]),
    .dma_active	(dma_active[0]),
    .nIRQ		(nirq_dma0)
);

// DMA1 channel
dma dma1 (
    .clock		(clock),
    .dmasad_o	(dma1sad_o),
    .dmadad_o	(dma1dad_o),
    .dmacnt_l_o (dma1cnt_l_o),
    .dmacnt_h_o (dma1cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_dma_start),
    .special    (1'b0),
    .halt       (dma_mem_hold),
    .priority_hold (dma_priority_hold[1]),
    .cpu_cycle_accepted (cpu_cycle_accepted),
    .src_addr	(addr_src_dma1),
    .dst_addr	(addr_dst_dma1),
    .data_o 	(data_dma1),
    .wr_en		(wr_en_dma1),
    .seq		(SEQ_dma1),
    .MAS		(MAS_dma1),
	.dma_pending	(dma_pending[1]),
    .dma_request  (dma_request[1]),
    .dma_disable  (dma_disable[1]),
    .dma_active	(dma_active[1]),
    .nIRQ		(nirq_dma1)
);

// DMA2 channel
dma dma2 (
    .clock		(clock),
    .dmasad_o	(dma2sad_o),
    .dmadad_o	(dma2dad_o),
    .dmacnt_l_o (dma2cnt_l_o),
    .dmacnt_h_o (dma2cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_dma_start),
    .special    (1'b0),
    .halt       (dma_mem_hold),
    .priority_hold (dma_priority_hold[2]),
    .cpu_cycle_accepted (cpu_cycle_accepted),
    .src_addr	(addr_src_dma2),
    .dst_addr	(addr_dst_dma2),
    .data_o 	(data_dma2),
    .wr_en		(wr_en_dma2),
    .seq		(SEQ_dma2),
    .MAS		(MAS_dma2),
	.dma_pending	(dma_pending[2]),
    .dma_request  (dma_request[2]),
    .dma_disable  (dma_disable[2]),
    .dma_active	(dma_active[2]),
    .nIRQ		(nirq_dma2)
);

// DMA3 channel
dma dma3 (
    .clock		(clock),
    .dmasad_o	(dma3sad_o),
    .dmadad_o	(dma3dad_o),
    .dmacnt_l_o (dma3cnt_l_o),
    .dmacnt_h_o (dma3cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_dma_start),
    .special    (ppu_video_dma_start),
    .halt       (dma_mem_hold),
    .priority_hold (dma_priority_hold[3]),
    .cpu_cycle_accepted (cpu_cycle_accepted),
    .src_addr	(addr_src_dma3),
    .dst_addr	(addr_dst_dma3),
    .data_o 	(data_dma3),
    .wr_en		(wr_en_dma3),
    .seq		(SEQ_dma3),
    .MAS		(MAS_dma3),
	.dma_pending	(dma_pending[3]),
    .dma_request  (dma_request[3]),
    .dma_disable  (dma_disable[3]),
    .dma_active	(dma_active[3]),
    .nIRQ		(nirq_dma3)
);

// {r[7][3:0],addr_bus[7:0], r[0][11:0]}
// {r[0][7:0], addr_bus[27:24], addr_bus[15:0]}
seg_display seg_display(
    .in(SW[8] ? lcd_dbg_word : {8'd0, cpu_dbg_sel}),
	.clk (clock),

    .s0(HEX0),
    .s1(HEX1),
    .s2(HEX2),
    .s3(HEX3),
    .s4(HEX4),
    .s5(HEX5)
);

pll  pll(
	.refclk	(CLOCK_50),
//	.rst	(~nrst|| SW[0]),
	.rst	(SW[0]),

	.outclk_0(clock_cpu),       // 17 MHz
	.outclk_1(clock_sdram),     // 4*17 MHz
	.outclk_2(clock_sdram_d),   // 4*17 MHz -120°
	.outclk_3(clock_cpu_n),     // Inverted 17 MHz
	.locked  (pll_lock)
);

//integer count = 0;
//wire startup_rst = SW[0] | ~pll_lock;
//always @(posedge clock_cpu or posedge startup_rst) begin
//	if (startup_rst) count <= 0;
//	else if (count >= 32'd249_999) count <= 0;
//	else count <= count+1;
//end
//
//always @(posedge clock_cpu or posedge startup_rst) begin
//    if (startup_rst)                 test_clk <= 1'b0;
//    else if (count == 32'd249_999)   test_clk <= ~test_clk;
//end

//always @(posedge clock_cpu or posedge startup_rst) begin
//	if (startup_rst) count <= 0;
//	else if (count >= 32'd2) count <= 0;
//	else count <= count+1;
//end
//
//always @(posedge clock_cpu or posedge startup_rst) begin
//    if (startup_rst)                 test_clk <= 1'b0;
//    else if (count == 32'd2)   test_clk <= ~test_clk;
//end

//clkctrl_cpu clkctrl_cpu (
//	.inclk  (test_clk),  //  altclkctrl_input.inclk
//	.outclk (clock)  // altclkctrl_output.outclk
//);

assign nrst = KEY[0];
assign tap_en = SW[9];
assign LEDR[0] = clock;
assign LEDR[1] = !(CPSR[7] || CPSR[6]);
// LCD bring-up status LEDs (LEDR[2:0] keep their CPU-debug meaning):
assign LEDR[3] = lcd_init_done;      // steady ON = init sequence completed
assign LEDR[4] = lcd_rst_seen;       // sticky: OFF while KEY[0] held, ON once the ~1.5us panel-reset pulse fired
assign LEDR[5] = lcd_frame_dropped;  // ON = FIFO overflow / frame drop
assign LEDR[6] = lcd_ppu_ready;      // writer accepting pixels
assign LEDR[7] = lcd_wr_act[23];     // ~1 Hz blink while 8080 writes flow (streaming active)
assign LEDR[8] = lcd_frame_cnt[5];   // frame-rate blink (toggles every ~32 frames)
assign LEDR[9] = lcd_dbg_div[25];    // ~1 Hz heartbeat = 68 MHz LCD clock is alive

endmodule
