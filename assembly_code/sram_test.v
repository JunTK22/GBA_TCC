module sram_test (
    input wire clk,
    input wire we,
    input wire [31:0] wr_data,
    input wire [31:0] addr,

    input wire [1:0]  size,
    input wire        sign_extend;

    output wire [31:0] rd_data
);

parameter DEPTH_POW2 = 10;

wire [12:0] addr_lo;
wire [12:0] addr_hi;

assign addr_lo = addr[12:0];
assign addr_hi = addr[12:0]+1'h1;

sram sram(
    .DEPTH_POW2 (DEPTH_POW2)           // 2^10 = 1024 words = 4 KB

    .clk (clk),

    .addr (addr[DEPTH_POW2+1:0]),           // byte address
    .wdata (wr_data),          // write data (right-aligned)
    .rdata (rd_data),          // read  data (right-aligned)
    .we (we),             // write enable
    .size (size),           // 00=byte 01=half 10=word
    .sign_extend (sign_extend),    // sign-extend on read

    .ready (),          // 1 unless fault
    .misalign_fault ()  // alignment error flag
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