module b_shifter (
    input  wire [31:0]  data_i,
    input  wire [7:0]   Rs_shift_ammount,
    input  wire [7:0]   shift_data,
    input  wire         carry_i,
    input  wire         Imm_Operand_f,
    input  wire         B_shifter_en,

    output wire [31:0]  data_o,
    output wire         carry_o
);


reg [63:-32] result = 0;
wire signed [31:-32] intermediate2;
reg  signed [31:-32] intermediate = 0;
wire [7:0] shift;

assign shift = Imm_Operand_f ? (shift_data[3:0] << 1) : (shift_data[0] ? Rs_shift_ammount : shift_data[7:3]);

assign intermediate2 = {data_i, 32'd0};

always @(*) begin
    result <= 0;
    if (Imm_Operand_f) begin
        // Rotate right
        intermediate <= intermediate2 >> shift;
        result[31:-1] <= {intermediate[-1:-32] | intermediate[31:0], intermediate[-1]};
    end else begin
        case (shift_data[2:1])
            2'b00: begin
                // Logical left
				intermediate <= 0;
                result[63:0] <= data_i << shift;
            end
            2'b01: begin
                // Logical right
                intermediate <= intermediate2 >> shift;
                result[31:-1] <= intermediate[31:-1];
            end
            2'b10: begin
                // Arithmetic right
                intermediate <= intermediate2 >>> shift;
                result[31:-1] <= intermediate[31:-1];
            end
            2'b11: begin
                // Rotate right
                intermediate <= intermediate2 >> shift;
                result[31:-1] <= {intermediate[-1:-32] | intermediate[31:0], intermediate[-1]};
            end
        endcase
    end
end

assign data_o = B_shifter_en ? result[31:0] : data_i;
assign carry_o = Imm_Operand_f ? result[-1] : ((shift_data[2:1] == 2'b00) ? result[32] : result[-1]);

endmodule