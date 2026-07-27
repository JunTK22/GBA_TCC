// =============================================================================
//  gba_rev0.v
//  DE1-SoC synthesis top for the ARM7TDMI/GBA bring-up system.
//
//  Active system paths:
//      ARM7TDMI + DMA0..3 -> bus_arbiter -> bus_controller -> memory regions
//      IO register controls -> PPU -> VRAM/OAM/palette fetch ports
//
//  The CPU, DMA engines, and PPU use the 17 MHz PLL `clock_cpu` output. Local
//  memories, the IO register file, and the SDRAM host wrapper use the dedicated
//  inverse output, `clock_cpu_n`, for the synchronous-read timing convention.
//  `mem_ready` releases CPU nWAIT and holds DMA through `.halt(!mem_ready)`.
//
//  The PPU drives DISPSTAT/VCOUNT state, video IRQ requests, and VBlank/HBlank
//  DMA start events. Its rendered pixel and blanking outputs are not yet routed
//  to the board VGA pins.
//
//  SDRAM access size and sign-extension controls come from the active master
//  bus (`MAS`, `sign_extend`).
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

//parameter INIT_FILE  = "code/assembly_code/instrucoes.mif";
//parameter INIT_FILE  = "code/assembly_code/arm7tdmi_thumb_test.mif";
//parameter INIT_FILE  = "code/assembly_code/interrupt_test.mif";
//parameter INIT_FILE  = "code/assembly_code/bus_test.mif";
//parameter INIT_FILE  = "code/assembly_code/presentation_fibonacci.mif";
//parameter INIT_FILE  = "code/assembly_code/memory_system_test.mif";
//parameter INIT_FILE  = "code/assembly_code/dma_modes_test.mif";
//parameter INIT_FILE  = "code/assembly_code/dma_irq_memory_test.mif";
parameter INIT_FILE  = "code/assembly_code/thumb_memory_test.mif";

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

// PPU register values from io_registers. These are written on clock_n and are
// stable for half a CPU cycle before the PPU samples them on clock.
wire [15:0] ppu_dispcnt;
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

wire ppu_vblank_status = (ppu_scanline >= 8'd160)
                       && (ppu_scanline <= 8'd226);
wire ppu_hblank_status = ppu_tick >= 11'd1006;
wire ppu_vcount_match = ppu_scanline == ppu_dispstat[15:8];
wire ppu_vblank_start = (ppu_tick == 11'd0)
                      && (ppu_scanline == 8'd160);
wire ppu_hblank_start = (ppu_tick == 11'd1006)
                      && (ppu_scanline < 8'd160);

reg ppu_vcount_match_q;
reg ppu_vcount_irq;
always @(posedge clock) begin
    if (!nrst) begin
        ppu_vcount_match_q <= 1'b0;
        ppu_vcount_irq <= 1'b0;
    end else begin
        ppu_vcount_match_q <= ppu_vcount_match;
        ppu_vcount_irq <= ppu_vcount_match && !ppu_vcount_match_q;
    end
end

// PPU and DMA event pulses are latched by IF. The CPU sees an active-low IRQ
// only when the corresponding IE bit and IME are enabled; KEY[1] remains a
// direct, active-low external IRQ source.
wire [15:0] ie_reg;
wire [15:0] if_reg;
wire [15:0] ime_reg;
wire [13:0] irq_request = {2'b00, ~nirq_dma3, ~nirq_dma2,
                            ~nirq_dma1, ~nirq_dma0, 5'b00000,
                            ppu_vcount_irq && ppu_dispstat[5],
                            ppu_hblank_start && ppu_dispstat[4],
                            ppu_vblank_start && ppu_dispstat[3]};
wire        irq_pending = ime_reg[0] && |(ie_reg & if_reg);
wire        nIRQ = KEY[1] && !irq_pending;

///////////////////////////////////////

wire busy;
wire [5:0] ready_mem;
reg nWAIT = 0;
wire mem_ready = !busy && &ready_mem;
always @(posedge clock_n) begin
    nWAIT <= (!(|dma_active) && mem_ready);
end
//=======================================================
//  Structural coding
//=======================================================

arm7tdmi_top arm7tdmi_top(
	.MCLK		(clock),
	.reset_n	(nrst),

	.nWAIT	(nWAIT),

	.DIN	(data_bus),
	.A		(addr_cpu),
	.DOUT	(data_cpu),
	.nRW	(nRW_CPU),
	.MAS	(MAS_cpu),
	.nMREQ	(),
	.SEQ	(),
	.nOPC	(),
	.nTRANS	(),

	.nENOUT	(),

	.sign_f	(sign_extend),

	.nIRQ	(nIRQ),
	.nFIQ	(KEY[2]),
	.ABORT	(KEY[3]),

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

    .nRW_CPU       (nRW_CPU),
    .wr_en_dma     (wr_en_dma0 || wr_en_dma1 || wr_en_dma2 || wr_en_dma3),
    .dma_active    (dma_active),

    .addr_o        (addr_bus),
    .data_o        (data_main),
    .MAS           (MAS),
    .nRW           (nRW)
);

sdram_controller_top sdram_controller(
    .clock      (clock_n),
    .clock_sdram(clock_sdram),
    .nrst       (nrst),
    .MAS        (MAS),
    .sign_extend (sign_extend),

    .rd_en      (rden_pakrom  || rden_ewram),
    .wr_en      (we_pakrom || we_ewram),
	
    .addr       (addr_bus),
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
assign data_pakrom = data_sdram;
assign data_ewram = data_sdram;

bios #(
    .INIT_FILE (INIT_FILE)
) bios (
    .clk	(clock_n),
    .addr	(addr_bus),        // word address (4096 32-bit words = 16 KB)
    .rdata	(data_bios),
    .rden	(rden_bios),
    .size	(MAS),             // 00=byte 01=half 10=word
    .sign_extend (sign_extend)
);

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
    .addr	(addr_bus),           // 32 KB byte address
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
    .addr	(addr_bus),           // 1 KB byte address
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
    .addr	(addr_bus),           // 128 KB byte address
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
    .obj_addr   (ppu_obj_vram_address),
    .obj_rdata  (ppu_obj_vram_read_data),
    .obj_rden   (ppu_obj_vram_read),
    .bg_mode    (ppu_dispcnt[2:0]),
    .force_blank (ppu_dispcnt[7])
);

oam oam (
    .clk	(clock_n),
    .addr	(addr_bus),            // 1 KB byte address
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

cart_ram cart_ram (
    .clk	(clock_n),
    .addr	(addr_bus),     // byte address
    .wdata	(data_bus),
    .rdata	(data_cartram),
    .we		(we_cartram),
    .rden	(rden_cartram),
	.size	(MAS),
    .sign_extend (sign_extend),
    .ready	(ready_mem[4]),
    .misalign_fault	()
);

io_registers io_registers (
    .clk	(clock_n),
    .reset_n	(nrst),
    //---------------- CPU bus ----------------
    .addr	(addr_bus),       // byte address within 1 KB IO space
    .wdata	(data_bus),
    .rdata	(data_ioram),
    .we		(we_ioram),
    .rden   (rden_ioram),
    .size	(MAS),             // 00=byte 01=half 10=word
    .sign_extend (sign_extend),
    .ready	(ready_mem[5]),
    .misalign_fault	(),
    //---------------- Hardware-driven read fields ----------------
    .vcount_i	({8'd0, ppu_scanline}),
    .vblank_status_i (ppu_vblank_status),
    .hblank_status_i (ppu_hblank_status),
    .vcount_match_i  (ppu_vcount_match),
    .keypad_i	(16'h03FF),    // REG_KEY (active low) — all keys released
    .irq_request_i (irq_request),
    .sound_status_i (4'd0),    // SOUNDCNT_X bits 0-3
    .serial_data0_i (16'd0),   // SCD0 (received)
    .serial_data1_i (16'd0),   // SCD1
    .serial_data2_i (16'd0),   // SCD2
    .serial_data3_i (16'd0),   // SCD3
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
    .wscnt_o	(),
    .ime_o		(ime_reg)
);

ppu ppu (
    .clock                  (clock),
    .reset                  (!nrst),
    .enable                 (1'b1),
    .display_mode           (ppu_dispcnt[2:0]),
    .display_frame          (ppu_dispcnt[4]),
    .display_force_blank    (ppu_dispcnt[7]),
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
    .output_valid           (),
    .output_pixel           (),
    .output_hblank          (),
    .output_vblank          (),
    .tick                   (ppu_tick),
    .scanline               (ppu_scanline)
);

// DMA0: 0x040000BA | DMA1: 0x040000C6 | DMA2: 0x040000D2 | DMA3: 0x040000DE
// DMA0 channel
dma #(.DMA_Control_Register_Addr (32'h0400_00BA)) dma0 (
    .clock		(clock),
    .dmasad_o	(dma0sad_o),
    .dmadad_o	(dma0dad_o),
    .dmacnt_l_o (dma0cnt_l_o),
    .dmacnt_h_o (dma0cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_start),
    .halt       (!mem_ready),
    .src_addr	(addr_src_dma0),
    .dst_addr	(addr_dst_dma0),
    .data_o 	(data_dma0),
    .wr_en		(wr_en_dma0),
    .MAS		(MAS_dma0),
    .dma_active	(dma_active[0]),
    .nIRQ		(nirq_dma0)
);

// DMA1 channel
dma #(.DMA_Control_Register_Addr (32'h0400_00C6)) dma1 (
    .clock		(clock),
    .dmasad_o	(dma1sad_o),
    .dmadad_o	(dma1dad_o),
    .dmacnt_l_o (dma1cnt_l_o),
    .dmacnt_h_o (dma1cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_start),
    .halt       (!mem_ready),
    .src_addr	(addr_src_dma1),
    .dst_addr	(addr_dst_dma1),
    .data_o 	(data_dma1),
    .wr_en		(wr_en_dma1),
    .MAS		(MAS_dma1),
    .dma_active	(dma_active[1]),
    .nIRQ		(nirq_dma1)
);

// DMA2 channel
dma #(.DMA_Control_Register_Addr (32'h0400_00D2)) dma2 (
    .clock		(clock),
    .dmasad_o	(dma2sad_o),
    .dmadad_o	(dma2dad_o),
    .dmacnt_l_o (dma2cnt_l_o),
    .dmacnt_h_o (dma2cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_start),
    .halt       (!mem_ready),
    .src_addr	(addr_src_dma2),
    .dst_addr	(addr_dst_dma2),
    .data_o 	(data_dma2),
    .wr_en		(wr_en_dma2),
    .MAS		(MAS_dma2),
    .dma_active	(dma_active[2]),
    .nIRQ		(nirq_dma2)
);

// DMA3 channel
dma #(.DMA_Control_Register_Addr (32'h0400_00DE)) dma3 (
    .clock		(clock),
    .dmasad_o	(dma3sad_o),
    .dmadad_o	(dma3dad_o),
    .dmacnt_l_o (dma3cnt_l_o),
    .dmacnt_h_o (dma3cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(ppu_vblank_start),
    .hblank		(ppu_hblank_start),
    .halt       (!mem_ready),
    .src_addr	(addr_src_dma3),
    .dst_addr	(addr_dst_dma3),
    .data_o 	(data_dma3),
    .wr_en		(wr_en_dma3),
    .MAS		(MAS_dma3),
    .dma_active	(dma_active[3]),
    .nIRQ		(nirq_dma3)
);

// {r[7][3:0],addr_bus[7:0], r[0][11:0]}
// {r[0][7:0], addr_bus[27:24], addr_bus[15:0]}
seg_display seg_display(
    .in({r[0][7:0], addr_bus[27:24], addr_bus[11:0]}),
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

//genvar i;
//generate
//	for (i = 0;i < 16 ; i = i+1) begin: reg_taps
//		signal_tap reg_bank_tap (
//		.acq_data_in    (r[i]),    //     tap.acq_data_in
//		.acq_trigger_in (tap_en), //        .acq_trigger_in
//		.acq_clk        (clock)         // acq_clk.clk
//	);
//	end
//endgenerate
//
//signal_tap addr_tap (
//		.acq_data_in    (addr_bus),    //     tap.acq_data_in
//		.acq_trigger_in (tap_en), //        .acq_trigger_in
//		.acq_clk        (clock)         // acq_clk.clk
//);
//
//signal_tap din_tap (
//		.acq_data_in    (data_bus),    //     tap.acq_data_in
//		.acq_trigger_in (tap_en), //        .acq_trigger_in
//		.acq_clk        (clock)         // acq_clk.clk
//);

assign nrst = KEY[0];
assign tap_en = SW[9];
assign LEDR[0] = clock;
assign LEDR[1] = !(CPSR[7] || CPSR[6]);

endmodule
