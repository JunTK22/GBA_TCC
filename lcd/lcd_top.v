module lcd_top #(
    parameter [15:0]  HRES = 16'd480,  // LCD landscape width  (GBA 240 * 2)
    parameter [15:0]  VRES = 16'd320,  // LCD landscape height (GBA 160 * 2)
    parameter integer NBUF = 32,       // row-FIFO depth (2^k >= 4); sim measured peak backlog 24
    // ILI9488 init delays (clk_lcd cycles); defaults sized for 68 MHz. TBs override for fast sim.
    parameter [31:0]  T_RST_LOW  = 32'd680000,   // 10 ms  @ 68 MHz
    parameter [31:0]  T_RST_WAIT = 32'd8160000,  // 120 ms @ 68 MHz
    parameter [31:0]  T_SLEEP    = 32'd8160000,  // 120 ms @ 68 MHz
    parameter [31:0]  T_DISPON   = 32'd1360000   // 20 ms  @ 68 MHz
) (
    input  wire clk_ppu,    // PPU pixel clock (17 MHz)   -> lcd_writer producer side
    input  wire clk_lcd,    // LCD adapter clock (~4x)    -> initializer, glue, writer consumer side
    input  wire nrst,       // active-low system reset
    input  wire init_en,    // enable the init sequence (normally tied high)

    // PPU capture input, on clk_ppu. GBA RGB555: red[4:0] green[9:5] blue[14:10].
    input  wire [14:0] ppu_pixel,
    input  wire        ppu_valid,
    input  wire        ppu_vblank,  // PPU output_vblank (high during VBlank); frames the capture
    output wire        ppu_ready,   // = writer.ppu_en (accepting a pixel right now)
    output wire        frame_dropped,// high while a whole source frame is being skipped (overflow)

    // ILI9488 8080 parallel bus (to the panel / GPIO breakout)
    output wire        lcd_csx,     // active low
    output wire        lcd_dcx,     // 0 = command, 1 = parameter/pixel
    output wire        lcd_wrx,     // rising edge latches lcd_db
    output wire        lcd_rst_n,   // panel reset, active low
    output wire [15:0] lcd_db,

    output wire        init_done    // high once the init sequence has completed
);
    // RGB555 -> RGB565 with green-endpoint preservation (FPGA_LCD_INTEGRATION.md):
    //   DB = {red5, green5, green_msb, blue5}. This is the ONLY colour conversion in the path;
    //   both LCD modules carry a ready 16-bit RGB565 word.
    wire [15:0] pixel_rgb565 =
        {ppu_pixel[4:0], ppu_pixel[9:5], ppu_pixel[9], ppu_pixel[14:10]};

    // source-frame boundary = VBlank falling edge (start of active line 0), one clk_ppu pulse
    // ahead of the frame's first pixel. vbl_d resets to 1 so the first active frame starts capture.
    reg vbl_d = 1'b1;
    always @(posedge clk_ppu or negedge nrst)
        if (!nrst) vbl_d <= 1'b1; else vbl_d <= ppu_vblank;
    wire frame_start = vbl_d & ~ppu_vblank;

    // Do not capture PPU frames until the panel is initialized: gate frame_start on init_done so
    // the writer's admission latch first arms at the FIRST frame boundary AFTER init. This keeps
    // the CPU/PPU free-running (the tap stays passive) while making the first displayed frame a
    // clean, frame-aligned current frame instead of stale data captured during init. init_done is
    // generated on clk_lcd, so synchronize it into clk_ppu (2-FF) before ANDing the pulse.
    reg init_done_s1 = 1'b0, init_done_ppu = 1'b0;
    always @(posedge clk_ppu or negedge nrst)
        if (!nrst) {init_done_ppu, init_done_s1} <= 2'b00;
        else       {init_done_ppu, init_done_s1} <= {init_done_s1, init_done};
    wire frame_start_cap = frame_start & init_done_ppu;

    // ---- initialization sequencer (drives its own command/parameter bus) ----
    wire        init_csx, init_dcx, init_wrx, init_nrst;
    wire [15:0] init_cmd, init_param;

    lcd_initializer #(
        .T_RST_LOW (T_RST_LOW), .T_RST_WAIT(T_RST_WAIT),
        .T_SLEEP   (T_SLEEP),   .T_DISPON  (T_DISPON)
    ) u_init (
        .clk(clk_lcd), .nrst(nrst), .init_en(init_en),
        .CSX(init_csx), .DCX(init_dcx), .WRX(init_wrx), .nRST(init_nrst),
        .cmd(init_cmd), .param(init_param), .init_done(init_done)
    );

    // ---- NBUF-deep row-FIFO 2x2 upscaler (PPU -> scaled pixel stream) ----
    // Deep FIFO (not 2 line buffers) so the per-row rate mismatch is absorbed and drained in VBlank;
    // NBUF=32 covers the measured peak backlog of 24 rows with margin. wr_level is the occupancy a
    // future frame-drop policy would gate capture on (left open here).
    wire        wr_pvo, glue_rd_en;
    wire [15:0] wr_pixel;

    lcd_writer_fifo #(.NBUF(NBUF), .COLS(HRES >> 1)) u_writer (
        .clk_W(clk_ppu), .clk_R(clk_lcd), .nrst(nrst), .nEN(1'b0),
        .pixel_i(pixel_rgb565), .pixel_valid(ppu_valid), .ppu_en(ppu_ready),
        .rd_en(glue_rd_en), .pixel_valid_o(wr_pvo), .pixel_o(wr_pixel),
        .wr_level(/* unused */),
        .frame_start(frame_start_cap), .frame_dropped(frame_dropped)
    );

    // ---- per-frame window/RAMWR + pixel-burst writer (streams after init) ----
    wire        glue_csx, glue_dcx, glue_wrx;
    wire [15:0] glue_db;

    lcd_8080_writer #(.HRES(HRES), .VRES(VRES)) u_glue (
        .clk(clk_lcd), .nrst(nrst), .start(init_done),
        .pixel_o(wr_pixel), .pixel_valid_o(wr_pvo), .rd_en(glue_rd_en),
        .CSX(glue_csx), .DCX(glue_dcx), .WRX(glue_wrx), .DB(glue_db),
        .frame_start(/* unused */)
    );

    // ---- 8080 bus mux ----
    // During init the initializer owns the bus; its 8-bit command/parameter selects the byte
    // to place on DB (DB[15:8]=0). After init_done the glue owns the bus. Both sources idle with
    // CSX/WRX high, so the switch at init_done introduces no spurious strobe.
    wire [15:0] init_db = init_dcx ? init_param : init_cmd;

    assign lcd_csx   = init_done ? glue_csx : init_csx;
    assign lcd_dcx   = init_done ? glue_dcx : init_dcx;
    assign lcd_wrx   = init_done ? glue_wrx : init_wrx;
    assign lcd_db    = init_done ? glue_db  : init_db;
    assign lcd_rst_n = init_nrst;   // panel reset only ever driven by the initializer

endmodule
