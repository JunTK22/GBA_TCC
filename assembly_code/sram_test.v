module sram_test (
    input wire clk,
    input wire we,
    input wire [31:0] wr_data,
    input wire [31:0] addr,

    output wire [31:0] rd_data
);

wire [12:0] addr_lo;
wire [12:0] addr_hi;

assign addr_lo = addr[12:0];
assign addr_hi = addr[12:0]+1'h1;

sram sram(
    .address_a(addr_lo),
    .address_b(addr_hi),
    .clock(~clk),
    .data_a(wr_data[15:0]),
    .data_b(wr_data[31:16]),
    .wren_a(we),
    .wren_b(we),
    .q_a(rd_data[15:0]),
    .q_b(rd_data[31:16])
);

//reg [15:0] mem [0:6000];
//reg [31:0] rd_data_r = 0;
//
//initial begin
//    $readmemh("instrucoes.hex", mem);
//end
//
//always @(negedge clk) begin
//    if (we) begin
//        mem[addr_lo] <= wr_data[15:0];
//        mem[addr_hi] <= wr_data[31:16];
//    end
//    rd_data_r[15:0]  <= mem[addr_lo];
//    rd_data_r[31:16] <= mem[addr_hi];
//end
//
//assign rd_data = rd_data_r;

endmodule