// =============================================================================
//  oam.v
//  1 KiB, single-port Object Attribute Memory with CPU/DMA/PPU arbitration.
//
//  The CPU/DMA port is byte addressed; the PPU port uses 32-bit word indices.
//  An active PPU read has priority unless force blank is asserted. A colliding
//  CPU/DMA request holds `ready` low and is retried through the shared nWAIT
//  path. PPU-only traffic does not stall that global ready chain.
//
//  Reads are synchronous. GBA OAM permits 8/16/32-bit reads and 16/32-bit
//  writes; byte writes complete without changing memory.
// =============================================================================

`timescale 1ns / 1ps

module oam (
    input  wire        clk,

    input  wire [9:0]  addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault,

    input  wire [7:0]  ppu_addr,
    input  wire        ppu_rden,
    output wire [31:0] ppu_rdata,
    input  wire        force_blank
);

    localparam [1:0] SIZE_BYTE = 2'b00;
    localparam [1:0] SIZE_WORD = 2'b10;

    wire cpu_request = we || rden;
    wire ppu_request = ppu_rden && !force_blank;
    wire cpu_grant = cpu_request && !ppu_request;

    wire [9:0] mem_addr =
        ppu_request ? {ppu_addr, 2'b00} : addr;
    wire [1:0] mem_size =
        ppu_request ? SIZE_WORD : size;
    wire mem_we =
        cpu_grant && we && (size != SIZE_BYTE);
    wire mem_rden =
        ppu_request || (cpu_grant && rden);

    wire [31:0] mem_rdata;
    wire mem_ready;
    wire mem_misalign_fault;

    sram #(
        .DEPTH_POW2 (8),
        .INIT_FILE  ("UNUSED")
    ) oam_mem (
        .clk            (clk),
        .addr           (mem_addr),
        .wdata          (wdata),
        .rdata          (mem_rdata),
        .we             (mem_we),
        .rden           (mem_rden),
        .size           (mem_size),
        .sign_extend    (ppu_request ? 1'b0 : sign_extend),
        .ready          (mem_ready),
        .misalign_fault (mem_misalign_fault)
    );

    assign rdata = mem_rdata;
    assign ppu_rdata = mem_rdata;

    // PPU-only traffic must not stall the global CPU/DMA ready chain.
    assign ready =
        !cpu_request || (!ppu_request && mem_ready);
    assign misalign_fault = mem_misalign_fault;

endmodule
