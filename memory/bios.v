// =============================================================================
//  bios.v
//  GBA System ROM (BIOS) — 16 KB, 32-bit port, read-only.
//
//  Memory map: 0x00000000 - 0x00003FFF.
//  The current bring-up top uses this as the CPU boot ROM and initializes it
//  from the top-level `INIT_FILE` parameter.
//
//  Read-only M10K-backed storage with byte/halfword/word read formatting,
//  optional sign extension, and combinational alignment-ready reporting.
//  Misalignment is reported on the registered read qualifier path.
// =============================================================================

`timescale 1ns / 1ps

module bios #(
    parameter INIT_FILE = "code/assembly_code/bios.mif"
)(
    input  wire        clk,
    input  wire [13:0] addr,        // word address (4096 32-bit words = 16 KB)
    output wire [31:0] rdata,
    input  wire        rden,
    input  wire [1:0]  size,           // 00=byte 01=half 10=word
    input  wire        sign_extend,    // sign-extend on read

    // Status
    output wire        ready,          // 1 unless fault
    output wire        misalign_fault  // alignment error flag
);

        // -------------------------------------------------------------------------
    //  Local parameters
    // -------------------------------------------------------------------------
    localparam DEPTH_POW2 = 12;

    localparam SIZE_BYTE = 2'b00;
    localparam SIZE_HALF = 2'b01;
    localparam SIZE_WORD = 2'b10;

    // -------------------------------------------------------------------------
    //  Address split
    // -------------------------------------------------------------------------
    wire [DEPTH_POW2-1:0] word_addr = addr[DEPTH_POW2+1 : 2];
    wire [1:0]            byte_lane = addr[1:0];

    // -------------------------------------------------------------------------
    //  Alignment check (combinational)
    // -------------------------------------------------------------------------
    wire misalign_comb = (((size == SIZE_HALF) && addr[0]) || ((size == SIZE_WORD) && |addr[1:0])) && (rden);
    assign ready = ~misalign_comb;

    // =========================================================================
    //  M10K-INFERABLE MEMORY BLOCK
    //
    //  Storage + synchronous read register live in a SINGLE always block.
    //  Byte-enable writes use a generate loop over 8-bit lanes — this is the
    //  Quartus-recognized byte-enable template that maps to native M10K
    //  byte-enable hardware.
    // =========================================================================

	wire [31:0] read_data;

    M10K #(
        .WIDTH      (32),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) bios_mem (
        .addr    (word_addr),
        .byteena (4'b1111),
        .clk     (clk),
        .data    (32'b0),
        .wren    (1'b0),
        .rden    (rden),
        .q       (read_data)
    );

    // =========================================================================
    //  Post-RAM pipeline stage: size selection + sign extension
    //  These signals are pipelined one cycle so they line up with mem_q.
    // =========================================================================
    reg [1:0] size_q = 2'b0;
    reg [1:0] byte_lane_q = 2'b0;
    reg       sign_extend_q = 0;
    reg       misalign_q = 0;

    always @(posedge clk) begin
        size_q        <= size;
        byte_lane_q   <= byte_lane;
        sign_extend_q <= sign_extend;
        misalign_q    <= misalign_comb;
    end

    // -------------------------------------------------------------------------
    //  Output formatting (combinational on the registered read data)
    // -------------------------------------------------------------------------
    reg [ 7:0] byte_sel = 0;
    reg [15:0] half_sel = 0;
    reg [31:0] rdata_next = 0;

    always @(*) begin
        // Byte select
        case (byte_lane_q)
            2'b00: byte_sel = read_data[ 7: 0];
            2'b01: byte_sel = read_data[15: 8];
            2'b10: byte_sel = read_data[23:16];
            2'b11: byte_sel = read_data[31:24];
        endcase

        // Halfword select
        half_sel = byte_lane_q[1] ? read_data[31:16] : read_data[15:0];

        // Final mux
        case (size_q)
            SIZE_BYTE: rdata_next = sign_extend_q ? {{24{byte_sel[7]}},  byte_sel} : {24'h0, byte_sel};
            SIZE_HALF: rdata_next = sign_extend_q ? {{16{half_sel[15]}}, half_sel} : {16'h0, half_sel};
            SIZE_WORD: rdata_next = read_data;
            default:   rdata_next = 32'h0;
        endcase
    end

    // -------------------------------------------------------------------------
    //  Output register (this one CAN have a reset — it's outside the RAM)
    // -------------------------------------------------------------------------
    assign rdata          = rdata_next;
    assign misalign_fault = misalign_q;


endmodule
