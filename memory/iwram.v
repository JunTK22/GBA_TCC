// =============================================================================
//  iwram.v
//  Internal Work RAM (IWRAM) — 32 KB, 32-bit port.
//
//  Memory map: 0x03000000 - 0x03007FFF (mirrored every 0x8000 to 0x03FFFFFF).
//  Per CowBite §3: fastest of the GBA's RAMs; place 32-bit ARM code here.
//  Zero-initialised by BIOS at startup.
//
//  32-bit ARM-bus interface inherited from sram.v: byte/half/word access with
//  optional sign-extension and misalignment fault.
// =============================================================================

`timescale 1ns / 1ps

module iwram (
    input  wire        clk,
    input  wire [14:0] addr,           // 32 KB byte address
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,           // 00=byte 01=half 10=word
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    sram #(
        .DEPTH_POW2 (13),               // 2^13 = 8192 words = 32 KB
        .INIT_FILE  ("UNUSED")
    ) iwram_mem (
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
