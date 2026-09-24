module lcd_8080_writer #(
    parameter [15:0] HRES = 16'd480,   // LCD landscape width  (source width  * 2)
    parameter [15:0] VRES = 16'd320    // LCD landscape height (source height * 2)
) (
    input  wire clk,                   // LCD-side adapter clock (same net as lcd_writer clk_R)
    input  wire nrst,
    input  wire start,                 // begin/continue streaming (tie to initializer init_done)

    // pixel source (lcd_writer read side)
    input  wire [15:0] pixel_o,
    input  wire        pixel_valid_o,
    output wire        rd_en,          // one-cycle pulse: take the presented pixel

    // ILI9488 8080 parallel bus
    output wire        CSX,            // active low, held low across a frame
    output wire        DCX,            // 0 = command, 1 = parameter/pixel
    output wire        WRX,            // rising edge latches DB
    output wire [15:0] DB,             // DB[7:0]=byte for cmd/param (DB[15:8]=0); full pixel in burst
    output wire        frame_start     // one-cycle pulse when a new frame's window write begins
);
    // Per frame this re-issues the window (CASET/PASET) and RAMWR, then streams HRES*VRES pixels
    // pulled from lcd_writer. Every command byte, parameter byte and pixel uses one SETUP/LOW/HOLD
    // WRX strobe. Commands/params are 8-bit on DB[7:0]; pixels are full 16-bit RGB565.

    localparam [15:0] XEND = HRES - 16'd1;   // inclusive column end (479 -> 0x01DF)
    localparam [15:0] YEND = VRES - 16'd1;   // inclusive page   end (319 -> 0x013F)
    localparam [31:0] NPIX = HRES * VRES;

    // setup item list: 0x2A + 4 params, 0x2B + 4 params, 0x2C   (11 items, index 0..10)
    localparam [3:0] LAST_SU = 4'd10;
    reg [3:0] si = 4'd0;        // setup-item index

    // Setup-item byte / DCX as functions (evaluated where used) rather than an always @(*)
    // reg, so item 0 (si never transitions into 0 from IDLE) is never left X.
    function [7:0] su_byte(input [3:0] idx);
        case (idx)
            4'd0 : su_byte = 8'h2A;      // CASET
            4'd1 : su_byte = 8'h00;      // x0 hi
            4'd2 : su_byte = 8'h00;      // x0 lo
            4'd3 : su_byte = XEND[15:8]; // x1 hi
            4'd4 : su_byte = XEND[7:0];  // x1 lo
            4'd5 : su_byte = 8'h2B;      // PASET
            4'd6 : su_byte = 8'h00;      // y0 hi
            4'd7 : su_byte = 8'h00;      // y0 lo
            4'd8 : su_byte = YEND[15:8]; // y1 hi
            4'd9 : su_byte = YEND[7:0];  // y1 lo
            4'd10: su_byte = 8'h2C;      // RAMWR
            default: su_byte = 8'h00;
        endcase
    endfunction
    function su_dcx(input [3:0] idx);    // 0 = command (0x2A/0x2B/0x2C), 1 = parameter
        case (idx)
            4'd0, 4'd5, 4'd10: su_dcx = 1'b0;
            default:           su_dcx = 1'b1;
        endcase
    endfunction

    localparam [3:0] IDLE     = 4'd0,
                     SU_SETUP = 4'd1,
                     SU_LOW   = 4'd2,
                     SU_HOLD  = 4'd3,
                     PX_WAIT  = 4'd4,
                     PX_SETUP = 4'd5,
                     PX_LOW   = 4'd6,
                     PX_HOLD  = 4'd7,
                     PX_GAP   = 4'd8;   // let the reader's rd_en advance settle before recapture

    reg [3:0]  state = IDLE;
    reg [31:0] pix_count = 32'd0;

    reg        CSX_r = 1'b1;
    reg        DCX_r = 1'b1;
    reg        WRX_r = 1'b1;
    reg [15:0] DB_r  = 16'd0;
    reg        rd_en_r = 1'b0;
    reg        frame_start_r = 1'b0;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state         <= IDLE;
            si            <= 4'd0;
            pix_count     <= 32'd0;
            CSX_r         <= 1'b1;
            DCX_r         <= 1'b1;
            WRX_r         <= 1'b1;
            DB_r          <= 16'd0;
            rd_en_r       <= 1'b0;
            frame_start_r <= 1'b0;
        end else begin
            rd_en_r       <= 1'b0;   // defaults, overridden below
            frame_start_r <= 1'b0;
            case (state)
                IDLE: begin
                    CSX_r <= 1'b1; WRX_r <= 1'b1;
                    if (start) begin
                        si            <= 4'd0;
                        frame_start_r <= 1'b1;
                        state         <= SU_SETUP;
                    end
                end
                // ---- command/parameter byte, 3-phase strobe ----
                SU_SETUP: begin
                    CSX_r <= 1'b0;
                    WRX_r <= 1'b1;
                    DCX_r <= su_dcx(si);
                    DB_r  <= {8'b0, su_byte(si)};
                    state <= SU_LOW;
                end
                SU_LOW: begin
                    WRX_r <= 1'b0;
                    state <= SU_HOLD;
                end
                SU_HOLD: begin
                    WRX_r <= 1'b1;                 // rising edge latches the byte
                    if (si == LAST_SU) begin
                        pix_count <= NPIX;
                        state     <= PX_WAIT;
                    end else begin
                        si    <= si + 4'd1;
                        state <= SU_SETUP;
                    end
                end
                // ---- one pixel, 3-phase strobe ----
                PX_WAIT: begin
                    CSX_r <= 1'b0;
                    WRX_r <= 1'b1;
                    if (pixel_valid_o) begin       // stall here if no ready buffer (safe underrun)
                        DCX_r <= 1'b1;
                        DB_r  <= pixel_o;
                        state <= PX_SETUP;
                    end
                end
                PX_SETUP: begin
                    WRX_r <= 1'b1;
                    state <= PX_LOW;
                end
                PX_LOW: begin
                    WRX_r <= 1'b0;
                    state <= PX_HOLD;
                end
                PX_HOLD: begin
                    WRX_r   <= 1'b1;               // latch pixel (rising edge)
                    rd_en_r <= 1'b1;               // advance lcd_writer to the next scaled pixel
                    state   <= PX_GAP;
                end
                PX_GAP: begin
                    // rd_en pulsed last cycle; the reader advances on this edge, so pixel_o only
                    // reflects the next scaled pixel from here on. Decide the next step now.
                    if (pix_count == 32'd1) begin
                        pix_count <= 32'd0;
                        if (start) begin           // next frame: re-issue window + RAMWR
                            si            <= 4'd0;
                            frame_start_r <= 1'b1;
                            state         <= SU_SETUP;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        pix_count <= pix_count - 32'd1;
                        state     <= PX_WAIT;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign CSX         = CSX_r;
    assign DCX         = DCX_r;
    assign WRX         = WRX_r;
    assign DB          = DB_r;
    assign rd_en       = rd_en_r;
    assign frame_start = frame_start_r;

endmodule
