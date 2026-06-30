// =============================================================================
//  gba_rev0.v
//  DE1-SoC synthesis top for the ARM7TDMI/GBA bring-up system.
//
//  Active datapath:
//      ARM7TDMI + DMA0..3 -> bus_arbiter -> bus_controller
//      -> BIOS/IWRAM/IO/Palette/VRAM/OAM/Cart RAM and SDRAM-backed EWRAM/PAK ROM.
//
//  The CPU runs from a PLL-derived debug clock (`test_clk`), while local memory
//  and the SDRAM host wrapper use the inverse clock (`clock_n`) for the current
//  synchronous-read timing convention. `mem_ready` releases CPU nWAIT and holds
//  DMA state machines through `.halt(!mem_ready)` while SDRAM or local regions
//  are not ready.
//
//  SDRAM access size and sign-extension controls are sourced from the active
//  master bus (`MAS`, `sign_extend`). VBlank/HBlank DMA timing is manual switch
//  stimulus (`SW[1]`/`SW[2]`) until a PPU timing source is integrated.
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
wire clock_sdram;
wire clock_sdram_d;
wire pll_lock;
reg test_clk = 0;

wire clock = clock_cpu;
wire clock_n = !clock_cpu;
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

// DMA completion pulses are latched by IF. The CPU sees an active-low IRQ only
// when the corresponding IE bit and IME are enabled; KEY[1] remains a direct,
// active-low external IRQ source.
wire [15:0] ie_reg;
wire [15:0] if_reg;
wire [15:0] ime_reg;
wire [13:0] irq_request = {2'b00, ~nirq_dma3, ~nirq_dma2,
                            ~nirq_dma1, ~nirq_dma0, 8'b0};
wire        irq_pending = ime_reg[0] && |(ie_reg & if_reg);
wire        nIRQ = KEY[1] && !irq_pending;

wire vblank_i = SW[1];
wire hblank_i = SW[2];

reg vblank_s0, vblank_s1, vblank_s2;
reg hblank_s0, hblank_s1, hblank_s2;

wire vblank = !vblank_s2 && vblank_s1;
wire hblank = !hblank_s2 && hblank_s1;

always @(posedge clock) begin
    vblank_s0 <= vblank_i;
    hblank_s0 <= hblank_i;
    vblank_s1 <= vblank_s0;
    hblank_s1 <= hblank_s0;
    vblank_s2 <= vblank_s1;
    hblank_s2 <= hblank_s1;
end

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
    .misalign_fault	()
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
    .misalign_fault	()
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
    .misalign_fault	()
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
    //  No PPU/keypad/serial hardware wired yet — tie to idle defaults.
    .vcount_i	(16'd0),       // REG_VCOUNT (only low 8 bits meaningful)
    .vblank_status_i (1'b0),   // DISPSTAT bit 0 (W)
    .hblank_status_i (1'b0),   // DISPSTAT bit 1 (G)
    .vcount_match_i  (1'b0),   // DISPSTAT bit 2 (Z)
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
    .dispcnt_o	(),
    .dispstat_o	(),
    //---------------- Backgrounds ----------------
    .bg0cnt_o (), .bg1cnt_o (), .bg2cnt_o (), .bg3cnt_o (),
    .bg0hofs_o (), .bg0vofs_o (),
    .bg1hofs_o (), .bg1vofs_o (),
    .bg2hofs_o (), .bg2vofs_o (),
    .bg3hofs_o (), .bg3vofs_o (),
    .bg2pa_o (), .bg2pb_o (), .bg2pc_o (), .bg2pd_o (),
    .bg3pa_o (), .bg3pb_o (), .bg3pc_o (), .bg3pd_o (),
    .bg2x_o (), .bg2y_o (),
    .bg3x_o (), .bg3y_o (),
    //---------------- Window ----------------
    .win0h_o (), .win1h_o (), .win0v_o (), .win1v_o (),
    .winin_o (), .winout_o (),
    //---------------- Effects ----------------
    .mosaic_o	(),
    .bldmod_o (), .colev_o (), .coley_o (),
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

// DMA0: 0x040000BA | DMA1: 0x040000C6 | DMA2: 0x040000D2 | DMA3: 0x040000DE
// DMA0 channel
dma #(.DMA_Control_Register_Addr (32'h0400_00BA)) dma0 (
    .clock		(clock),
    .dmasad_o	(dma0sad_o),
    .dmadad_o	(dma0dad_o),
    .dmacnt_l_o (dma0cnt_l_o),
    .dmacnt_h_o (dma0cnt_h_o),
    .data_i	    (data_bus),
    .vblank		(vblank),            // no PPU timing wired yet
    .hblank		(hblank),
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
    .vblank		(vblank),            // no PPU timing wired yet
    .hblank		(hblank),
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
    .vblank		(vblank),            // no PPU timing wired yet
    .hblank		(hblank),
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
    .vblank		(vblank),            // no PPU timing wired yet
    .hblank		(hblank),
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

assign nrst = KEY[0] & pll_lock;
assign tap_en = SW[9];
assign LEDR[0] = clock;
assign LEDR[1] = !(CPSR[7] || CPSR[6]);

endmodule
