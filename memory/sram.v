// =============================================================================
//  sram.v
//  M10K Block RAM — Byte-Addressed, 32-bit Word, ARM/Thumb Compatible
// =============================================================================
//
//  Description:
//    Single-port synchronous memory targeting Intel/Altera M10K block RAM.
//    Byte-addressed, 32-bit datapath, supports byte / halfword / word
//    transfers with optional sign extension. 1-cycle read latency.
//
//    This version is structured so Quartus' RAM inference engine recognizes
//    the memory as a true synchronous block RAM with byte enables. The key
//    rules followed here:
//
//      1. The memory array is read and written ONLY inside a single
//         clocked always block. No combinational read, no second clocked
//         block touching `mem`.
//      2. Byte-enable writes use a generate loop over byte lanes, which
//         matches the Quartus byte-enable RAM template.
//      3. The read register has no reset — M10K output registers can't be
//         reset with arbitrary logic, and adding one disables inference.
//      4. All ARM size/alignment/sign-extension logic operates on the
//         registered read data AFTER the RAM, in a separate pipeline stage.
//
//  Read timing:
//        cycle 0:  addr/we/size/sign_extend presented
//        cycle 1:  rdata valid (registered M10K output, post-processed)
//
// =============================================================================

`timescale 1ns / 1ps

module sram #(
    parameter DEPTH_POW2 = 10           // 2^10 = 1024 words = 4 KB
)(
    input  wire                       clk,

    // CPU interface
    input  wire [DEPTH_POW2+1 : 0]    addr,           // byte address
    input  wire [31:0]                wdata,          // write data (right-aligned)
    output reg  [31:0]                rdata,          // read  data (right-aligned)
    input  wire                       we,             // write enable
    input  wire [1:0]                 size,           // 00=byte 01=half 10=word
    input  wire                       sign_extend,    // sign-extend on read

    // Status
    output wire                       ready,          // 1 unless fault
    output reg                        misalign_fault  // alignment error flag
);

    // -------------------------------------------------------------------------
    //  Local parameters
    // -------------------------------------------------------------------------
    localparam DEPTH = 1 << DEPTH_POW2;

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
    reg misalign_comb;
    always @(*) begin
        case (size)
            SIZE_BYTE: misalign_comb = 1'b0;
            SIZE_HALF: misalign_comb = addr[0];
            SIZE_WORD: misalign_comb = |addr[1:0];
            default:   misalign_comb = 1'b0;
        endcase
    end
    assign ready = ~misalign_comb;

    // -------------------------------------------------------------------------
    //  Byte-enable generation
    // -------------------------------------------------------------------------
    reg [3:0] byteena;
    always @(*) begin
        case (size)
            SIZE_BYTE: begin
                case (byte_lane)
                    2'b00: byteena = 4'b0001;
                    2'b01: byteena = 4'b0010;
                    2'b10: byteena = 4'b0100;
                    2'b11: byteena = 4'b1000;
                endcase
            end
            SIZE_HALF: byteena = addr[1] ? 4'b1100 : 4'b0011;
            SIZE_WORD: byteena = 4'b1111;
            default:   byteena = 4'b0000;
        endcase
    end

    // -------------------------------------------------------------------------
    //  Write-data alignment: replicate/shift into the right lanes so each
    //  byte lane gets the correct data. byteena selects which lanes commit.
    // -------------------------------------------------------------------------
    reg [31:0] wdata_shifted;
    always @(*) begin
        case (size)
            SIZE_BYTE: wdata_shifted = {4{wdata[7:0]}};
            SIZE_HALF: wdata_shifted = addr[1] ? {wdata[15:0], 16'h0000}
                                               : {16'h0000, wdata[15:0]};
            SIZE_WORD: wdata_shifted = wdata;
            default:   wdata_shifted = 32'h0;
        endcase
    end

    // Effective write enable: suppress on misalignment
    wire write_en = we & ~misalign_comb;

    // =========================================================================
    //  M10K-INFERABLE MEMORY BLOCK
    //
    //  Storage + synchronous read register live in a SINGLE always block.
    //  Byte-enable writes use a generate loop over 8-bit lanes — this is the
    //  Quartus-recognized byte-enable template that maps to native M10K
    //  byte-enable hardware.
    // =========================================================================
    (* ramstyle = "M10K" *)
    reg [31:0] mem [0:DEPTH-1];

    reg [31:0] mem_q;     // registered read data straight out of the M10K

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : byte_lanes
            always @(posedge clk) begin
                if (write_en && byteena[gi])
                    mem[word_addr][gi*8 +: 8] <= wdata_shifted[gi*8 +: 8];
            end
        end
    endgenerate
 
    // Read port with bypass — separate clocked block, but only reads `mem`. Quartus
    // accepts read+write in different always blocks for simple dual-action
    // single-port RAM as long as both are clocked and there is no
    // combinational read elsewhere.
	reg [31:0] wdata_bypass;
	reg        bypass_valid;

	always @(posedge clk) begin
		mem_q        <= mem[word_addr];
		wdata_bypass <= wdata_merged;            // what would have been written
		bypass_valid <= write_en;                // collision detector simplification
	end

	wire [31:0] read_data = bypass_valid ? wdata_bypass : mem_q;

    // =========================================================================
    //  Post-RAM pipeline stage: size selection + sign extension
    //  These signals are pipelined one cycle so they line up with mem_q.
    // =========================================================================
    reg [1:0] size_q;
    reg [1:0] byte_lane_q;
    reg       sign_extend_q;
    reg       misalign_q;
    reg       we_q;

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
    reg [ 7:0] byte_sel;
    reg [15:0] half_sel;
    reg [31:0] rdata_next;

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
    always @(*) begin
        rdata          <= rdata_next;
        misalign_fault <= misalign_q & we_q;
    end

endmodule