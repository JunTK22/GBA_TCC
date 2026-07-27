// =============================================================================
//  palette_ram.v
//  1 KiB, single-port Palette RAM with CPU/DMA/PPU arbitration.
//
//  The CPU/DMA port is byte addressed; the PPU port uses 16-bit halfword
//  indices. An active PPU read has priority unless force blank is asserted.
//  A colliding CPU/DMA request holds `ready` low, and a preempted 32-bit access
//  retains its pending halfword until the shared bus retries it.
//
//  Reads are synchronous. CPU/DMA word accesses use two halfword beats, and a
//  GBA byte write replicates its byte into both lanes of the target halfword.
// =============================================================================

`timescale 1ns / 1ps

module palette_ram (
    input  wire        clk,

    input  wire [9:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault,

    input  wire [8:0]  ppu_addr,
    input  wire        ppu_rden,
    output wire [15:0] ppu_rdata,
    input  wire        force_blank
);

    localparam [1:0] SIZE_BYTE = 2'b00;
    localparam [1:0] SIZE_HALF = 2'b01;
    localparam [1:0] SIZE_WORD = 2'b10;

    wire cpu_request = we || rden;
    wire ppu_request = ppu_rden && !force_blank;
    wire cpu_grant = cpu_request && !ppu_request;

    wire misalign_comb =
        (((size == SIZE_HALF) && addr[0])
        || ((size == SIZE_WORD) && |addr[1:0]))
        && cpu_request;

    reg word_high_beat = 1'b0;

    wire cpu_beat_grant = cpu_grant && !misalign_comb;
    wire word_low_grant =
        cpu_beat_grant && (size == SIZE_WORD) && !word_high_beat;
    wire word_high_grant =
        cpu_beat_grant && (size == SIZE_WORD) && word_high_beat;

    always @(posedge clk) begin
        if (word_low_grant)
            word_high_beat <= 1'b1;
        else if (word_high_grant)
            word_high_beat <= 1'b0;
    end

    wire [8:0] cpu_halfword_addr =
        (size == SIZE_WORD)
        ? {addr[9:2], word_high_beat}
        : addr[9:1];
    wire [8:0] mem_addr =
        ppu_request ? ppu_addr : cpu_halfword_addr;

    reg [15:0] cpu_write_data;
    always @(*) begin
        case (size)
            SIZE_BYTE: cpu_write_data = {2{wdata[7:0]}};
            SIZE_HALF: cpu_write_data = wdata[15:0];
            SIZE_WORD: cpu_write_data =
                word_high_beat ? wdata[31:16] : wdata[15:0];
            default:   cpu_write_data = 16'h0000;
        endcase
    end

    wire mem_wren = cpu_beat_grant && we;
    wire mem_rden =
        ppu_request || (cpu_beat_grant && rden);
    wire [15:0] mem_read_data;

    M10K #(
        .WIDTH      (16),
        .DEPTH_POW2 (9),
        .INIT_FILE  ("UNUSED")
    ) palette_mem (
        .addr    (mem_addr),
        .byteena (2'b11),
        .clk     (clk),
        .data    (cpu_write_data),
        .wren    (mem_wren),
        .rden    (mem_rden),
        .q       (mem_read_data)
    );

    // A word-read low half must be saved before a PPU access can replace the
    // single-port RAM output while the CPU/DMA high half remains pending.
    reg        low_capture_pending = 1'b0;
    reg [15:0] word_low_data = 16'h0000;

    always @(posedge clk) begin
        if (low_capture_pending) begin
            word_low_data <= mem_read_data;
            low_capture_pending <= 1'b0;
        end

        if (word_low_grant && rden)
            low_capture_pending <= 1'b1;
    end

    reg [1:0] size_q = SIZE_BYTE;
    reg       byte_lane_q = 1'b0;
    reg       sign_extend_q = 1'b0;
    reg       misalign_q = 1'b0;
    reg       we_q = 1'b0;

    always @(posedge clk) begin
        // Qualify faults only for a CPU/DMA request that actually received
        // the single RAM port. Clear both registers during idle and PPU-only
        // cycles so a completed/aborted alignment fault cannot remain sticky.
        misalign_q <= cpu_grant && misalign_comb;
        we_q <= cpu_grant && we;

        if (cpu_beat_grant) begin
            size_q <= size;
            byte_lane_q <= addr[0];
            sign_extend_q <= sign_extend;
        end
    end

    reg [7:0] byte_sel;
    always @(*) begin
        byte_sel =
            byte_lane_q ? mem_read_data[15:8] : mem_read_data[7:0];

        case (size_q)
            SIZE_BYTE: rdata =
                sign_extend_q ? {{24{byte_sel[7]}}, byte_sel}
                              : {24'h000000, byte_sel};
            SIZE_HALF: rdata =
                sign_extend_q
                ? {{16{mem_read_data[15]}}, mem_read_data}
                : {16'h0000, mem_read_data};
            SIZE_WORD: rdata = {mem_read_data, word_low_data};
            default:   rdata = 32'h00000000;
        endcase
    end

    assign ppu_rdata = mem_read_data;

    // The low word beat inserts the normal 16-bit-bus wait. Any PPU collision
    // inserts another wait without advancing the CPU/DMA beat state.
    assign ready =
        !cpu_request ? 1'b1
      : ppu_request ? 1'b0
      : misalign_comb ? 1'b0
      : (size == SIZE_WORD) ? word_high_beat
      : 1'b1;

    assign misalign_fault = misalign_q && we_q;

endmodule
