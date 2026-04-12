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
    input  wire [31:0] addr_in,   // Current PC or address register value
    input  wire        tbit,      // TBIT (Thumb state indicator)
    output reg  [31:0] addr_out   // Incremented address (next sequential)
);

    // Simple constant increment based on processor state
    // Synthesis note: On FPGA this becomes a 32-bit adder with constant operand.
    // Modern tools (Vivado/Quartus) will optimize it to a few LUTs + carry chain.
    always @(*) begin
        addr_out = addr_in + (tbit ? 32'd2 : 32'd4);        
    end

    // Optional: explicit +4 and +2 for even better optimization on some FPGAs
    // wire [31:0] inc_arm  = addr_in + 32'd4;
    // wire [31:0] inc_thumb = addr_in + 32'd2;
    // assign addr_out = tbit ? inc_thumb : inc_arm;

endmodule