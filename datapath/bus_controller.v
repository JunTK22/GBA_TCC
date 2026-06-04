module bus_controller(	
	input  wire [31:0]	rd_addr,
	input  wire 		nRW,

	input  wire [31:0]	data_bios,
	input  wire [31:0]	data_ewram,
	input  wire [31:0]	data_iwram,
	input  wire [31:0]	data_ioram,
	input  wire [31:0]	data_palram,
	input  wire [31:0]	data_vram,
	input  wire [31:0]	data_oam,
	input  wire [31:0]	data_pakrom,
	input  wire [31:0]	data_cartram,
	input  wire [31:0]	data_main,

	output reg  [31:0]	data_o,

	output reg			rden_bios,
	output reg			rden_ewram,
	output reg			rden_iwram,
	output reg			rden_palram,
	output reg			rden_vram,
	output reg			rden_oam,
	output reg			rden_pakrom,
	output reg			rden_cartram,

	output reg	 		we_ewram,
	output reg	 		we_iwram,
	output reg	 		we_ioram,
	output reg	 		we_palram,
	output reg	 		we_vram,
	output reg	 		we_oam,
	output reg	 		we_cartram
);

wire [3:0] mem_section;
assign mem_section = rd_addr[27:24];

always @(*) begin
	if (nRW) begin
		data_o = data_main;
		we_ewram	= 0;
		we_iwram	= 0;
		we_ioram	= 0;
		we_palram	= 0;
		we_vram	 	= 0;
		we_oam	 	= 0;
		we_cartram	= 0;
		case (mem_section) 
			4'h2: we_ewram	 = 1;	//EWRAM
			4'h3: we_iwram	 = 1;	//IWRAM
			4'h4: we_ioram	 = 1;	//IO_RAM
			4'h5: we_palram	 = 1;	//PAL_RAM
			4'h6: we_vram	 = 1;	//VRAM
			4'h7: we_oam	 = 1;	//OAM
			4'hE: we_cartram = 1;	//CART_RAM
			4'hF: we_cartram = 1;	//CART_RAM
			default:;
		endcase
	end else begin
		case (mem_section) 
			4'h0: data_o = data_bios;	//BIOS
			4'h1: data_o = data_bios;	//BIOS
			4'h2: data_o = data_ewram;	//EWRAM
			4'h3: data_o = data_iwram;	//IWRAM
			4'h4: data_o = data_ioram;	//IO_RAM
			4'h5: data_o = data_palram;	//PAL_RAM
			4'h6: data_o = data_vram;	//VRAM
			4'h7: data_o = data_oam;	//OAM
			4'h8: data_o = data_pakrom;	//PAK_ROM
			4'h9: data_o = data_pakrom;	//PAK_ROM
			4'hA: data_o = data_pakrom;	//PAK_ROM
			4'hB: data_o = data_pakrom;	//PAK_ROM
			4'hC: data_o = data_pakrom;	//PAK_ROM
			4'hD: data_o = data_pakrom;	//PAK_ROM
			4'hE: data_o = data_cartram;//CART_RAM
			4'hF: data_o = data_cartram;//CART_RAM
		endcase
		rden_bios	= 0;
		rden_ewram	= 0;
		rden_iwram	= 0;
		rden_palram	= 0;
		rden_vram	= 0;
		rden_oam	= 0;
		rden_pakrom	= 0;
		rden_cartram= 0;
		case (mem_section) 
			4'h0: rden_bios 	= 1;	//BIOS
			4'h1: rden_bios 	= 1;	//BIOS
			4'h2: rden_ewram 	= 1;	//EWRAM
			4'h3: rden_iwram 	= 1;	//IWRAM
			4'h5: rden_palram 	= 1;	//PAL_RAM
			4'h6: rden_vram 	= 1;	//VRAM
			4'h7: rden_oam 		= 1;	//OAM
			4'h8: rden_pakrom 	= 1;	//PAK_ROM
			4'h9: rden_pakrom 	= 1;	//PAK_ROM
			4'hA: rden_pakrom 	= 1;	//PAK_ROM
			4'hB: rden_pakrom 	= 1;	//PAK_ROM
			4'hC: rden_pakrom 	= 1;	//PAK_ROM
			4'hD: rden_pakrom 	= 1;	//PAK_ROM
			4'hE: rden_cartram 	= 1;	//CART_RAM
			4'hF: rden_cartram 	= 1;	//CART_RAM
			default:;
		endcase
	end
end

endmodule