// =============================================================================
//  arm_m10k_memory.v
//  M10K Block RAM — Byte-Addressed, 32-bit Word, ARM/Thumb Compatible
// =============================================================================
//
//  Description:
//    A single-port synchronous memory module targeting Intel/Altera M10K block
//    RAM primitives.  The interface is byte-addressed with a 32-bit datapath,
//    and supports all three ARM/Thumb transfer sizes:
//
//      size[1:0]  Transfer    Thumb instruction examples
//      ---------  ----------  --------------------------------
//        2'b00    Byte   (8)  LDRB / STRB / LDRSB
//        2'b01    Half  (16)  LDRH / STRH / LDRSH
//        2'b10    Word  (32)  LDR  / STR
//
//    On reads, the selected byte/halfword is right-aligned in rdata and
//    optionally sign-extended when sign_extend is asserted (LDRSB / LDRSH).
//
//    Unaligned accesses (halfword on odd byte, word on non-multiple-of-4)
//    assert misalign_fault for one cycle without modifying memory.
//
//  Parameters:
//    DEPTH_POW2   — log2 of the number of 32-bit words.
//                   Default 8 → 256 words = 1 KB (fits in one M10K).
//
//  Port summary:
//    clk
//    rst_n        — active-low synchronous reset (clears output register only)
//    addr         — byte address; width = DEPTH_POW2 + 2
//    wdata        — write data (32-bit, always right-aligned)
//    rdata        — read data  (32-bit, right-aligned, 1-cycle latency)
//    we           — write enable
//    re           — read  enable
//    size         — transfer size selector (see table above)
//    sign_extend  — 1 = sign-extend byte/halfword reads into 32 bits
//    ready        — combinatorial; always 1 unless misalign_fault
//    misalign_fault — asserted for one cycle on illegal alignment
//
//  Synthesis notes:
//    The (* ramstyle = "M10K" *) attribute targets Quartus Prime.
//    For Vivado, replace with (* ram_style = "block" *).
//    byteena is implemented by reading-then-merging on writes; this matches
//    the M10K byte-enable feature when inferred correctly by Quartus.
//
// =============================================================================

`timescale 1ns / 1ps

module sram #(
    parameter DEPTH_POW2 = 10           // 2^8 = 256 words = 1 KB
)(
    // -------------------------------------------------------------------------
    //  Clock / Reset
    // -------------------------------------------------------------------------
    input  wire                       clk,
    input  wire                       rst_n,          // active-low sync reset

    // -------------------------------------------------------------------------
    //  CPU Interface
    // -------------------------------------------------------------------------
    input  wire [DEPTH_POW2+1 : 0]   addr,           // byte address
    input  wire [31:0]                wdata,          // write data (right-aligned)
    output reg  [31:0]                rdata,          // read  data (right-aligned)
    input  wire                       we,             // write enable
    input  wire [1:0]                 size,           // 00=byte 01=half 10=word
    input  wire                       sign_extend,    // sign-extend on read

    // -------------------------------------------------------------------------
    //  Status
    // -------------------------------------------------------------------------
    output wire                       ready,          // 1 unless fault
    output reg                        misalign_fault  // alignment error flag
);

    // =========================================================================
    //  Local parameters
    // =========================================================================
    localparam DEPTH = 1 << DEPTH_POW2;   // number of 32-bit words

    localparam SIZE_BYTE = 2'b00;
    localparam SIZE_HALF = 2'b01;
    localparam SIZE_WORD = 2'b10;

    // =========================================================================
    //  M10K array declaration
    //  Each entry is 32 bits wide; depth = DEPTH words.
    //  The attribute tells Quartus to use M10K blocks.
    // =========================================================================
    (* ramstyle = "M10K" *)
    reg [31:0] mem [0 : DEPTH-1];

    // =========================================================================
    //  Address decomposition
    //    word_addr  — index into the 32-bit word array
    //    byte_lane  — which byte within the word (little-endian)
    // =========================================================================
    wire [DEPTH_POW2-1:0] word_addr  = addr[DEPTH_POW2+1 : 2];
    wire [1:0]            byte_lane  = addr[1:0];

    // =========================================================================
    //  Alignment check
    //    Halfword: must be 2-byte aligned  (addr[0]   == 0)
    //    Word    : must be 4-byte aligned  (addr[1:0] == 2'b00)
    // =========================================================================
    reg misalign_comb;

    always @(*) begin
        case (size)
            SIZE_BYTE: misalign_comb = 1'b0;
            SIZE_HALF: misalign_comb =  addr[0];          // odd = misaligned
            SIZE_WORD: misalign_comb = |addr[1:0];        // any offset = misaligned
            default:   misalign_comb = 1'b0;
        endcase
    end

    assign ready = ~misalign_comb;

    // =========================================================================
    //  Byte-enable generation
    //    byteena[3] → mem[word][31:24]   (most-significant / "byte 3")
    //    byteena[0] → mem[word][ 7: 0]   (least-significant / "byte 0")
    //  Little-endian layout assumed (consistent with ARM default mapping).
    // =========================================================================
    reg [3:0] byteena;

    always @(*) begin
        case (size)
            SIZE_BYTE: begin
                // Only the addressed byte lane is enabled
                case (byte_lane)
                    2'b00: byteena = 4'b0001;
                    2'b01: byteena = 4'b0010;
                    2'b10: byteena = 4'b0100;
                    2'b11: byteena = 4'b1000;
                endcase
            end
            SIZE_HALF: begin
                // Halfword: two consecutive byte lanes
                // byte_lane[1] selects lower (00/01) or upper (10/11) half
                byteena = addr[1] ? 4'b1100 : 4'b0011;
            end
            SIZE_WORD: byteena = 4'b1111;
            default:   byteena = 4'b0000;
        endcase
    end

    // =========================================================================
    //  Write data alignment
    //    wdata is always right-aligned; we shift it into the correct byte lanes
    //    before merging with the existing word.
    // =========================================================================
    reg  [31:0] wdata_shifted;
    wire [31:0] mem_current;       // current contents of the target word
    reg  [31:0] wdata_merged;

    // Combinatorial read of the target word (used for byte-merge on write)
    assign mem_current = mem[word_addr];

    always @(*) begin
        case (size)
            SIZE_BYTE: begin
                // Replicate the byte into all lanes; byteena masks the rest
                wdata_shifted = {wdata[7:0], wdata[7:0], wdata[7:0], wdata[7:0]};
            end
            SIZE_HALF: begin
                // Place the halfword in the selected half
                if (addr[1])
                    wdata_shifted = {wdata[15:0], 16'h0000};  // upper half
                else
                    wdata_shifted = {16'h0000, wdata[15:0]};  // lower half
            end
            SIZE_WORD: wdata_shifted = wdata;
            default:   wdata_shifted = 32'h0000_0000;
        endcase
    end

    // Merge write data with existing memory using byteena
    always @(*) begin
        wdata_merged[31:24] = byteena[3] ? wdata_shifted[31:24] : mem_current[31:24];
        wdata_merged[23:16] = byteena[2] ? wdata_shifted[23:16] : mem_current[23:16];
        wdata_merged[15: 8] = byteena[1] ? wdata_shifted[15: 8] : mem_current[15: 8];
        wdata_merged[ 7: 0] = byteena[0] ? wdata_shifted[ 7: 0] : mem_current[ 7: 0];
    end

    // =========================================================================
    //  Synchronous Write
    //    Suppressed on misalignment fault.
    // =========================================================================
    always @(posedge clk) begin
        if (we && !misalign_comb)
            mem[word_addr] <= wdata_merged;
    end

    // =========================================================================
    //  Synchronous Read  (1-cycle latency — matches M10K registered output)
    //    Data is extracted from the full 32-bit word, right-aligned, and
    //    optionally sign-extended.
    // =========================================================================
    reg  [31:0] raw_word;
    reg  [15:0] half_selected;
    reg  [ 7:0] byte_selected;

    // Capture on clock edge
    always @(posedge clk) begin
        if (!rst_n) begin
            rdata         <= 32'h0000_0000;
            misalign_fault <= 1'b0;
        end else begin
            misalign_fault <= misalign_comb & we;

            if (!misalign_comb) begin
                raw_word = mem[word_addr];   // blocking: use value immediately below

                case (size)
                    // ----------------------------------------------------------
                    //  Byte read
                    // ----------------------------------------------------------
                    SIZE_BYTE: begin
                        case (byte_lane)
                            2'b00: byte_selected = raw_word[ 7: 0];
                            2'b01: byte_selected = raw_word[15: 8];
                            2'b10: byte_selected = raw_word[23:16];
                            2'b11: byte_selected = raw_word[31:24];
                        endcase
                        if (sign_extend)
                            rdata <= {{24{byte_selected[7]}}, byte_selected};
                        else
                            rdata <= {24'h000000, byte_selected};
                    end

                    // ----------------------------------------------------------
                    //  Halfword read  (Thumb LDRH / LDRSH)
                    // ----------------------------------------------------------
                    SIZE_HALF: begin
                        half_selected = addr[1] ? raw_word[31:16] : raw_word[15:0];
                        if (sign_extend)
                            rdata <= {{16{half_selected[15]}}, half_selected};
                        else
                            rdata <= {16'h0000, half_selected};
                    end

                    // ----------------------------------------------------------
                    //  Word read
                    // ----------------------------------------------------------
                    SIZE_WORD: rdata <= raw_word;

                    default:   rdata <= 32'h0000_0000;
                endcase
            end
        end
    end

endmodule
