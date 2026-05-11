// =============================================================================
//  oam.v
//  Object Attribute Memory (OAM) — 1 KB, 32-bit port.
//
//  Memory map: 0x07000000 - 0x070003FF (mirrored every 0x400 to 0x07FFFFFF).
//  Per CowBite §3 / §6: holds the 128 OBJ attribute entries (8 bytes each)
//  plus the rotation/scaling matrix entries interleaved between them.
//  Zero-initialised by BIOS at startup.
//
//  32-bit ARM-bus interface inherited from sram.v.
// =============================================================================

`timescale 1ns / 1ps

module oam (
    input  wire        clk,
    input  wire [9:0]  addr,            // 1 KB byte address
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire [1:0]  size,
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    sram #(
        .DEPTH_POW2 (8),                 // 2^8 = 256 words = 1 KB
        .INIT_FILE  ("UNUSED")
    ) oam_mem (
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
