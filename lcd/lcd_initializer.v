module lcd_initializer #(
    // ILI9488 power-up delays, in `clk` cycles. Defaults are sized for a 68 MHz clk
    // (reset-low 10 ms, reset-release 120 ms, sleep-out 120 ms, display-on 20 ms).
    // Testbenches override these with tiny values for fast simulation.
    parameter [31:0] T_RST_LOW  = 32'd680000,   // 10 ms  @ 68 MHz
    parameter [31:0] T_RST_WAIT = 32'd8160000,  // 120 ms @ 68 MHz
    parameter [31:0] T_SLEEP    = 32'd8160000,  // 120 ms @ 68 MHz
    parameter [31:0] T_DISPON   = 32'd1360000   // 20 ms  @ 68 MHz
) (
    input wire clk,
    input wire nrst,
    input wire init_en,

    output wire CSX,
    output wire DCX,
    output wire WRX,
    output wire nRST,
    output wire [15:0] cmd,
    output wire [15:0] param,
    output wire init_done
);

    reg CSX_r = 1;
    reg DCX_r = 1;
    reg WRX_r = 1;
    reg nRST_r = 0;
    reg [7:0] cmd_r   = 8'b0;
    reg [7:0] param_r = 8'b0;

    reg [7:0] params_E0 [0:14];
    reg [7:0] params_E1 [0:14];
    reg [7:0] params_C0 [0:1];
    reg [7:0] params_C1;
    reg [7:0] params_C5 [0:2];
    reg [7:0] params_B0;
    reg [7:0] params_B1;
    reg [7:0] params_B4;
    reg [7:0] params_B6 [0:2];
    reg [7:0] params_B7;
    reg [7:0] params_F7 [0:3];

    localparam START        = 4'd0;
    localparam RESET_ASSERT  = 4'd1;
    localparam RESET_RELEASE = 4'd2;
    localparam LCD_SEL      = 4'd3;
    localparam CMD_SELECT   = 4'd4;
    localparam PARAM_WRITE  = 4'd5;
    localparam SETUP        = 4'd6;
    localparam LOW          = 4'd7;
    localparam HOLD         = 4'd8;
    localparam LCD_NSEL     = 4'd9;
    localparam WAIT         = 4'd10;
    localparam END_STATE    = 4'd11;

    reg [3:0] STATE = START;
    reg [3:0] NEXT_STATE = START;

    reg [31:0] wait_count = 32'd0; // wait duration in `clk` cycles; the loaded ILI9488 delays below
                                   // (10/120/120/20 ms) are sized for a 68 MHz clk -- rescale if clk changes
    reg [4:0] cmd_i   = 5'd0;
    reg [3:0] param_i = 4'd0;
    reg [3:0] param_count = 4'd0;

    wire param_end = (param_i == param_count);
    wire wait_end  = (wait_count <= 1);
    wire init_end  = (cmd_i == 5'd21);
    
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            STATE <= START;
        end else if(init_en) begin
            STATE <= NEXT_STATE;
        end
    end

    always @(*) begin
        case (STATE)
            START:       NEXT_STATE = RESET_ASSERT;
            RESET_ASSERT:  NEXT_STATE = WAIT;
            RESET_RELEASE: NEXT_STATE = WAIT;
            LCD_SEL:     NEXT_STATE = CMD_SELECT;
            CMD_SELECT:  NEXT_STATE = SETUP;
            PARAM_WRITE: NEXT_STATE = SETUP;
            SETUP:       NEXT_STATE = LOW;
            LOW:         NEXT_STATE = HOLD;
            HOLD:        NEXT_STATE = param_end ? LCD_NSEL : PARAM_WRITE;
            LCD_NSEL:    NEXT_STATE = !wait_end ? WAIT : LCD_SEL;
            WAIT:        NEXT_STATE = wait_end ? (init_end ? END_STATE : (nRST_r ? LCD_SEL : RESET_RELEASE)) : WAIT;
            END_STATE:   NEXT_STATE = END_STATE;
            default:     NEXT_STATE = STATE;
        endcase
    end

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            wait_count   <= 32'd0;
            cmd_i        <= 5'd0;
            param_i      <= 4'd0;
            param_count  <= 4'd0;

            CSX_r   <= 1;
            DCX_r   <= 1;
            WRX_r   <= 1;
            nRST_r  <= 1;
            cmd_r   <= 8'b0;
            param_r <= 8'b0;
        end else if(init_en) begin
            case (STATE)
                START: begin
                    wait_count   <= 32'd0;
                    cmd_i        <= 5'd0;
                    param_i      <= 4'd0;
                    param_count  <= 4'd0;

                    CSX_r   <= 1;
                    DCX_r   <= 1;
                    WRX_r   <= 1;
                    nRST_r  <= 1;
                    cmd_r   <= 8'b0;
                    param_r <= 8'b0;

                    params_E0[0]  <= 8'h00;
                    params_E0[1]  <= 8'h03;
                    params_E0[2]  <= 8'h09;
                    params_E0[3]  <= 8'h08;
                    params_E0[4]  <= 8'h16;
                    params_E0[5]  <= 8'h0A;
                    params_E0[6]  <= 8'h3F;
                    params_E0[7]  <= 8'h78;
                    params_E0[8]  <= 8'h4C;
                    params_E0[9]  <= 8'h09;
                    params_E0[10] <= 8'h0A;
                    params_E0[11] <= 8'h08;
                    params_E0[12] <= 8'h16;
                    params_E0[13] <= 8'h1A;
                    params_E0[14] <= 8'h0F;

                    params_E1[0]  <= 8'h00;
                    params_E1[1]  <= 8'h16;
                    params_E1[2]  <= 8'h19;
                    params_E1[3]  <= 8'h03;
                    params_E1[4]  <= 8'h0F;
                    params_E1[5]  <= 8'h05;
                    params_E1[6]  <= 8'h32;
                    params_E1[7]  <= 8'h45;
                    params_E1[8]  <= 8'h46;
                    params_E1[9]  <= 8'h04;
                    params_E1[10] <= 8'h0E;
                    params_E1[11] <= 8'h0D;
                    params_E1[12] <= 8'h35;
                    params_E1[13] <= 8'h37;
                    params_E1[14] <= 8'h0F;

                    params_C0[0] <= 8'h17;
                    params_C0[1] <= 8'h15;

                    params_C1 <= 8'h41;

                    params_C5[0] <= 8'h00;
                    params_C5[1] <= 8'h12;
                    params_C5[2] <= 8'h80;

                    params_B0 <= 8'h00;
                    params_B1 <= 8'hA0;
                    params_B4 <= 8'h02;

                    params_B6[0] <= 8'h02;
                    params_B6[1] <= 8'h02;
                    params_B6[2] <= 8'h3B;

                    params_B7 <= 8'hC6;

                    params_F7[0] <= 8'hA9;
                    params_F7[1] <= 8'h51;
                    params_F7[2] <= 8'h2C;
                    params_F7[3] <= 8'h02;
                end
                RESET_ASSERT: begin
                    nRST_r <= 0;
                    wait_count   <= T_RST_LOW;     // ILI9488 hardware reset low
                end
                RESET_RELEASE: begin
                    nRST_r <= 1;
                    wait_count   <= T_RST_WAIT;    // wait after reset release
                end
                LCD_SEL: begin
                    CSX_r <= 0;
                end
                CMD_SELECT: begin
                    wait_count   <= 32'd0;
                    DCX_r <= 0;
                    cmd_i <= cmd_i+1;
                    case (cmd_i)
                        5'd0 : begin cmd_r <= 8'h28; param_count <= 4'd0;end // Display off
                        5'd1 : begin cmd_r <= 8'hE0; param_count <= 4'd15;end
                        5'd2 : begin cmd_r <= 8'hE1; param_count <= 4'd15;end
                        5'd3 : begin cmd_r <= 8'hC0; param_count <= 4'd2;end
                        5'd4 : begin cmd_r <= 8'hC1; param_count <= 4'd1;end
                        5'd5 : begin cmd_r <= 8'hC5; param_count <= 4'd3;end
                        5'd6 : begin cmd_r <= 8'hB0; param_count <= 4'd1;end
                        5'd7 : begin cmd_r <= 8'hB1; param_count <= 4'd1;end
                        5'd8 : begin cmd_r <= 8'hB4; param_count <= 4'd1;end
                        5'd9 : begin cmd_r <= 8'hB6; param_count <= 4'd3;end
                        5'd10: begin cmd_r <= 8'hB7; param_count <= 4'd1;end
                        5'd11: begin cmd_r <= 8'hF7; param_count <= 4'd4;end
                        5'd12: begin cmd_r <= 8'h36; param_count <= 4'd1;end // MADCTL
                        5'd13: begin cmd_r <= 8'h3A; param_count <= 4'd1;end // COLMOD
                        5'd14: begin cmd_r <= 8'h20; param_count <= 4'd0;end // Inversion off (8'h21 for Inversion on)
                        5'd15: begin cmd_r <= 8'h34; param_count <= 4'd0;end // TE off
                        5'd16: begin cmd_r <= 8'h11; param_count <= 4'd0; wait_count <= T_SLEEP; end // Sleep out
                        5'd17: begin cmd_r <= 8'h38; param_count <= 4'd0;end // Idle mode off
                        5'd18: begin cmd_r <= 8'h13; param_count <= 4'd0;end // Normal display mode
                        5'd19: begin cmd_r <= 8'h2C; param_count <= 4'd0;end // Normal display mode
                        5'd20: begin cmd_r <= 8'h29; param_count <= 4'd0; wait_count <= T_DISPON; end // Display on
                        default: ;
                    endcase
                end
                PARAM_WRITE: begin
                    DCX_r <= 1;
                    param_i <= param_i+1;
                    case (cmd_i) // cmd_i is indexed one higher due to CMD_SELECT cmd_i increase before PARAM_WRITE STATE
                        5'd2 : param_r <= params_E0[param_i];
                        5'd3 : param_r <= params_E1[param_i];
                        5'd4 : param_r <= params_C0[param_i];
                        5'd5 : param_r <= params_C1;
                        5'd6 : param_r <= params_C5[param_i];
                        5'd7 : param_r <= params_B0;
                        5'd8 : param_r <= params_B1;
                        5'd9 : param_r <= params_B4;
                        5'd10: param_r <= params_B6[param_i];
                        5'd11: param_r <= params_B7;
                        5'd12: param_r <= params_F7[param_i];
                        5'd13: param_r <= 8'h28; // MADCTL: MV+BGR (MX removed: it flipped the landscape image vertically)
                        5'd14: param_r <= 8'h55; // COLMOD: parallel RGB565
                        default: param_r <= 8'h0;
                    endcase
                end
                SETUP: begin
                    CSX_r <= 0;
                    WRX_r <= 1;
                end
                LOW: begin
                    WRX_r <= 0;
                end
                HOLD: begin
                    WRX_r <= 1;
                end
                LCD_NSEL: begin
                    CSX_r <= 1;
                    param_i <= 4'd0;
                end
                WAIT: begin
                    wait_count <= wait_count-1;
                end
                END_STATE: begin

                end
                default: ;
            endcase
        end
    end

    assign CSX   = CSX_r;
    assign DCX   = DCX_r;
    assign WRX   = WRX_r;
    assign nRST   = nRST_r;
    assign cmd   = {8'b0, cmd_r};
    assign param = {8'b0, param_r};
    assign init_done = (STATE == END_STATE);

endmodule