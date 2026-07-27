// =============================================================================
//  gba_ram_w16_dualport.v
//  16-bit M10K-backed adapter with CPU/DMA and PPU ports.
//
//  Port A accepts byte-addressed 8/16/32-bit CPU or DMA accesses. A 32-bit
//  access uses two halfword beats and holds the active beat if its request is
//  temporarily removed by the VRAM arbiter. `ready` is low for the first word
//  beat and for misaligned halfword/word requests.
//
//  Port B is an independent read-only, halfword-indexed PPU port. Both ports
//  are synchronous to `clk` and have one RAM read cycle of latency.
// =============================================================================

`timescale 1ns / 1ps

module gba_ram_w16_dualport #(
    parameter DEPTH_POW2 = 9,
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire                      clk,

    input  wire [DEPTH_POW2:0]       addr,
    input  wire [31:0]               wdata,
    output reg  [31:0]               rdata,
    input  wire                      we,
    input  wire                      rden,
    input  wire [1:0]                size,
    input  wire                      sign_extend,
    output wire                      ready,
    output reg                       misalign_fault,

    input  wire [DEPTH_POW2-1:0]     ppu_addr,
    input  wire                      ppu_rden,
    output wire [15:0]               ppu_rdata
);

    localparam [1:0] SIZE_BYTE = 2'b00;
    localparam [1:0] SIZE_HALF = 2'b01;
    localparam [1:0] SIZE_WORD = 2'b10;

    wire cpu_request = rden || we;
    wire misalign_comb =
        (((size == SIZE_HALF) && addr[0])
        || ((size == SIZE_WORD) && |addr[1:0]))
        && cpu_request;

    // A blocked request is removed by the VRAM arbiter. Hold the current word
    // beat until that request is presented again.
    reg word_high_beat = 1'b0;
    always @(posedge clk) begin
        if (cpu_request && !misalign_comb) begin
            if (size == SIZE_WORD)
                word_high_beat <= !word_high_beat;
            else
                word_high_beat <= 1'b0;
        end
    end

    wire word_low_stall =
        cpu_request && (size == SIZE_WORD) && !word_high_beat;
    assign ready = !misalign_comb && !word_low_stall;

    wire [DEPTH_POW2-1:0] halfword_addr =
        (size == SIZE_WORD)
        ? {addr[DEPTH_POW2:2], word_high_beat}
        : addr[DEPTH_POW2:1];
    wire byte_lane = addr[0];

    wire [1:0] byteena =
        size == SIZE_BYTE ? (byte_lane ? 2'b10 : 2'b01)
      : size == SIZE_HALF ? 2'b11
      : size == SIZE_WORD ? 2'b11
      : 2'b00;

    reg [15:0] wdata_shifted;
    always @(*) begin
        case (size)
            SIZE_BYTE: wdata_shifted = {2{wdata[7:0]}};
            SIZE_HALF: wdata_shifted = wdata[15:0];
            SIZE_WORD: wdata_shifted =
                word_high_beat ? wdata[31:16] : wdata[15:0];
            default:   wdata_shifted = 16'h0000;
        endcase
    end

    wire [15:0] read_data;
    M10K_dualport #(
        .WIDTH      (16),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) ram_inst (
        .clk       (clk),
        .addr_a    (halfword_addr),
        .byteena_a (byteena),
        .data_a    (wdata_shifted),
        .wren_a    (we && !misalign_comb),
        .rden_a    (rden),
        .q_a       (read_data),
        .addr_b    (ppu_addr),
        .rden_b    (ppu_rden),
        .q_b       (ppu_rdata)
    );

    reg [15:0] read_data_q = 16'h0000;
    reg [1:0]  size_q = SIZE_BYTE;
    reg        byte_lane_q = 1'b0;
    reg        sign_extend_q = 1'b0;
    reg        misalign_q = 1'b0;
    reg        we_q = 1'b0;

    always @(posedge clk) begin
        if (cpu_request) begin
            read_data_q <= read_data;
            size_q <= size;
            byte_lane_q <= byte_lane;
            sign_extend_q <= sign_extend;
            misalign_q <= misalign_comb;
            we_q <= we;
        end
    end

    reg [7:0] byte_sel;
    always @(*) begin
        byte_sel = byte_lane_q ? read_data[15:8] : read_data[7:0];

        case (size_q)
            SIZE_BYTE: rdata =
                sign_extend_q ? {{24{byte_sel[7]}}, byte_sel}
                              : {24'h000000, byte_sel};
            SIZE_HALF: rdata =
                sign_extend_q ? {{16{read_data[15]}}, read_data}
                              : {16'h0000, read_data};
            SIZE_WORD: rdata = {read_data, read_data_q};
            default:   rdata = 32'h00000000;
        endcase

        misalign_fault = misalign_q && we_q;
    end

endmodule
