module bus_controller
	(	
	input  wire [ADDR_WIDTH-1:0] rd_addr,
	input  wire is_str,
	
	output wire [3:0] data_bus_sel,
	output wire [15:0] we_sel,
	);

parameter BIOS  	= 'h0;
parameter EWRAM 	= 'h2;
parameter IWRAM  	= 'h3;
parameter IO_RAM	= 'h4;
parameter PAL_RAM 	= 'h5;
parameter VRAM  	= 'h6;
parameter OAM	  	= 'h7;
parameter PAK_ROM  	= 'h8;
parameter CART_RAM  = 'hE;
parameter ARM7TDMI  = 'hF;

reg [3:0] mem_section;
reg [3:0] cs_r = 0;
reg [15:0] we_sel_r = 0;

assign mem_section <= rd_addr[27:24];
assign data_bus_sel <= cs_r;
assign we_sel <= we_sel_r;

always @(*) begin
	we_sel_r <= 16'b0;
	if (is_str) begin
		cs_r = ARM7TDMI;
		we_sel_r[mem_section] <= 1;
	end else begin
		we_sel_r <= 16'b0;
		case (mem_section) begin
			4'h0: cs_r = BIOS;
			4'h2: cs_r = EWRAM;
			4'h3: cs_r = IWRAM;
			4'h4: cs_r = IO_RAM;
			4'h5: cs_r = PAL_RAM;
			4'h6: cs_r = VRAM;
			4'h7: cs_r = OAM;
			4'h8: cs_r = PAK_ROM;
			4'h9: cs_r = PAK_ROM;
			4'hE: cs_r = CART_RAM;
			default: cs_r = BIOS;
		endcase
	end
end

endmodule