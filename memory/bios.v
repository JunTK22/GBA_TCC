// =============================================================================
//  bios.v
//  GBA System ROM (BIOS) — 16 KB, 32-bit port, read-only.
//
//  Memory map: 0x00000000 - 0x00003FFF.
//  Per CowBite §3 / GBA spec: "executable but not readable".
//
//  Thin M10K wrapper. The bus decoder is responsible for byte-lane selection
//  and for blocking visible reads (returning prefetched instructions instead).
//  This module simply exposes the raw 32-bit word at a given word address with
//  one cycle of read latency.
// =============================================================================

`timescale 1ns / 1ps

module bios #(
    parameter INIT_FILE = "assembly_code/bios.mif"
)(
    input  wire        clk,
    input  wire [11:0] addr,        // word address (4096 32-bit words = 16 KB)
    output wire [31:0] rdata
);

    M10K #(
        .WIDTH      (32),
        .DEPTH_POW2 (12),
        .INIT_FILE  (INIT_FILE)
    ) bios_mem (
        .addr    (addr),
        .byteena (4'b1111),
        .clk     (clk),
        .data    (32'b0),
        .wren    (1'b0),
        .q       (rdata)
    );

endmodule
