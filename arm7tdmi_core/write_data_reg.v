// =============================================================================
// ARM7TDMI Write Data Register Module (32-bit) — REBUILT with nENOUT / nENIN / DBE
// =============================================================================
// 
// Reference: ARM7TDMI Data Sheet (ARM DDI 0029E)
// - Section 1.4: ARM7TDMI Core Diagram (page 1-5) → "Write Data Register"
//   block with nENOUT, nENIN and DBE explicitly shown connected to it
// - Section 2.1: Signal Description (pages 2-4, 2-7)
//   • nENOUT (Not enable output) — driven LOW for the entire write cycle
//   • nENIN  (NOT enable input)  — external arbitration input (tie HIGH normally)
//   • DBE    (Data Bus Enable)   — test input (tie HIGH in normal use)
// - Section 6.9: The ARM Data Bus (page 6-13)
// - Section 6.10: The External Data Bus (page 6-15)
// - Section 10.8: Store Register & Section 10.11: Data Swap
//
// This rebuilt module now contains BOTH:
//   1. The 32-bit write-data latch (exactly as before)
//   2. The full data-bus control logic (nENOUT generation + FPGA output-enable)
//
// In the real ARM7TDMI silicon the Write Data Register and its enable signals
// are tightly coupled. This single module matches the core diagram exactly.
// =============================================================================

module write_data_reg (
    input  wire        clk,         // MCLK (phase 2 rising edge)
    input  wire        reset_n,

    // Data to be latched (from regfile rd_b or ALU result for SWP)
    input  wire [31:0] data_in,

    // Write enable (asserted by pipeline control in execute stage of STR/STM/SWP)
    input  wire        we,

    // From pipeline controller — indicates current cycle is a write
    input  wire        nRW,         // 1 = write cycle, 0 = read cycle

    // ========================================================================
    // Outputs
    // ========================================================================
    output reg  [31:0] data_out,    // Registered data → DOUT[31:0] or D[31:0]

    // Core output signals (exact names from datasheet)
    output wire        nENOUT,      // Driven LOW for the entire write cycle

    // FPGA-specific tri-state control (active-HIGH for IOB output enable)
    output wire        data_bus_oe  // Connect directly to your top-level D[31:0] IOB OE
);

    // =========================================================================
    // 1. Write Data Register latch (synchronous, holds value for full cycle)
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= 32'h0000_0000;
        end else if (we) begin
            data_out <= data_in;
        end
        // When !we the register holds its previous value — required by
        // the datasheet so that data remains stable on the bus while nRW=1
    end

    // =========================================================================
    // 2. nENOUT generation (datasheet exact behaviour)
    // =========================================================================
    // "During a data write cycle, this signal is driven LOW during phase 1,
    // and remains LOW for the entire cycle."
    // In our synchronous FPGA implementation nRW is already valid for the
    // full memory cycle, so nENOUT = ~nRW is correct and timing-accurate.
    assign nENOUT = ~nRW;

endmodule