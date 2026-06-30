// =============================================================================
//  vram.v
//  Video RAM (VRAM) — 96 KB physical, 128 KB allocated, 16-bit port.
//
//  Memory map: 0x06000000 - 0x06017FFF (96 KB).
//  Bytes 0x06010000 - 0x06017FFF are mirrored at 0x06018000 - 0x0601FFFF
//  per CowBite §3.
//
//  We allocate 128 KB (DEPTH_POW2 = 16) because M10K block sizing is a power
//  of two. The wrapper folds addr[16] into the documented 96 KB mirror window.
//
//  Wraps `gba_ram_w16`, so word accesses are assembled from two 16-bit beats.
// =============================================================================

`timescale 1ns / 1ps

module vram (
    input  wire        clk,
    input  wire [16:0] addr,           // 128 KB byte address
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,           // 0=byte, 1=halfword
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    wire [16:0] addr_w = addr[16] ? {2'b10, addr[14:0]} : addr;

    gba_ram_w16 #(
        .DEPTH_POW2 (16),               // 2^16 = 65536 halfwords = 128 KB
        .INIT_FILE  ("UNUSED")
    ) vram_mem (
        .clk            (clk),
        .addr           (addr_w),
        .wdata          (wdata),
        .rdata          (rdata),
        .we             (we),
        .rden           (rden),
        .size           (size),
        .sign_extend    (sign_extend),
        .ready          (ready),
        .misalign_fault (misalign_fault)
    );

endmodule
