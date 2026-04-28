// =============================================================================
// ARM7TDMI ALU Module (32-bit)
// =============================================================================
// 
// Reference: ARM7TDMI Data Sheet (ARM DDI 0029E)
// - Section 1.4: ARM7TDMI Core Diagram (32-bit ALU block)
// - Section 4.5: Data Processing Instructions (pages 4-10 to 4-17)
//   - Table 4-3: ARM Data processing instructions (opcode mapping and actions)
//   - Section 4.5.1: CPSR flags (logical vs arithmetic classification,
//     C/V flag rules, N/Z from result[31] and zero check)
// - THUMB Format 4 ALU operations (Section 5.4) reuse the same ALU hardware
// 
// This module implements the 32-bit ALU for FPGA synthesis.
// It is purely combinational (no clock) to match the ARM7TDMI datapath.
// Barrel-shifter output is pre-applied to op_b; shifter_carry is provided
// separately for logical operations.
//
// Inputs:
//   op_a          : 32-bit operand A (usually from register bank)
//   op_b          : 32-bit operand B (barrel shifter output)
//   alu_opcode    : 4-bit opcode (instruction bits [24:21])
//   cpsr_c        : Current CPSR C flag (used only by ADC/SBC/RSC)
//   shifter_carry : Carry-out from barrel shifter (used by logical ops)
//
// Outputs:
//   result        : 32-bit ALU result
//   n, z, c, v    : NZCV flags (N/Z always from result; C/V depend on op class)
// 
// Synthesis note (FPGA): Uses native + operator for carry chains (good for
// Xilinx/Intel LUTs + carry logic). No multipliers or dividers.
// =============================================================================

module alu (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [3:0]  alu_opcode,   // instr[24:21]
    input  wire        cpsr_c,       // CPSR C flag (for ADC/SBC/RSC)
    input  wire        shifter_carry,// Barrel shifter carry-out
    output reg  [31:0] result,
    output reg         n,            // Negative
    output reg         z,            // Zero
    output reg         c,            // Carry / Borrow
    output reg         v             // Overflow (signed)
);

    // Internal signals for unified adder (arithmetic ops only)
    reg [31:0] effective_a;
    reg [31:0] effective_b;
    reg        adder_cin;
    reg        is_arithmetic;

    always @* begin
        // Default values (safe for synthesis)
        result         = 32'b0;
        n              = 1'b0;
        z              = 1'b0;
        c              = shifter_carry;   // default = shifter carry (logical ops)
        v              = 1'b0;
        is_arithmetic  = 1'b0;
        effective_a    = 32'b0;
        effective_b    = 32'b0;
        adder_cin      = 1'b0;

        case (alu_opcode)
            // =========================================================================
            // Logical operations (Section 4.5.1 - C = shifter_carry, V unchanged)
            // =========================================================================
            4'b0000: result = op_a & op_b;                    // AND
            4'b0001: result = op_a ^ op_b;                    // EOR
            4'b1000: result = op_a & op_b;                    // TST (flags only)
            4'b1001: result = op_a ^ op_b;                    // TEQ (flags only)
            4'b1100: result = op_a | op_b;                    // ORR
            4'b1101: result = op_b;                           // MOV
            4'b1110: result = op_a & ~op_b;                   // BIC
            4'b1111: result = ~op_b;                          // MVN

            // =========================================================================
            // Arithmetic operations (use unified adder, C/V from ALU)
            // =========================================================================
            4'b0010: begin // SUB   op_a - op_b
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = ~op_b;
                adder_cin     = 1'b1;
            end
            4'b0011: begin // RSB   op_b - op_a
                is_arithmetic = 1'b1;
                effective_a   = ~op_a;
                effective_b   = op_b;
                adder_cin     = 1'b1;
            end
            4'b0100: begin // ADD
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = op_b;
                adder_cin     = 1'b0;
            end
            4'b0101: begin // ADC
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = op_b;
                adder_cin     = cpsr_c;
            end
            4'b0110: begin // SBC   op_a - op_b - ~C
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = ~op_b + 32'b1;
                adder_cin     = cpsr_c;
            end
            4'b0111: begin // RSC   op_b - op_a - ~C
                is_arithmetic = 1'b1;
                effective_a   = ~op_a + 32'b1;
                effective_b   = op_b;
                adder_cin     = cpsr_c;
            end
            4'b1010: begin // CMP (SUB, flags only)
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = ~op_b;
                adder_cin     = 1'b1;
            end
            4'b1011: begin // CMN (ADD, flags only)
                is_arithmetic = 1'b1;
                effective_a   = op_a;
                effective_b   = op_b;
                adder_cin     = 1'b0;
            end

            default: result = 32'b0; // unreachable in normal operation
        endcase

        // Perform addition only for arithmetic ops (FPGA carry-chain friendly)
        if (is_arithmetic) begin
            {c, result} = effective_a + effective_b + adder_cin;
        end

        // Common flag logic (Section 4.5.1)
        n = result[31];
        z = (result == 32'b0);

        // V flag (signed overflow) only for arithmetic ops
        // Formula works for all unified-add cases (including ADC/SBC and cin):
        // V = (op_a[31] == effective_b[31]) && (result[31] != op_a[31])
        if (is_arithmetic) begin
            v = (op_a[31] == effective_b[31]) && (result[31] != op_a[31]);
        end
        // For logical ops: V is unchanged by ALU (control logic in CPSR update
        // will preserve old V). We drive v=0 here as a safe default.
    end

endmodule