// =============================================================================
//  gba_ram_w16.v
//  16-bit-port ARM-bus RAM template (M10K-backed).
//
//  Used by GBA memory regions whose port size is 16 bits per CowBite §3:
//    EWRAM (256 KB), VRAM (96 KB rounded to 128 KB), Palette RAM (1 KB).
//
//  CPU interface:
//    addr   — byte address (DEPTH_POW2+1 bits wide).
//    size   — 0 = byte, 1 = halfword.
//    The CPU bus controller is responsible for issuing two transactions for
//    32-bit accesses on this 16-bit port.
//
//  Behaviour:
//    1-cycle read latency. Byte accesses optionally sign-extend to 16 bits.
//    Halfword accesses must be 2-byte aligned; misaligned halfword sets
//    misalign_fault on the next cycle (paired with we_q for write faults)
//    and `ready` deasserts the same cycle.
//
//  Implementation follows the same M10K-inferable pattern as sram.v: storage
//  and the synchronous read register live in the M10K instance, all ARM
//  size/sign-extension logic operates on the registered output one stage
//  later.
// =============================================================================

`timescale 1ns / 1ps

module gba_ram_w16 #(
    parameter DEPTH_POW2 = 9,                 // 2^DEPTH_POW2 halfwords
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire                       clk,

    // CPU interface
    input  wire [DEPTH_POW2 : 0]      addr,           // byte address
    input  wire [15:0]                wdata,
    output reg  [15:0]                rdata,
    input  wire                       we,
    input  wire                       size,           // 0=byte 1=half
    input  wire                       sign_extend,

    // Status
    output wire                       ready,
    output reg                        misalign_fault
);

    localparam SIZE_BYTE = 1'b0;
    localparam SIZE_HALF = 1'b1;

    // -------------------------------------------------------------------------
    //  Address split
    // -------------------------------------------------------------------------
    wire [DEPTH_POW2-1:0] hword_addr = addr[DEPTH_POW2 : 1];
    wire                  byte_lane  = addr[0];

    // -------------------------------------------------------------------------
    //  Alignment check
    // -------------------------------------------------------------------------
    wire misalign_comb = (size == SIZE_HALF) && addr[0];
    assign ready = ~misalign_comb;

    // -------------------------------------------------------------------------
    //  Byte-enable generation
    // -------------------------------------------------------------------------
    reg [1:0] byteena;
    always @(*) begin
        case (size)
            SIZE_BYTE: byteena = byte_lane ? 2'b10 : 2'b01;
            SIZE_HALF: byteena = 2'b11;
            default:   byteena = 2'b00;
        endcase
    end

    // -------------------------------------------------------------------------
    //  Write-data alignment: replicate byte into both lanes; byteena selects.
    // -------------------------------------------------------------------------
    reg [15:0] wdata_shifted;
    always @(*) begin
        case (size)
            SIZE_BYTE: wdata_shifted = {2{wdata[7:0]}};
            SIZE_HALF: wdata_shifted = wdata;
            default:   wdata_shifted = 16'h0;
        endcase
    end

    wire write_en = we & ~misalign_comb;

    // -------------------------------------------------------------------------
    //  M10K instance
    // -------------------------------------------------------------------------
    wire [15:0] read_data;

    M10K #(
        .WIDTH      (16),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) ram_inst (
        .addr    (hword_addr),
        .byteena (byteena),
        .clk     (clk),
        .data    (wdata_shifted),
        .wren    (write_en),
        .q       (read_data)
    );

    // -------------------------------------------------------------------------
    //  Pipelined CPU-side qualifiers (line up with read_data)
    // -------------------------------------------------------------------------
    reg       size_q        = 1'b0;
    reg       byte_lane_q   = 1'b0;
    reg       sign_extend_q = 1'b0;
    reg       misalign_q    = 1'b0;
    reg       we_q          = 1'b0;

    always @(posedge clk) begin
        size_q        <= size;
        byte_lane_q   <= byte_lane;
        sign_extend_q <= sign_extend;
        misalign_q    <= misalign_comb;
        we_q          <= we;
    end

    // -------------------------------------------------------------------------
    //  Output formatting (combinational on the registered read data)
    // -------------------------------------------------------------------------
    reg [7:0] byte_sel;
    always @(*) begin
        byte_sel = byte_lane_q ? read_data[15:8] : read_data[7:0];

        case (size_q)
            SIZE_BYTE: rdata = sign_extend_q ? {{8{byte_sel[7]}}, byte_sel}
                                             : {8'h0, byte_sel};
            SIZE_HALF: rdata = read_data;
            default:   rdata = 16'h0;
        endcase

        misalign_fault = misalign_q & we_q;
    end

endmodule
