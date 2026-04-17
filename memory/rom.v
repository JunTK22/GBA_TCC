module rom // Single port ROM
	# (
	parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 14 // 16.383 bytes (16 KB)
    parameter ROM = "GBA_bios.rom"
	)
	(	
	input wire [ADDR_WIDTH-1:0] addr,
	output wire [DATA_WIDTH-1:0] rd_data	
	);

reg [7:0] mem [2**DEPTH];

wire [DEPTH-1:0] addr_w;
assign addr_w <= addr[DEPTH-1:0];

assign rd_data = {mem[addr_w+3], mem[addr_w+2], mem[addr_w+1], mem[addr_w]};

initial begin
	$readmemh(ROM, mem);
begin

endmodule