module moduleName (
    input wire  clock,
    input wire  nrst,

    input wire  [2:0] BG_MODE;

    // Either BG Map Entry, BG Map Tile or BG Bitmap
    input wire  [31:0] bg_addr;
    input wire  [15:0] rd_data;

    // BG Control registers
    input wire  [15:0]  BG0_CTN,
    input wire  [15:0]  BG1_CTN,
    input wire  [15:0]  BG2_CTN,
    input wire  [15:0]  BG3_CTN,
    
    // BG Scrolling: Specifies the coordinate of the upperleft
    // first visible dot of BG0 background layer, ie. used to scroll the BG0 area.
    input wire  [15:0]  BG0_H0FS,
    input wire  [15:0]  BG0_V0FS,
    input wire  [15:0]  BG1_H0FS,
    input wire  [15:0]  BG1_V0FS,
    input wire  [15:0]  BG2_H0FS,
    input wire  [15:0]  BG2_V0FS,
    input wire  [15:0]  BG3_H0FS,
    input wire  [15:0]  BG3_V0FS,

    // Rotation/Scalling reference points (BG Scrolling is ignored)
    // and parameters
    input wire  [15:0]  BG2_X_L,
    input wire  [15:0]  BG2_X_H,
    input wire  [15:0]  BG2_Y_L,
    input wire  [15:0]  BG2_Y_H,
    input wire  [15:0]  BG2_PA,
    input wire  [15:0]  BG2_PB,
    input wire  [15:0]  BG2_PC,
    input wire  [15:0]  BG2_PD,
    input wire  [15:0]  BG3_X_L,
    input wire  [15:0]  BG3_X_H,
    input wire  [15:0]  BG3_Y_L,
    input wire  [15:0]  BG3_Y_H,
    input wire  [15:0]  BG3_PA,
    input wire  [15:0]  BG3_PB,
    input wire  [15:0]  BG3_PC,
    input wire  [15:0]  BG3_PD
);

    localparam START        = 0;
    localparam IDLE         = 1;
    localparam SETUP        = 2;
    localparam INIT_FETCH   = 3;
    localparam BG1_RENDER   = 4;
    localparam BG2_RENDER   = 5;
    localparam BG3_RENDER   = 6;
    localparam BG4_RENDER   = 7;

    reg [9:0] STATE, NEXT_STATE = START;
    
    wire BG0_8bpp = BG0_CTN[7];
    wire BG1_8bpp = BG1_CTN[7];
    wire BG2_8bpp = BG2_CTN[7];
    wire BG3_8bpp = BG3_CTN[7];

    reg [15:0]  BG0_map_entry = 16'b0;
    reg [15:0]  BG1_map_entry = 16'b0;
    reg [15:0]  BG2_map_entry = 16'b0;
    reg [15:0]  BG3_map_entry = 16'b0;
    
    reg [15:0]  BG0_pixel = 16'b0;
    reg [15:0]  BG1_pixel = 16'b0;
    reg [15:0]  BG2_pixel = 16'b0;
    reg [15:0]  BG3_pixel = 16'b0;

    always @(posedge clock or negedge nrst) begin
        if (!nrst) STATE <= START;
        else STATE <= NEXT_STATE;
    end

    always @(*) begin
        case (STATE)
            START: begin
                BG0_map_entry <= 16'b0;
                BG1_map_entry <= 16'b0;
                BG2_map_entry <= 16'b0;
                BG3_map_entry <= 16'b0;

                BG0_pixel <= 16'b0;
                BG1_pixel <= 16'b0;
                BG2_pixel <= 16'b0;
                BG3_pixel <= 16'b0;

                NEXT_STATE <= START;
            end
            IDLE: begin
                BG0_map_entry <= 16'b0;
                BG1_map_entry <= 16'b0;
                BG2_map_entry <= 16'b0;
                BG3_map_entry <= 16'b0;

                BG0_pixel <= 16'b0;
                BG1_pixel <= 16'b0;
                BG2_pixel <= 16'b0;
                BG3_pixel <= 16'b0;

                NEXT_STATE <= SETUP;
            end
            SETUP: begin
                bg_addr <= BG0_CTN[12:8] * 1024

                NEXT_STATE <= SETUP;
            end
            default: 
        endcase
    end

endmodule