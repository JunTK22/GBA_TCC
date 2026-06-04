// =============================================================================
//  palette_ram.v
//  Palette RAM — 1 KB, 16-bit port.
//
//  Memory map: 0x05000000 - 0x050003FF.
//  Per CowBite §3: 256 16-bit BG palette entries at 0x05000000 +
//  256 16-bit OBJ palette entries at 0x05000200.
//  Zero-initialised by BIOS at startup.
// =============================================================================

`timescale 1ns / 1ps

module palette_ram (
    input  wire        clk,
    input  wire [9:0]  addr,           // 1 KB byte address
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire        size,           // 0=byte, 1=halfword
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    gba_ram_w16 #(
        .DEPTH_POW2 (9),                // 2^9 = 512 halfwords = 1 KB
        .INIT_FILE  ("UNUSED")
    ) palette_mem (
        .clk            (clk),
        .addr           (addr),
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
