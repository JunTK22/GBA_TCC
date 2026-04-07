module address_reg (
    input [31:0]    Incrementer,
    input [31:0]    ALU,
    input [31:0]    PC,
    input [31:0]    Rn,

    input           CLK,
    input           ABE, // Address Bus Enable (Low => Address Bus goes into high impedance)
    input           ALE, // Address Latch Enable
    input [1:0]     Addr_reg_sel,
    input           Addr_reg_en,
    input           Pre_Pos_Inc_f,

    output [31:0] A
);

// Address Register Input Selector Params
parameter	Incrementer_bus = 2'b00;
parameter	ALU_bus = 2'b01;
parameter	PC_bus  = 2'b10;
parameter	Rn_bus	= 2'b11; // Used to feed Addr register Rn directly if necessary during Load/Store instructions

reg [31:0] address_i;
reg [31:0] address_reg;

always @(*) begin
    case (Addr_reg_sel)
        Incrementer_bus: address_i <= Incrementer; 
        ALU_bus: address_i  <= ALU; 
        PC_bus: address_i   <= PC; 
        Rn_bus: address_i   <= Rn; 
    endcase
end

always @(posedge CLK) begin
    if (Addr_reg_en) begin
        address_reg <= address_i;
    end
end

assign A = Pre_Pos_Inc_f ? address_i : address_reg;

endmodule