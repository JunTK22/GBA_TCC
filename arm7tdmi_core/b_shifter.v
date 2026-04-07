module b_shifter (
    input       [31:0]  data_i,
    input       [7:0]   Rs_shift_ammount,
    input       [7:0]   shift_data,
    input               carry_i,
    input               Imm_Operand_f,
    input               B_shifter_en,

    output wire [31:0]  data_o,
    output reg          carry_o = 0
);


reg [63:-32] result = 0;
reg [31:-32] rot_intermediate = 0;
wire [7:0] shift;

assign shift = Imm_Operand_f ? (shift_data[3:0] << 1) : (shift_data[0] ? Rs_shift_ammount : shift_data[7:3]);

always @(*) begin
    rot_intermediate <= 0;
    result <= 0;
    if (Imm_Operand_f) begin
        rot_intermediate <= data_i >> shift;
        result[31:0] <= rot_intermediate[-1:-32] | rot_intermediate[31:0];
        carry_o <= result[-1];
    end else begin
       case (shift_data[2:1])
            2'b00: begin
                // Logical left
                result[63:0] <= data_i << shift;
                carry_o <= result[32];
            end
            2'b01: begin
                // Logical right
                result[31:-32] <= data_i >> shift;
                carry_o <= result[-1];
            end
            2'b10: begin
                // Arithmetic right
                result[31:-32] <= data_i >>> shift;
                carry_o <= result[-1];
            end
            2'b11: begin
                // Rotate right
                rot_intermediate <= data_i >> shift;
                result[31:0] <= rot_intermediate[-1:-32] | rot_intermediate[31:0];
                carry_o <= result[-1];
            end
            default:;
        endcase
    end
end

assign data_o = B_shifter_en ? result[31:0] : data_i;

endmodule