module multiplier (
    input wire  [31:0]  data_a,
    input wire  [31:0]  data_b,
    input wire          CLK,
    input wire          Multiplier_reg_en,

    output wire [31:0]  result_lo,
    output wire [31:0]  result_hi
);

reg [63:0] result = 0;

always @(posedge CLK) begin
    if (Multiplier_reg_en) begin    
        result <= data_a * data_b;
    end
end

assign result_lo = result[31:0];
assign result_hi = result[63:32];

endmodule