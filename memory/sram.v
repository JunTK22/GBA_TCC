module iwram // Single port asynchronus RAM
	# (
	parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 15 // 32.767 bytes (32 KB)
	)
	(
	input wire clk,
	input wire we, // write enable
	
	input wire [ADDR_WIDTH-1:0] addr,
	input wire [DATA_WIDTH-1:0] wr_data,
	
	output wire [DATA_WIDTH-1:0] rd_data	
	);

reg [7:0] mem [2**DEPTH];

wire [DEPTH-1:0] addr_w;
assign addr_w <= addr[DEPTH-1:0];

always @(posedge clk) begin
	if(we) begin
		{mem[addr_w+3], mem[addr_w+2], mem[addr_w+1], mem[addr_w]} <= wr_data;
	end
end

assign rd_data = {mem[addr_w+3], mem[addr_w+2], mem[addr_w+1], mem[addr_w]};

endmodule