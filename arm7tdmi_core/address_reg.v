module address_reg (
    input wire [31:0]   Incrementer,
    input wire [31:0]   ALU,
    input wire [31:0]   PC,
    input wire [31:0]   Rn,

    input wire          CLK,
    //input wire          ABE, // Address Bus Enable (Low => Address Bus goes into high impedance)
    //input wire          ALE, // Address Latch Enable
    input wire [1:0]    Addr_reg_sel,
    input wire          Addr_reg_en,

    output wire [31:0]  A
);

// Address Register Input Selector Params
parameter	Incrementer_bus = 2'b00;
parameter	ALU_bus = 2'b01;
parameter	PC_bus  = 2'b10;
parameter	Rn_bus	= 2'b11;

reg [31:0] address_i = 0;
reg [31:0] address_reg = 0;

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
    end else begin
        address_reg <= address_reg;
    end
end

assign A = address_reg;

endmodule