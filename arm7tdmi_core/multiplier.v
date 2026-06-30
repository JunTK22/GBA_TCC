// =============================================================================
//  multiplier.v
//  Registered 32x32 -> 64-bit multiplier.
//
//  Latches a signed or unsigned product on CLK when `Multiplier_reg_en` is high.
//  `sign_f == 0` zero-extends operands for unsigned multiply; `sign_f == 1`
//  sign-extends operands for signed long multiply variants.
// =============================================================================

module multiplier (
    input wire  [31:0]  data_a,
    input wire  [31:0]  data_b,
    input wire          CLK,
    input wire          Multiplier_reg_en,
    input wire          sign_f,

    output wire [31:0]  result_lo,
    output wire [31:0]  result_hi
);

reg signed [63:0] result = 0;
wire [63:0] a = !sign_f ? {32'b0, data_a} : {{32{data_a[31]}}, data_a};
wire [63:0] b = !sign_f ? {32'b0, data_b} : {{32{data_b[31]}}, data_b};

always @(posedge CLK) begin
    if (Multiplier_reg_en) begin    
        result <= a * b;
    end
end

assign result_lo = result[31:0];
assign result_hi = result[63:32];

endmodule
