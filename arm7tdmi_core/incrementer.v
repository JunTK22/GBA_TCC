// =============================================================================
// ARM7TDMI Address Incrementer Module (32-bit)
// =============================================================================
// 
// Purely combinational next-address helper. With `increment_sel == 0`, it
// advances `pc_in` by the current instruction width (+4 ARM, +2 Thumb). With
// `increment_sel == 1`, it increments or decrements `addr_reg_in` for load/store
// address sequencing; Thumb write-back cycles use the ARM-width step when
// `writeback_en` is asserted.
// =============================================================================

module incrementer (
    input  wire [31:0] addr_reg_in,   // Current PC or address register value
    input  wire [31:0] pc_in,   // Current PC or address register value
    input  wire        increment_sel,
    input  wire        tbit,      // TBIT (Thumb state indicator)
    input  wire        writeback_en,
    input  wire        up_down_f,
    output reg  [31:0] addr_out = 0   // Incremented address (next sequential)
);

    always @(*) begin
        case (increment_sel)
            0: addr_out = pc_in + (tbit ? 32'd2 : 32'd4);
            1: addr_out = up_down_f ? (addr_reg_in + (tbit && ~writeback_en ? 32'd2 : 32'd4))
                                    : (addr_reg_in - (tbit && ~writeback_en ? 32'd2 : 32'd4));
        endcase
    end

endmodule
