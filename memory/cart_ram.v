// =============================================================================
//  cart_ram.v
//  Game Pak Cart RAM (battery-backed SRAM) — 64 KB, 8-bit port.
//
//  Memory map: 0x0E000000 - 0x0E00FFFF (also mirrored at 0x0F000000).
//  Per CowBite §3: 8-bit port, used for save data. Modeled here as on-chip
//  M10K — battery backing, flash erase semantics, etc. are out of scope.
//
//  CPU interface: byte-addressed, byte-only. The CPU bus controller is
//  responsible for splitting wider accesses into multiple byte transactions
//  and for any sign-extension after read.
//
//  Read timing:
//        cycle 0:  addr / we / wdata presented
//        cycle 1:  rdata valid
// =============================================================================

`timescale 1ns / 1ps

module cart_ram #(
    parameter DEPTH_POW2 = 16,                  // 2^16 = 65536 bytes = 64 KB
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire                       clk,
    input  wire [DEPTH_POW2-1:0]      addr,     // byte address
    input  wire [7:0]                 wdata,
    output wire [7:0]                 rdata,
    input  wire                       we,
    input  wire                       rden
);

    M10K #(
        .WIDTH      (8),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) cart_mem (
        .addr    (addr),
        .byteena (1'b1),       // single-lane: writes gated by `we`
        .clk     (clk),
        .data    (wdata),
        .wren    (we),
        .q       (rdata)
    );

endmodule
