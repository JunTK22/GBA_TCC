// =============================================================================
// ARM7TDMI Write Data Register Module (32-bit)
// =============================================================================
//
// Latches the core write-data bus when `we` is asserted and emits `nENOUT` low
// during write cycles (`nRW == 1`) so the top-level bus can distinguish memory
// writes from reads. Reset clears the registered write data.
// =============================================================================

module write_data_reg (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [31:0] data_in,

    input  wire        we,
    input  wire        nRW,

    output reg  [31:0] data_out,
    output wire        nENOUT
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            data_out <= 32'h0000_0000;
        end else if (we) begin
            data_out <= data_in;
        end
    end

    assign nENOUT = ~nRW;

endmodule
