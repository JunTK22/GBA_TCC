`timescale 1ns / 1ps

module sram #(
    parameter DEPTH_POW2 = 8           // 2^8 = 256 words = 1 KB
)(
    // -------------------------------------------------------------------------
    //  Clock / Reset
    // -------------------------------------------------------------------------
    input  wire                       clk,

    // -------------------------------------------------------------------------
    //  CPU Interface
    // -------------------------------------------------------------------------
    input  wire [DEPTH_POW2-1 : 0]    addr,           // byte address
    input  wire [31:0]                wdata,          // write data (right-aligned)
    input  wire                       we,             // write enable
    
	output reg  [31:0]                rdata,          // read  data (right-aligned)
);

    // =========================================================================
    //  Local parameters
    // =========================================================================
    localparam DEPTH = 1 << DEPTH_POW2;   // number of 32-bit words

    // =========================================================================
    //  M10K array declaration
    //  Each entry is 32 bits wide; depth = DEPTH words.
    //  The attribute tells Quartus to use M10K blocks.
    // =========================================================================
    (* ramstyle = "M10K" *)
    reg [31:0] mem [0 : DEPTH-1];

	always @(posedge clk) begin
		if (we) mem[addr] = wdata;
		rdata = mem[addr];
	end

endmodule
