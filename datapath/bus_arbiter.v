// =============================================================================
//  bus_arbiter.v
//  Combinational shared-bus master mux.
//
//  Selects CPU or DMA0..DMA3 address, write data, access size, and direction.
//  DMA channels have fixed priority DMA0, DMA1, DMA2, DMA3, then CPU. For DMA,
//  `wr_en_dma` selects destination address/write phase versus source address/read
//  phase, and also becomes the bus `nRW` value while any DMA is active.
// =============================================================================

module bus_arbiter (
    input wire  [31:0] addr_cpu,
    input wire  [31:0] addr_src_dma0, addr_dst_dma0,
    input wire  [31:0] addr_src_dma1, addr_dst_dma1,
    input wire  [31:0] addr_src_dma2, addr_dst_dma2,
    input wire  [31:0] addr_src_dma3, addr_dst_dma3,

    input wire  [31:0] data_cpu,
    input wire  [31:0] data_dma0,
    input wire  [31:0] data_dma1,
    input wire  [31:0] data_dma2,
    input wire  [31:0] data_dma3,

    input wire [1:0]  MAS_cpu,
    input wire [1:0]  MAS_dma0,
    input wire [1:0]  MAS_dma1,
    input wire [1:0]  MAS_dma2,
    input wire [1:0]  MAS_dma3,

    input wire         nRW_CPU,
    input wire         wr_en_dma,
    input wire  [3:0]  dma_active,

    output wire [31:0] addr_o,
    output wire [31:0] data_o,
    output wire [1:0]  MAS,
    output wire        nRW
);

wire [31:0] addr_src =  dma_active[0] ? addr_src_dma0 :
                        dma_active[1] ? addr_src_dma1 :
                        dma_active[2] ? addr_src_dma2 :
                        dma_active[3] ? addr_src_dma3 :
                        addr_cpu;

wire [31:0] addr_dst =  dma_active[0] ? addr_dst_dma0 :
                        dma_active[1] ? addr_dst_dma1 :
                        dma_active[2] ? addr_dst_dma2 :
                        dma_active[3] ? addr_dst_dma3 :
                        addr_cpu;

wire [31:0] data     =  dma_active[0] ? data_dma0 :
                        dma_active[1] ? data_dma1 :
                        dma_active[2] ? data_dma2 :
                        dma_active[3] ? data_dma3 :
                        data_cpu;

assign      MAS     =   dma_active[0] ? MAS_dma0 :
                        dma_active[1] ? MAS_dma1 :
                        dma_active[2] ? MAS_dma2 :
                        dma_active[3] ? MAS_dma3 :
                        MAS_cpu;

assign addr_o = wr_en_dma ? addr_dst : addr_src;
assign data_o = data;
assign nRW    = dma_active == 4'b0 ? nRW_CPU : wr_en_dma;

endmodule
