module multiplier (
    input wire  [31:0]  data_a,
    input wire  [31:0]  data_b,
    input wire          CLK,
    input wire          Multiplier_reg_en,

    output wire [31:0]  result_lo,
    output wire [31:0]  result_hi
);

//assign multi_cycle = (data_a[31:8] == 24'd0 || data_a[31:8] == 24'hFFFFFF) ? 3'd1 : ((data_a[31:16] == 16'd0 || data_a[31:16] == 16'hFFFF) ? 3'd2 : ((data_a[31:24] == 8'd0 || data_a[31:24] == 8'hFF) ? 3'd3 : 3'd4));
//
//reg [31:0] data_a_reg = 0;
//
//
//always @(posedge CLK) begin
//    if (Multiplier_reg_en) begin
//        data_a_reg <= data_a;
//    end else begin
//        data_a_reg <= data_a_reg >> 8;
//    end
//end

reg [63:0] result = 0;

always @(posedge CLK) begin
    if (Multiplier_reg_en) begin    
        result <= data_a * data_b;
    end
end

assign result_lo = result[31:0];
assign result_hi = result[63:32];

endmodule