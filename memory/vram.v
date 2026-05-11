// =============================================================================
//  vram.v
//  Video RAM (VRAM) — 96 KB physical, 128 KB allocated, 16-bit port.
//
//  Memory map: 0x06000000 - 0x06017FFF (96 KB).
//  Bytes 0x06010000 - 0x06017FFF are mirrored at 0x06018000 - 0x0601FFFF
//  per CowBite §3 — handled by the bus decoder upstream, not here.
//
//  We allocate 128 KB (DEPTH_POW2 = 16) because M10K block sizing is a power
//  of two; the upper 32 KB is unmapped from the CPU's perspective and the bus
//  decoder is expected to fold (or reject) accesses to that range.
//
//  Zero-initialised by BIOS at startup.
// =============================================================================

`timescale 1ns / 1ps

module vram (
    input  wire        clk,
    input  wire [16:0] addr,           // 128 KB byte address
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    input  wire        we,
    input  wire        size,           // 0=byte, 1=halfword
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    gba_ram_w16 #(
        .DEPTH_POW2 (16),               // 2^16 = 65536 halfwords = 128 KB
        .INIT_FILE  ("UNUSED")
    ) vram_mem (
        .clk            (clk),
        .addr           (addr),
        .wdata          (wdata),
        .rdata          (rdata),
        .we             (we),
        .size           (size),
        .sign_extend    (sign_extend),
        .ready          (ready),
        .misalign_fault (misalign_fault)
    );

endmodule
