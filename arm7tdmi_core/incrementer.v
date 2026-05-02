// =============================================================================
// ARM7TDMI Address Incrementer Module (32-bit)
// =============================================================================
// 
// Reference: ARM7TDMI Data Sheet (ARM DDI 0029E)
// - Section 1.4: ARM7TDMI Core Diagram (page 1-5)
//   - "Address Incrementer" block (dedicated 32-bit incrementer)
// - Section 1.3: ARM7TDMI Block Diagram (page 1-4)
// - Section 6.5: Instruction Fetch (sequential addresses)
// - Section 10: Instruction Cycle Operations
//   - PC is incremented by +4 (ARM state) or +2 (THUMB state) every cycle
// - Signal TBIT (Section 2.1, page 2-10): HIGH = THUMB state
// 
// This is the dedicated Address Incrementer used for:
// - Sequential instruction prefetch (PC + 4 or PC + 2)
// - Address generation for the next cycle when SEQ = 1
// 
// It is purely combinational (no clock, no pipeline) to match the ARM7TDMI
// datapath timing. On FPGA this synthesizes to a tiny carry-chain adder
// (constant +2 or +4) — essentially free logic.
// 
// Inputs:
//   addr_in   : 32-bit input address (usually current PC from Address Register)
//   tbit      : TBIT signal (1 = THUMB → +2, 0 = ARM → +4)
// 
// Outputs:
//   addr_out  : addr_in + 4 (ARM) or addr_in + 2 (THUMB)
// =============================================================================

module incrementer (
    input  wire [31:0] addr_reg_in,   // Current PC or address register value
    input  wire [31:0] pc_in,   // Current PC or address register value
    input  wire        increment_sel,      // TBIT (Thumb state indicator)
    input  wire        tbit,      // TBIT (Thumb state indicator)
    input  wire        clk,
    input  wire        up_down_f,
    output reg  [31:0] addr_out = 0   // Incremented address (next sequential)
);

    //always @(negedge clk) begin
    //    addr_out <= (increment_sel ? addr_reg_in : pc_in) + (tbit ? 32'd2 : 32'd4);        
    //end

    always @(*) begin
        case (increment_sel)
            0: addr_out = pc_in + (tbit ? 32'd2 : 32'd4);
            1: addr_out = up_down_f ? (addr_reg_in + (tbit ? 32'd2 : 32'd4)) : (addr_reg_in - (tbit ? 32'd2 : 32'd4));
        endcase
    end

endmodule