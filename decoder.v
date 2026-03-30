module decoder(
	input	[31:0]	Data_i,
	input	[31:0]	PSR,
	input			Rn0_Thumb, // Value stored on bit 0 in Rn. Used to activate or deactivate Thumb instructions on BX instruction
	input			clk,
	input			pipeline_halt,
	input			pipeline_rst,
	input	[3:0]	multi_cycle,
	
	output	reg [31:0]	Data_o,
	
	output	reg [5:0] 	Inst_decoded_o,
	output	reg [3:0]	cond_o,
	output	reg [3:0]	opcode_o,
	output	reg [3:0]	Rn_o, // A bus
	output	reg [3:0]	Rd_o,
	output	reg [3:0]	Rs_o,
	output	reg [3:0]	Rm_o, // B bus
	output	reg [23:0]	Imm_o,
	output	reg	[7:0]	Shift_o,
	output	reg			PSR_Thumb_bit = 0, // Activate or Deactivate Thumb instructions by writing into PSR[5]

	output	wire		cond_valid,

	output	wire		nMREQ,
	output	wire		SEQ,

	output	reg			Wr_Data_reg_en,
	output	reg			Reg_bank_en,
	output	reg			B_shifter_en,
	output	reg			Multiplier_en,	
	output	reg			PSR_en,
	output	reg	[1:0]	Addr_reg_sel = 0,
	output	reg	[1:0]	Bus_A_sel = 0,
	output	reg	[1:0]   Bus_B_sel = 0,

	output reg			Set_condition_f,
	output reg			Imm_Operand_f,
	output reg			Acumulate_f,
	output reg			Mult_Long_f,
	output reg			Sign_f,
	output reg			Byte_Word_f,
	output reg			HW_Byte_f,
	output reg			Load_f,
	output reg			Pre_Pos_Indx_f,
	output reg			Up_Down_f,
	output reg			Write_Back_f,
	output reg			L_PSR_UserMode_f,
	output reg			Link_f,
	output reg			Transf_len_f,
	output reg			Interrupt_f,
	output reg			PSR_sel_f,
	output reg			PSR_flags_only_f,
	output reg			H1_f,
	output reg			H2_f,
	output reg			SP_f,
	output reg			PC_LR_f,
	output reg			Low_High_off_f,
	output reg			Shifter_reg_f
	);

// Address Register Input Selector Params
parameter	PC_bus  = 0;
parameter	ALU_bus = 1;
parameter	Inc_bus = 2;

// A Bus Input Selector Params
parameter	Rn = 0;
parameter	Rs = 1;
parameter	Multiplier  = 2;

// B Bus Input Selector Params
parameter	Rm = 0;
parameter	Immediate  	= 1;
//parameter	Multiplier  = 2;
parameter	Data_reg_in = 3;

// Mem Cycle Types
parameter S = 2'b00;
parameter N = 2'b01;
parameter I = 2'b10;
parameter C = 2'b11;

reg [40:0] cycles_types = 0;
reg set_multi_cycle = 0;
reg [19:0] cycle_count = 0;
wire [1:0] special_flow;
assign special_flow = cond_valid ? cycle_count[1:0] : 2'b00;

assign nMREQ	= cycles_types[1];
assign SEQ		= (cycles_types[1:0] == 2'b00) ? 1'b1 : ((cycles_types[1:0] == 2'b11) ? 1'b1 : 1'b0);

// Arm Instructions
parameter DP 			= 1;
parameter Mult 			= 2;
parameter Mult_L 		= 3;
parameter SD_Swap 		= 4;
parameter BranchX 		= 5;
parameter HW_LS_reg 	= 6;
parameter HW_LS_imm 	= 7;
parameter SD_LS 		= 8;
parameter Undf 			= 9;
parameter BD_LS 		= 10;
parameter Branch 		= 11;
parameter Co_Data_LS 	= 12;
parameter Co_Data_Op 	= 13;
parameter Co_Reg_LS 	= 14;
parameter Interrupt_A	= 15;
parameter MRS			= 36;
parameter MSR			= 37;

// Thumb Instructions
parameter Mv_Shift_Reg	= 16;
parameter Add_Sub		= 17;
parameter Imm_Op 		= 18;
parameter Alu_OP 		= 19;
parameter Hi_op_BranchX = 20;
parameter Pc_r_L	 	= 21;
parameter LS_Reg_Off 	= 22;
parameter LS_SignEx_HW	= 23;
parameter LS_Imm_Off	= 24;
parameter HW_LS_T		= 25;
parameter SP_rel_LS		= 26;
parameter Load_Addr		= 27;
parameter Add_Off_SP 	= 28;
parameter Push_Pop_Reg 	= 29;
parameter Multi_LS 		= 30;
parameter Cond_Branch 	= 31;
parameter Interrupt_T	= 32;
parameter Uncon_Branch 	= 33;
parameter L_Branch_Link	= 34;

parameter NOP			= 35;

reg [5:0] Inst_decoded	= NOP;

reg pipeline_halt_r = 0;
reg pipeline_flush = 0;

wire thumb_state;
assign thumb_state = PSR[5];

assign cond_valid = (cond_o == PSR[31:28] || cond_o == 4'b1110) ? 1'b1 : 1'b0;

reg [31:0] instruct_reg; // Fetched instruction

always @(posedge clk) begin
	Data_o	<= Data_i;
end

always @(posedge clk or posedge pipeline_flush or posedge pipeline_rst) begin // Fetch Register
	instruct_reg <= pipeline_rst ? 0 : (pipeline_flush ? 0 : (pipeline_halt_r ? instruct_reg : (thumb_state ? Data_i[15:0] : Data_i)));
end


wire [3:0] reg_list_ones;
assign reg_list_ones	=	instruct_reg[0]+instruct_reg[1]+instruct_reg[2]+instruct_reg[3]+instruct_reg[4]+instruct_reg[5]+instruct_reg[6]+instruct_reg[7]+instruct_reg[8]+
							instruct_reg[9]+instruct_reg[10]+instruct_reg[11]+instruct_reg[12]+instruct_reg[13]+instruct_reg[14]+instruct_reg[15];

always @(instruct_reg) begin
	// Instruction Decoding
	if (thumb_state == 0) begin
	// Modo ARM
		if (instruct_reg[27:25] == 3'b000 && instruct_reg[4]) begin
			if (instruct_reg[24:22] == 3'b000 && instruct_reg[7] && instruct_reg[6:5] == 2'b00) begin 
				// Multiply e Multiply-Acumulate
				Inst_decoded = Mult;
			end else if(instruct_reg[24:23] == 2'b01 && instruct_reg[7] && instruct_reg[6:5] == 2'b00) begin
				// Multiply e Multiply-Acumulate Long
				Inst_decoded = Mult_L;
			end else if (instruct_reg[24:23] == 2'b10 && instruct_reg[21:20] == 2'b00 && instruct_reg[7] && instruct_reg[6:5] == 2'b00) begin
				// Single Data Swap
				Inst_decoded = SD_Swap;
			end else if (instruct_reg[24:20] == 5'b10010 && !instruct_reg[7] && instruct_reg[6:5] == 2'b00) begin
				// Brand and Exchange
				Inst_decoded = BranchX;
			end else begin
				//Halfword Load/Store
				case (instruct_reg[21])
					1'b0: Inst_decoded = HW_LS_reg; // Register Offset
					1'b1: Inst_decoded = HW_LS_imm; // Immediate Offset
				endcase
			end
		end else if (instruct_reg[27:26] == 2'b00) begin
			//Data Processing
			if (instruct_reg[25:23] == 3'b010 && instruct_reg[21:16] == 6'b001111) begin
				Inst_decoded = MRS;
			end else if (instruct_reg[25:23] == 3'b010 && instruct_reg[21:12] == 10'b1010011111 && instruct_reg[11:4] == 8'b00000000) begin
				Inst_decoded = MSR;
			end else begin
				Inst_decoded = DP;
			end
		end else if (instruct_reg[27:25] ==3'b011 && instruct_reg[4]) begin
			// Undefined
			Inst_decoded = Undf;
		end else if (instruct_reg[27:26] ==2'b01) begin
			// Single Data Load/Store
			Inst_decoded = SD_LS;
		end else if (instruct_reg[27:25] == 3'b100) begin
			// Block Data Load/Store
			Inst_decoded = BD_LS;
		end	else if (instruct_reg[27:25] == 3'b101) begin
			// Branch
			Inst_decoded = Branch;
		end else if (instruct_reg[27:25] == 3'b110) begin
			// Coprocessor Data Load/Store
			Inst_decoded = Co_Data_LS;
		end else if (instruct_reg[27:24] == 4'b1110 && instruct_reg[4]) begin
			// Coprocessor Data Operation
			Inst_decoded = Co_Data_Op;
		end else if (instruct_reg[27:24] == 4'b1110 && instruct_reg[4]) begin
			// Coprocessor Register Load/Store
			Inst_decoded = Co_Reg_LS;
		end else if(instruct_reg[27:24] == 4'b1111) begin
			// Software Interrupt
			Inst_decoded = Interrupt_A;
		end else begin
			Inst_decoded = NOP;
		end
	end else begin
		// Modo Thumb
		if (instruct_reg == 0) begin
			Inst_decoded = NOP;
		end else begin
			case (instruct_reg[15:13])
				3'b000: Inst_decoded = (instruct_reg[12:11] == 2'b11) ? Add_Sub : Mv_Shift_Reg; // Add/Subtract : Move Shifter Register
				3'b001: Inst_decoded = Imm_Op; // Move, compare, add, subtract Immediate
				3'b010:	Inst_decoded = instruct_reg[12] ? (instruct_reg[9] ? LS_SignEx_HW : LS_Reg_Off) // Load/store sign-extended byte/halfword : Load/Store with Register Offset
										: (instruct_reg[11] ? Pc_r_L : (instruct_reg[10] ? Hi_op_BranchX : Alu_OP)); // PC-relative load : Hi Register Operations/Branch Exchange : ALU Operations
				3'b011: Inst_decoded = LS_Imm_Off; // Load/Store with Immediate Offset
				3'b100: Inst_decoded = instruct_reg[12] ? SP_rel_LS : HW_LS_T; // SP-relative Load/Store : Load/Store Halfword
				3'b101: Inst_decoded = instruct_reg[12] ? (instruct_reg[10] ? Push_Pop_Reg : Add_Off_SP) : Load_Addr; // Push/Pop Registers : Add Offset to SP : Load Address
				3'b110: Inst_decoded = (instruct_reg[12:8] == 5'b11111) ? Interrupt_T : (instruct_reg[12] ? Cond_Branch : Multi_LS); // Software Interrupt : Conditional Branch : Multiple Load/Store
				3'b111: Inst_decoded = instruct_reg[12] ? L_Branch_Link : Uncon_Branch; // Long Branch with Link : Unconditional Branch
			endcase
		end
	end
end 

// flags [Set_condition_f, Imm_Operand_f, Acumulate_f, Mult_Long_f, Sign_f, 
//		  Byte_Word_f, HW_Byte_f, Load_f, Pre_Pos_Indx_f, Up_Down_f, Write_Back_f]
always @(posedge clk or posedge pipeline_rst) begin
	if (pipeline_rst) begin
		opcode_o			<= 0;
		Rn_o				<= 0;
		Rd_o				<= 0;
		Rs_o				<= 0;
		Rm_o				<= 0;
		Imm_o				<= 0;
		Shift_o				<= 0;
		Reg_bank_en			<= 0;
		B_shifter_en		<= 0;

		Set_condition_f		<= 0;
		Imm_Operand_f		<= 0;
		Acumulate_f			<= 0;
		Mult_Long_f			<= 0;
		Sign_f				<= 0;
		Byte_Word_f			<= 0;
		HW_Byte_f			<= 0;
		Load_f				<= 0;
		Pre_Pos_Indx_f		<= 0;
		Up_Down_f			<= 0;
		Write_Back_f		<= 0;
		L_PSR_UserMode_f	<= 0;
		Link_f				<= 0;
		Transf_len_f		<= 0;
		Interrupt_f			<= 0;
		PSR_sel_f			<= 0;
		PSR_flags_only_f	<= 0;
	end else if (!pipeline_halt_r && !special_flow[1]) begin
		Inst_decoded_o 	 <= Inst_decoded;

		Set_condition_f	 <= 0;
		Imm_Operand_f	 <= 0;
		Acumulate_f		 <= 0;
		Mult_Long_f		 <= 0;
		Sign_f			 <= 0;
		Byte_Word_f		 <= 0;
		HW_Byte_f		 <= 0;
		Load_f			 <= 0;
		Pre_Pos_Indx_f	 <= 0;
		Up_Down_f		 <= 0;
		Write_Back_f	 <= 0;
		L_PSR_UserMode_f <= 0;
		Link_f			 <= 0;
		Transf_len_f	 <= 0;
		Interrupt_f		 <= 0;
		PSR_sel_f		 <= 0;
		PSR_flags_only_f <= 0;
		H1_f			 <= 0;
		H2_f			 <= 0;
		SP_f			 <= 0;
		PC_LR_f			 <= 0;
		Low_High_off_f	 <= 0;
		Shifter_reg_f	 <= 0;

		Wr_Data_reg_en	<= 0;
		Reg_bank_en		<= 0;
		B_shifter_en	<= 0;
		Multiplier_en	<= 0;
		PSR_en			<= 0;

		Addr_reg_sel <= PC_bus;
		Bus_A_sel <= Rn;
		Bus_B_sel <= Rm;

		cond_o 			 <= thumb_state ? ((Inst_decoded == Cond_Branch) ? instruct_reg[11:8] : 0) : instruct_reg[31:28];
		opcode_o		 <= 0;
		Rn_o			 <= 0;
		Rd_o			 <= 0;
		Rs_o			 <= 0;
		Rm_o			 <= 0;
		Imm_o			 <= 0;
		Shift_o			 <= 0;
//		PSR_Thumb_bit	 <= 0;

		cycle_count 	<= cycle_count >> 1;
		cycles_types	<= cycles_types >> 2;

		case (Inst_decoded)
		// ARM Instructions
			DP: begin
				cycle_count		<= (!instruct_reg[25] && instruct_reg[4]) ? ((instruct_reg[15:12] == 15) ? 4'b1111 : 2'b11) : ((instruct_reg[15:12] == 15) ? 3'b111 : 0);
				cycles_types	<= (!instruct_reg[25] && instruct_reg[4]) ? ((instruct_reg[15:12] == 15) ? {S,S,N,I} : {S,I}) : ((instruct_reg[15:12] == 15) ? {S,S,N} : 0);
				
				Set_condition_f	<= instruct_reg[20];
				Imm_Operand_f	<= instruct_reg[25];
				Shifter_reg_f	<= instruct_reg[4];

				Reg_bank_en		<= 1;
				B_shifter_en	<= 1;

				opcode_o		<= instruct_reg[24:21];
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
				Imm_o			<= instruct_reg[7:0];
				Shift_o			<= instruct_reg[25] ? instruct_reg[11:8] : instruct_reg[11:4];
			end
			MRS: begin
				PSR_sel_f		<= instruct_reg[22];
				
				Reg_bank_en		<= 1;
				PSR_en			<= 1;

				opcode_o		<= 4'b1101;
				Rd_o			<= instruct_reg[15:12];
			end
			MSR: begin
				Imm_Operand_f	<= instruct_reg[25];
				PSR_sel_f		<= instruct_reg[22];
				PSR_flags_only_f<= instruct_reg[16];

				Reg_bank_en		<= 1;
				B_shifter_en	<= 1;
				PSR_en			<= 1;

				opcode_o		<= 4'b1101;
				Rm_o			<= instruct_reg[3:0];
				Imm_o			<= instruct_reg[7:0];
				Shift_o			<= instruct_reg[25] ? instruct_reg[11:8] : instruct_reg[11:4];
			end
			Mult: begin
				cycle_count		<= 2'b11;
				cycles_types	<= I;
				
				opcode_o		<= 4'b1101; // MOV initial mult result do Rd
				Set_condition_f <= instruct_reg[20];
				Acumulate_f		<= instruct_reg[21];
				set_multi_cycle	<= 1;

				// Abus <= Rs_o and Bbus <= multiplier_o (Multiplier receive Rm_o directly)				
				Bus_A_sel <= Rs;
				Bus_B_sel <= Multiplier;
				Reg_bank_en <= 0; // Disables reg bank on first cycle
				Multiplier_en <= 1; // Enables Mult. reg to save Rs on first cycle
				
				Rd_o			<= instruct_reg[19:16];
				Rn_o			<= instruct_reg[15:12];
				Rs_o			<= instruct_reg[11:8]; // Initial value is saved in a register inside Multiplier to calculate instruction cycle time. After one cycle Rs <= Rd (because the multiplier is 8x32)
				Rm_o			<= instruct_reg[3:0]; // If Acumulate_f is High, at the last cycle Abus <= Rn_o, Bbus <= Rm_o and Rm_o <= Rd_o
			end
			Mult_L: begin
				cycle_count		<= 2'b11;
				cycles_types	<= I;
				
				opcode_o		<= 4'b1101; // MOV initial mult result do Rd
				Set_condition_f <= instruct_reg[20];
				Acumulate_f		<= instruct_reg[21];
				Mult_Long_f		<= instruct_reg[23];
				Sign_f			<= instruct_reg[22];
				set_multi_cycle	<= 1;

				// Abus <= Rs_o and Bbus <= multiplier_o (Multiplier receive Rm_o directly)				
				Bus_A_sel <= Rs;
				Bus_B_sel <= Multiplier;
				Reg_bank_en <= 0; // Disables reg bank on first cycle
				Multiplier_en <= 1; // Enables Mult. reg to save Rs on first cycle
				
				Rd_o			<= instruct_reg[19:16];
				Rn_o			<= instruct_reg[15:12];
				Rs_o			<= instruct_reg[11:8];
				Rm_o			<= instruct_reg[3:0];
			end
			SD_Swap: begin
				cycle_count 	<= 4'b1111;
				cycles_types	<= {S,N,N,I};
				
				Byte_Word_f		<= instruct_reg[20];

				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
			end
			BranchX: begin
				cycle_count 	<= 3'b111;
				cycles_types	<= {S,S,N};

				Rd_o			<= instruct_reg[15:12];
				Rn_o			<= instruct_reg[3:0];
			end
			HW_LS_reg: begin
				cycle_count		<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? 5'b11111 : 3'b111) : 2'b11;
				cycles_types	<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? {I,N,N,S,S} : {I,N,S}) : {N,N};
				
				Imm_Operand_f	<= instruct_reg[22];
				Sign_f			<= instruct_reg[6];
				HW_Byte_f		<= instruct_reg[5];
				Load_f			<= instruct_reg[20];
				Pre_Pos_Indx_f	<= instruct_reg[24];
				Up_Down_f		<= instruct_reg[23];
				Write_Back_f	<= instruct_reg[21];
				
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
			end
			HW_LS_imm: begin
				cycle_count		<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? 5'b11111 : 3'b111) : 2'b11;
				cycles_types	<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? {I,N,N,S,S} : {I,N,S}) : {N,N};
				
				Imm_Operand_f	<= instruct_reg[22];
				Sign_f			<= instruct_reg[6];
				HW_Byte_f		<= instruct_reg[5];
				Load_f			<= instruct_reg[20];
				Pre_Pos_Indx_f	<= instruct_reg[24];
				Up_Down_f		<= instruct_reg[23];
				Write_Back_f	<= instruct_reg[21];
				
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Imm_o			<= {instruct_reg[11:8], instruct_reg[3:0]};
			end
			SD_LS: begin
				cycle_count		<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? 5'b11111 : 3'b111) : 2'b11;
				cycles_types	<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? {S,S,N,N,I} : {S,N,I}) : {N,N};
				
				opcode_o		<= 4'b0100; // ADD Rn + Imm (Offset)
				Imm_Operand_f	<= !instruct_reg[25];
				Sign_f			<= instruct_reg[6];
				Byte_Word_f		<= instruct_reg[22];
				HW_Byte_f		<= instruct_reg[5];
				Load_f			<= instruct_reg[20];
				Pre_Pos_Indx_f	<= instruct_reg[24];
				Up_Down_f		<= instruct_reg[23];
				Write_Back_f	<= instruct_reg[21];

				// Add Rn + Offset into Addr register on 1st cycle
				Addr_reg_sel <= ALU_bus;
				Bus_A_sel <= Rn;
				Bus_B_sel <= instruct_reg[25] ? Rm : Immediate;
				B_shifter_en	<= 1;

				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
				Imm_o			<= instruct_reg[11:0];
				Shift_o			<= instruct_reg[11:4];
			end
			Undf: begin
				cycle_count		<= 4'b1111;
				cycles_types	<= {S,S,I,N};

			end
			BD_LS: begin
				cycle_count		<=	(instruct_reg[20] ? (instruct_reg[15] ? 4'b1111 : 4'b0011) : 4'b0001) << reg_list_ones | ((8'b0 | 1'b1) << reg_list_ones)-1'b1;
				cycles_types	<=	instruct_reg[20] ? {{16{S}} >> 2*(4'b1111-reg_list_ones), (instruct_reg[15] ? {S,N,N,I} : {N,I})} : {{15{S}} >> 2*(4'b1111-reg_list_ones), N,N};
				
				Load_f			<= instruct_reg[20];
				Pre_Pos_Indx_f	<= instruct_reg[24];
				Up_Down_f		<= instruct_reg[23];
				Write_Back_f	<= instruct_reg[21];
				L_PSR_UserMode_f<= instruct_reg[22];

				Rn_o			<= instruct_reg[19:16];
				Imm_o			<= instruct_reg[15:0]; // Register List
			end
			Branch: begin
				cycle_count		<= 3'b111;
				cycles_types	<= {S,S,N};

				Link_f			<= instruct_reg[24];
				

				opcode_o		<= 4'b0100; // PC := PC + Imm
				Rn_o			<= 4'b1111;
				Rd_o			<= 4'b1111;
				Imm_o			<= instruct_reg[24:0];
				Shift_o			<= 8'b00010000; // 2 bits Logical shift left
			end
			Co_Data_LS: begin
				Load_f			<= instruct_reg[20];
				Pre_Pos_Indx_f	<= instruct_reg[24];
				Up_Down_f		<= instruct_reg[23];
				Write_Back_f	<= instruct_reg[21];
				Transf_len_f	<= instruct_reg[22];
				
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Imm_o			<= instruct_reg[11:0]; // {CP#, Offset}
			end
			Co_Data_Op: begin

				opcode_o		<= instruct_reg[23:20]; // CD opc
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
				Imm_o			<= instruct_reg[11:5]; // {CP#, CP}
			end
			Co_Reg_LS: begin
				Load_f			<= instruct_reg[20];
				
				opcode_o		<= instruct_reg[23:21]; // CD opc
				Rn_o			<= instruct_reg[19:16];
				Rd_o			<= instruct_reg[15:12];
				Rm_o			<= instruct_reg[3:0];
				Imm_o			<= instruct_reg[11:5]; // {CP#, CP}
			end
			Interrupt_A: begin
				cycle_count 	<= 3'b111;
				cycles_types	<= {S,S,N};

				Interrupt_f		<= 1;
			end
			// Thumb Instructions
			Mv_Shift_Reg: begin
				opcode_o		<= instruct_reg[12:11];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
				Imm_o			<= instruct_reg[10:6];
			end
			Add_Sub: begin
				Imm_Operand_f 	<= instruct_reg[10];

				opcode_o		<= instruct_reg[9];
				Rn_o			<= instruct_reg[8:6];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
				Imm_o			<= instruct_reg[8:6];
			end
			Imm_Op: begin
				opcode_o		<= instruct_reg[12:11];
				Rd_o			<= instruct_reg[10:8];
				Imm_o			<= instruct_reg[7:0];
			end
			Alu_OP: begin
				opcode_o		<= instruct_reg[9:6];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
			end
			Hi_op_BranchX: begin
				H1_f			<= instruct_reg[7];
				H2_f			<= instruct_reg[6];

				opcode_o		<= instruct_reg[9:8];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
			end
			Pc_r_L: begin
				Rd_o			<= instruct_reg[10:8];
				Imm_o			<= instruct_reg[7:0];
			end
			LS_Reg_Off: begin
				Load_f 			<= instruct_reg[11];
				Byte_Word_f 	<= instruct_reg[10];
	
				Rn_o			<= instruct_reg[8:6];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
			end
			LS_SignEx_HW: begin
				Load_f 			<= instruct_reg[11];
				Sign_f			<= instruct_reg[10];
	
				Rn_o			<= instruct_reg[8:6];
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
			end
			LS_Imm_Off: begin
				Load_f 			<= instruct_reg[11];
				Byte_Word_f 	<= instruct_reg[12];
	
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
				Imm_o			<= instruct_reg[10:6];
			end
			HW_LS_T: begin
				Load_f 			<= instruct_reg[11];
	
				Rd_o			<= instruct_reg[2:0];
				Rs_o			<= instruct_reg[5:3];
				Imm_o			<= instruct_reg[10:6];
			end
			SP_rel_LS: begin
				Load_f 			<= instruct_reg[11];
	
				Rd_o			<= instruct_reg[10:8];
				Imm_o			<= instruct_reg[7:0];
			end
			Load_Addr: begin
				Rn_o			<= instruct_reg[11] ? 4'b1101 : 4'b1111;
				Rd_o			<= instruct_reg[10:8];
				Imm_o			<= instruct_reg[7:0];
			end
			Add_Off_SP: begin
				Rd_o			<= 4'b1101;
				Imm_o			<= instruct_reg[7:0];
			end
			Push_Pop_Reg: begin
				Load_f			<= instruct_reg[11];
				PC_LR_f			<= instruct_reg[8];

				Imm_o			<= instruct_reg[7:0];
			end
			Multi_LS: begin
				Load_f			<= instruct_reg[11];

				Rn_o			<= instruct_reg[10:8];
				Imm_o			<= instruct_reg[7:0];
			end
			Cond_Branch: begin
				Rd_o			<= 4'b1111;
				Imm_o			<= instruct_reg[7:0];
			end
			Interrupt_T: begin
				Interrupt_f		<= 1;
			end
			Uncon_Branch: begin
				Rd_o			<= 4'b1111;
				Imm_o			<= instruct_reg[10:0];
			end
			L_Branch_Link: begin
				Low_High_off_f	<= instruct_reg[11];

				Rn_o			<= instruct_reg[1] ? 4'b1101 : 4'b1111;
				Rd_o			<= instruct_reg[1] ? 4'b1111 : 4'b1101;
				Imm_o			<= instruct_reg[10:0];
				Shift_o			<= instruct_reg[1] ? 8'b00001000 : 8'b01100000;
			end
			default: begin
			end
		endcase
	end else if (special_flow[0]) begin
		cycle_count 	<= cycle_count >> 1;
		cycles_types	<= cycles_types >> 2;
		case (Inst_decoded_o)
			DP: begin
				if (Rd_o == 4'b1111) begin
					pipeline_flush <= (cycle_count[3:0] == 4'b0111) ? 1 : 0;
				end else begin
					pipeline_flush <= 0;
				end
			end
			Mult: begin
				if (set_multi_cycle) begin
					cycle_count		<= (Acumulate_f ? 2'b11 : 2'b01) << multi_cycle | ((8'b0 | 1'b1) << multi_cycle)-1'b1;
					cycles_types	<= (multi_cycle == 0) ? (Acumulate_f ? {S,I} : {S}) : {Acumulate_f ? {S,I} : {S}, (multi_cycle == 1) ? {I, I} : ((multi_cycle == 2) ? {I, I, I} : {I, I, I, I})};
					Reg_bank_en = 1;
					Multiplier_en = 0;
					set_multi_cycle <= 0;
				end
				if (!set_multi_cycle) begin
					Rs_o <= Rd_o;
					opcode_o <= 4'b0100;
				end
				if (cycle_count[2:1] == 2'b01 && Acumulate_f && !set_multi_cycle) begin
					Bus_A_sel <= Rn;
					Bus_B_sel <= Rm;
					Rm_o	  <= Rd_o;
				end
			end
			Mult_L: begin
				if (set_multi_cycle) begin
					cycle_count		<= (Acumulate_f ? 3'b111 : 3'b011) << multi_cycle | ((8'b0 | 1'b1) << multi_cycle)-1'b1;
					cycles_types	<= (multi_cycle == 0) ? (Acumulate_f ? {S,I,I} : {S,I}) : {Acumulate_f ? {S,I,I} : {S,I}, (multi_cycle == 1) ? {I} : ((multi_cycle == 2) ? {I, I} : {I, I, I})};
					Reg_bank_en = 1;
					Multiplier_en = 0;
					set_multi_cycle <= 0;
				end
				if (!set_multi_cycle) begin
					Rs_o <= Rd_o;
					opcode_o <= 4'b0100;
				end
				if (cycle_count[2:1] == 2'b01 && Acumulate_f && !set_multi_cycle) begin
					Bus_A_sel <= Rn;
					Bus_B_sel <= Rm;
					Rm_o	  <= Rd_o;
				end
			end
			BranchX: begin
				pipeline_flush	<= cycle_count[2]; // Flush pipeline on first cycle
				PSR_Thumb_bit	<= Rn0_Thumb;
			end
			Branch: begin
				pipeline_flush	<= cycle_count[2]; // Flush pipeline on first cycle
				Link_f			<= 0;
			end
			HW_LS_reg: begin
				if (Rd_o == 4'b1111 && Load_f) begin
					pipeline_flush <= (cycle_count[4:0] == 5'b00111) ? 1 : 0;
				end else begin
					pipeline_flush <= 0;
				end
			end
			HW_LS_imm: begin
				if (Rd_o == 4'b1111 && Load_f) begin
					pipeline_flush <= (cycle_count[4:0] == 5'b00111) ? 1 : 0;
				end else begin
					pipeline_flush <= 0;
				end
			end
			SD_LS: begin
				if (Load_f) begin
					opcode_o <= 1101; // Mov Rd <- Data_reg_in
					Reg_bank_en <= 1;
					B_shifter_en <= 0;					
					Bus_B_sel <= Data_reg_in;
				end else begin
					Bus_B_sel <= Rm;
					Wr_Data_reg_en <= 1;
				end
				if (Rd_o == 4'b1111 && Load_f) begin
					pipeline_flush <= (cycle_count[4:0] == 5'b00111) ? 1 : 0;
				end else begin
					pipeline_flush <= 0;
				end
			end
			default: pipeline_flush <= 0;
		endcase
	end
end

always @(cycle_count) begin
	pipeline_halt_r <= cycle_count[1];
end

//always @(cycle_count or multi_cycle) begin
//	if (special_flow) begin
//		case (Inst_decoded_o)
//			DP: begin
//				if (!Imm_Operand_f && Shifter_reg_f) begin
//					pipeline_halt_r <= (Rd_o == 4'b1111) ? cycle_count[3] : cycle_count[1];
//				end else begin
//					pipeline_halt_r <= 0;
//				end
//			end
//			Mult: begin
//				pipeline_halt_r	<= (multi_cycle[1] | cycle_count[0]);
//			end
//			Mult_L: begin
//				pipeline_halt_r	<= (multi_cycle[1] | cycle_count[0]);
//			end
//			BranchX: begin
//				pipeline_halt_r <= 0; // Pipeline refilled based on new PC
//			end
//			Branch: begin
//				pipeline_halt_r <= 0; // Pipeline refilled based on new PC
//			end
//			HW_LS_reg: begin
//				if (Rd_o == 4'b1111 && Load_f) begin
//					pipeline_halt_r <= cycle_count[3];
//				end else  begin
//					pipeline_halt_r <= cycle_count[1];
//				end
//			end
//			HW_LS_imm: begin
//				if (Rd_o == 4'b1111 && Load_f) begin
//					pipeline_halt_r <= cycle_count[3];
//				end else  begin
//					pipeline_halt_r <= cycle_count[1];
//				end
//			end
//			SD_LS: begin
//				if (Rd_o == 4'b1111 && Load_f) begin
//					pipeline_halt_r <= cycle_count[3];
//				end else  begin
//					pipeline_halt_r <= cycle_count[1];
//				end
//			end
//			default: pipeline_halt_r <= cycle_count[1];
//		endcase
//	end 
//end

endmodule