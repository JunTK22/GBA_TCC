module seg_display (
    input   wire [31:0] in,
    input   wire clk,

    output  wire [6:0] s0,
    output  wire [6:0] s1,
    output  wire [6:0] s2,
    output  wire [6:0] s3,
    output  wire [6:0] s4,
    output  wire [6:0] s5
);

function reg [6:0] seg;
    input [3:0] hex;
    begin
        case (hex)
            4'h0: seg = 7'b0111111;
            4'h1: seg = 7'b0000110;
            4'h2: seg = 7'b1011011;
            4'h3: seg = 7'b1001111;
            4'h4: seg = 7'b1100110;
            4'h5: seg = 7'b1101101;
            4'h6: seg = 7'b1111101;
            4'h7: seg = 7'b0000111;
            4'h8: seg = 7'b1111111;
            4'h9: seg = 7'b1100111;
            4'ha: seg = 7'b1110111;
            4'hb: seg = 7'b1111100;
            4'hc: seg = 7'b0111001;
            4'hd: seg = 7'b1011110;
            4'he: seg = 7'b1111001;
            4'hf: seg = 7'b1110001;
        endcase
    end
endfunction

reg [31:0] in_r;
always @(posedge clk) begin
    in_r <= in;
end

assign s0 = ~seg(in_r[3:0]);
assign s1 = ~seg(in_r[7:4]);
assign s2 = ~seg(in_r[11:8]);
assign s3 = ~seg(in_r[15:12]);
assign s4 = ~seg(in_r[19:16]);
assign s5 = ~seg(in_r[23:20]);

endmodule