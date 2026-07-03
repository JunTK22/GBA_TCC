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

    localparam IDLE         = 0;
    localparam SETUP        = 0;
    localparam INIT_FETCH   = 0;
    localparam BG1_RENDER   = 0;
    localparam BG2_RENDER   = 0;
    localparam BG3_RENDER   = 0;
    localparam BG4_RENDER   = 0;

    reg [9:0] STATE, NEXT_STATE = 0;
    
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





endmodule