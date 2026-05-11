// =============================================================================
//  ewram.v
//  External Work RAM (EWRAM) — 256 KB, 16-bit port.
//
//  Memory map: 0x02000000 - 0x0203FFFF (mirrored every 0x40000 to 0x02FFFFFF).
//  Per CowBite §3: general-purpose data/code RAM, 16-bit bus → 32-bit ARM
//  accesses cost twice as many cycles as IWRAM.
//  Zero-initialised by BIOS at startup.
// =============================================================================

`timescale 1ns / 1ps

module ewram (
    input  wire        clk,
    input  wire [17:0] addr,           // 256 KB byte address
    input  wire [15:0] wdata,
    output wire [15:0] rdata,
    input  wire        we,
    input  wire        size,           // 0=byte, 1=halfword
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault
);

    gba_ram_w16 #(
        .DEPTH_POW2 (17),               // 2^17 = 131072 halfwords = 256 KB
        .INIT_FILE  ("UNUSED")
    ) ewram_mem (
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
