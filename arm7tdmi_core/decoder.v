module decoder(
	input	wire [31:0]	Data_i,
	input	wire [31:0]	PSR,
	input	wire 		Rn0_Thumb, // Value stored on bit 0 in Rn. Used to activate or deactivate Thumb instructions on BX instruction
	input	wire 		CLK,
	input	wire 		pipeline_rst_n,
	//input	wire [3:0]	multi_cycle,

    input  	wire        nIRQ,         // Interrupt requests
    input  	wire        nFIQ,
    input  	wire        ABORT,        // Memory abort input

	// Data coming from memory due to a LDR	
	output	reg [31:0]	Data_o = 0,
	
	output	reg [5:0] 	Inst_decoded_o = 0,
	output	reg [3:0]	cond_o = 0,
	output	reg [3:0]	opcode_o = 0,
	output	reg [3:0]	Rn_o = 0, // A bus
	output	reg [3:0]	Rd_o = 0,
	output	reg [3:0]	Rs_o = 0,
	output	reg [3:0]	Rm_o = 0, // B bus
	output	reg [23:0]	Imm_o = 0,
	output	reg	[7:0]	Shift_o = 0,
	output	reg			PSR_Thumb_bit = 0, // Activate or Deactivate Thumb instructions by writing into PSR[5]

	output	reg			cond_valid = 0,

    // To Write Data Register (for stores)
    output  reg         core_nRW = 0,     // nRW to bus control

    // Memory interface (Section 6 + Section 10)
    output reg  [1:0]  MAS = 0,          // Memory access size (word/half/byte)
    output wire        nMREQ,        // Not memory request
    output wire        SEQ,          // Sequential address
    output reg         nOPC = 0,         // Not opcode fetch
    output reg         nTRANS = 0,       // Not translate (user mode indicator)

	// Enable signal for modules and registers
	output	reg			Addr_reg_en = 1,
	output	reg			Wr_Data_reg_en = 0,
	output	reg			Reg_bank_en = 0,
	output	reg			B_shifter_en = 0,
	output	reg			Multiplier_reg_en = 0,	
	output	reg			PSR_wr_en = 0,
	output	reg			PSR_rd_en = 0,
	output  reg			Writeback_en = 0,
	output  wire		pc_we,

	// Bus Selectors
	output	reg	[1:0]	Addr_reg_sel = 0,
	output	reg	[1:0]	Bus_A_sel = 0,
	output	reg	[2:0]   Bus_B_sel = 0,
	output	reg		    Wr_Data_reg_sel = 0,
	output	reg		    increment_sel = 0,

	// Control flags
	output reg			Set_condition_f = 0,
	output reg			Imm_Operand_f = 0,
	output reg			Acumulate_f = 0,
	output reg			Mult_Long_f = 0,
	output reg			Sign_f = 0,
	output reg			Byte_Word_f = 0,
	output reg			HW_Byte_f = 0,
	output reg			Load_f = 0,
	output reg			Pre_Pos_Indx_f = 0,
	output reg			Pre_Pos_Inc_f = 0,
	output reg			Up_Down_f = 0,
	output reg			Write_Back_f = 0,
	output reg			L_PSR_UserMode_f = 0,
	output reg			Link_f = 0,
	output reg			Transf_len_f = 0,
	output reg			Interrupt_f = 0,
	output reg			PSR_sel_f = 0,
	output reg			PSR_flags_only_f = 0,
	output reg			H1_f = 0,
	output reg			H2_f = 0,
	output reg			SP_f = 0,
	output reg			PC_LR_f = 0,
	output reg			Low_High_off_f = 0,
	output reg			Shifter_reg_f = 0,
	
	output reg [1:0]	data_size = 2'b10
);

// Address Register Input Selector Params
parameter	Incrementer_bus = 2'b00;
parameter	ALU_bus = 2'b01;
parameter	PC_bus  = 2'b10;
parameter	Rn_bus	= 2'b11; // Used to feed Addr register Rn directly if necessary during Load/Store instructions

// A Bus Input Selector Params
parameter	Rn = 2'b00;
parameter	Rs = 2'b01;
parameter	Multiplier  = 2'b10;

// B Bus Input Selector Params
parameter	Rm = 3'b000;
parameter	Immediate  	= 3'b001;
parameter	Multiplier_Lo  = 3'b010;
parameter	Multiplier_Hi  = 3'b011;
parameter	Data_reg_in = 3'b100;

// Write Data Register Selector Params
parameter	Reg_Bank = 1'b0;
parameter	Bus_B = 1'b1;

// Incrementer Input Selector Params
parameter	PC = 1'b0;
parameter	Address_reg = 1'b1;

// Mem Cycle Types
parameter S = 2'b00;
parameter N = 2'b01;
parameter I = 2'b10;
parameter C = 2'b11;

// Opcode Params
parameter AND = 4'b0000
parameter EOR = 4'b0001
parameter SUB = 4'b0010;
parameter RSB = 4'b0011;
parameter ADD = 4'b0100;
parameter ADC = 4'b0101;
parameter SBC = 4'b0110;
parameter RSC = 4'b0111;
parameter TST = 4'b1000;
parameter TEQ = 4'b1001;
parameter CMP = 4'b1010;
parameter CMN = 4'b1011;
parameter ORR = 4'b1100;
parameter MOV = 4'b1101;
parameter BIC = 4'b1110;
parameter MVN = 4'b1111;

// Arm Instructions
parameter DP 			= 6'd1;
parameter Mult 			= 6'd2;
parameter Mult_L 		= 6'd3;
parameter SD_Swap 		= 6'd4;
parameter BranchX 		= 6'd5;
parameter HW_LS 		= 6'd7;
parameter SD_LS 		= 6'd8;
parameter Undf 			= 6'd9;
parameter BD_LS 		= 6'd10;
parameter Branch 		= 6'd11;
parameter Co_Data_LS 	= 6'd12;
parameter Co_Data_Op 	= 6'd13;
parameter Co_Reg_LS 	= 6'd14;
parameter Interrupt_A	= 6'd15;
parameter MRS			= 6'd36;
parameter MSR			= 6'd37;

// Thumb Instructions
parameter Mv_Shift_Reg	= 6'd16;
parameter Add_Sub		= 6'd17;
parameter Imm_Op 		= 6'd18;
parameter Alu_OP 		= 6'd19;
parameter Hi_op_BranchX = 6'd20;
parameter Pc_r_L	 	= 6'd21;
parameter LS_Reg_Off 	= 6'd22;
parameter LS_SignEx_HW	= 6'd23;
parameter LS_Imm_Off	= 6'd24;
parameter HW_LS_T		= 6'd25;
parameter SP_rel_LS		= 6'd26;
parameter Load_Addr		= 6'd27;
parameter Add_Off_SP 	= 6'd28;
parameter Push_Pop_Reg 	= 6'd29;
parameter Multi_LS 		= 6'd30;
parameter Cond_Branch 	= 6'd31;
parameter Interrupt_T	= 6'd32;
parameter Uncon_Branch 	= 6'd33;
parameter L_Branch_Link	= 6'd34;

parameter NOP			= 6'd35;

reg [5:0] Inst_decoded	= NOP;

reg [31:0] instruct_reg = 0; // Fetched instruction
reg [31:0] instruct_dec = 0; // Decoded instruction register

reg [63:0] register_list = 0; // Register list for Block Load/Store

reg [11:0] cycles_types = 0;
reg [19:0] cycle_count = 0;
reg set_multi_cycle = 0;

reg pipeline_halt_r = 0;
reg wait_f = 0;

wire [1:0] special_flow;
wire [4:0] reg_list_ones;

assign reg_list_ones	=	instruct_reg[0]+instruct_reg[1]+instruct_reg[2]+instruct_reg[3]+instruct_reg[4]+instruct_reg[5]+instruct_reg[6]+instruct_reg[7]+instruct_reg[8]+
							instruct_reg[9]+instruct_reg[10]+instruct_reg[11]+instruct_reg[12]+instruct_reg[13]+instruct_reg[14]+instruct_reg[15];

assign special_flow = cycle_count[1:0];

assign nMREQ	= cycles_types[1];
assign SEQ		= (cycles_types[1:0] == 2'b00) ? 1'b1 : ((cycles_types[1:0] == 2'b11) ? 1'b1 : 1'b0);

wire thumb_state;
assign thumb_state = PSR[5];
wire [3:0] cond = thumb_state ? 4'b1110 : instruct_reg[31:28]; // THUMB always unconditional

always @* begin
    case (cond)
        4'b0000: cond_valid <=  PSR[30];           // EQ  Z==1
        4'b0001: cond_valid <= ~PSR[30];           // NE  Z==0
        4'b0010: cond_valid <=  PSR[29];           // CS  C==1
        4'b0011: cond_valid <= ~PSR[29];           // CC  C==0
        4'b0100: cond_valid <=  PSR[31];           // MI  N==1
        4'b0101: cond_valid <= ~PSR[31];           // PL  N==0
        4'b0110: cond_valid <=  PSR[28];           // VS  V==1
        4'b0111: cond_valid <= ~PSR[28];           // VC  V==0
        4'b1000: cond_valid <=  PSR[29] &  PSR[30]; // HI  C==1 & Z==0
        4'b1001: cond_valid <= ~PSR[29] |  PSR[30]; // LS  C==0 | Z==1
        4'b1010: cond_valid <= (PSR[31] == PSR[28]);// GE
        4'b1011: cond_valid <= (PSR[31] != PSR[28]);// LT
        4'b1100: cond_valid <= ~PSR[30] & (PSR[31] == PSR[28]); // GT
        4'b1101: cond_valid <=  PSR[30] | (PSR[31] != PSR[28]); // LE
        4'b1110: cond_valid <= 1'b1;                // AL
        4'b1111: cond_valid <= 1'b0;                // NV (never)
        default: cond_valid <= 1'b0;
    endcase
end

always @(posedge CLK) begin
	Data_o	<= Data_i;
end

always @(posedge CLK or negedge pipeline_rst_n) begin // Fetch Register
	// Instruction hE1A00000 -> MOV R0, R0 (NOP)
	instruct_reg <= !pipeline_rst_n ? 32'hE1A00000 : (pipeline_halt_r ? instruct_reg : (thumb_state ? Data_i[15:0] : Data_i));
end

//always @(posedge CLK or posedge pipeline_flush_t or posedge pipeline_rst) begin // Fetch Register
//	// Instruction hE1A00000 -> MOV R0, R0 (NOP)
//	instruct_reg <= pipeline_rst ? 32'hE1A00000 : (pipeline_flush_t ? 32'hE1A00000 : (pipeline_halt_r ? instruct_reg : (thumb_state ? Data_i[15:0] : Data_i)));
//end

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
				Inst_decoded = HW_LS;
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

always @(posedge CLK or negedge pipeline_rst_n) begin
	if (!pipeline_rst_n) begin
		Inst_decoded_o	<= 0;
		instruct_dec	<= 0;

		Set_condition_f	 <= 0;
		Imm_Operand_f	 <= 0;
		Acumulate_f		 <= 0;
		Mult_Long_f		 <= 0;
		Sign_f			 <= 0;
		Byte_Word_f		 <= 0;
		HW_Byte_f		 <= 0;
		Load_f			 <= 0;
		Pre_Pos_Indx_f	 <= 0;
		Pre_Pos_Inc_f	 <= 0;
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
		Writeback_en	 <= 0;
		wait_f			 <= 0;
		data_size		 <= 2'b10;

		Wr_Data_reg_en	<= 0;
		Reg_bank_en		<= 0;
		B_shifter_en	<= 0;
		Multiplier_reg_en	<= 0;
		PSR_wr_en			<= 0;
		PSR_rd_en			<= 0;

		core_nRW <= 0;

		Addr_reg_sel <= Incrementer_bus;
		Bus_A_sel <= Rn;
		Bus_B_sel <= Rm;
		Wr_Data_reg_sel <= Reg_Bank;
		increment_sel   <= PC;

		cond_o 			 <= 0;
		opcode_o		 <= MOV;
		Rn_o			 <= 0;
		Rd_o			 <= 0;
		Rs_o			 <= 0;
		Rm_o			 <= 0;
		Imm_o			 <= 0;
		Shift_o			 <= 0;
		register_list	 <= 0;

		cycle_count 	<= 0;
		cycles_types	<= 0;
	end else if (!pipeline_halt_r && !special_flow[1]) begin
		Inst_decoded_o	<= Inst_decoded;
		instruct_dec	<= instruct_reg;

		Set_condition_f	 <= 0;
		Imm_Operand_f	 <= 0;
		Acumulate_f		 <= 0;
		Mult_Long_f		 <= 0;
		Sign_f			 <= 0;
		Byte_Word_f		 <= 0;
		HW_Byte_f		 <= 0;
		Load_f			 <= 0;
		Pre_Pos_Indx_f	 <= 0;
		Pre_Pos_Inc_f	 <= 0;
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
		Writeback_en	 <= 0;
		wait_f			 <= 0;
		data_size		 <= 2'b10;

		Wr_Data_reg_en	<= 0;
		Reg_bank_en		<= 0;
		B_shifter_en	<= 0;
		Multiplier_reg_en	<= 0;
		PSR_wr_en			<= 0;
		PSR_rd_en			<= 0;

		core_nRW <= 0;

		Addr_reg_sel <= Incrementer_bus;
		Bus_A_sel <= Rn;
		Bus_B_sel <= Rm;
		Wr_Data_reg_sel <= Reg_Bank;
		increment_sel <= PC;

		cond_o 			 <= thumb_state ? ((Inst_decoded == Cond_Branch) ? instruct_reg[11:8] : 4'b0000) : instruct_reg[31:28];
		opcode_o		 <= MOV;
		Rn_o			 <= 0;
		Rd_o			 <= 0;
		Rs_o			 <= 0;
		Rm_o			 <= 0;
		Imm_o			 <= 0;
		Shift_o			 <= 0;
		register_list	 <= 0;
//		PSR_Thumb_bit	 <= 0;

		cycle_count 	<= cycle_count >> 1;
		cycles_types	<= cycles_types >> 2;

		if (cond_valid) begin
			case (Inst_decoded)
			// ARM Instructions
				DP: begin
					cycle_count		<= (!instruct_reg[25] && instruct_reg[4]) ? ((instruct_reg[15:12] == 15) ? 4'b1111 : 2'b11) : ((instruct_reg[15:12] == 15) ? 3'b111 : 1'b0);
					cycles_types	<= (!instruct_reg[25] && instruct_reg[4]) ? ((instruct_reg[15:12] == 15) ? {S,S,N,I} : {S,I}) : ((instruct_reg[15:12] == 15) ? {S,S,N} : 1'b0);
					
					Set_condition_f	<= instruct_reg[20];
					Imm_Operand_f	<= instruct_reg[25];
					Shifter_reg_f	<= instruct_reg[4];
	
					Reg_bank_en		<= (instruct_reg[24:21] == 4'b1000 || instruct_reg[24:21] == 4'b1001 || instruct_reg[24:21] == 4'b1010 || instruct_reg[24:21] == 4'b1011) ? 0 : 1;
					B_shifter_en	<= 1;
					Bus_B_sel		<= instruct_reg[25] ? Immediate : Rm;
	
					opcode_o		<= instruct_reg[24:21];
					Rn_o			<= instruct_reg[19:16];
					Rd_o			<= instruct_reg[15:12];
					Rs_o			<= instruct_reg[11:8];
					Rm_o			<= instruct_reg[3:0];
					Imm_o			<= instruct_reg[7:0];
					Shift_o			<= instruct_reg[25] ? instruct_reg[11:8] : instruct_reg[11:4];
				end
				MRS: begin
					PSR_sel_f		<= instruct_reg[22];
					
					Reg_bank_en		<= 1;
					PSR_rd_en		<= 1; // Rm <= PSR
	
					opcode_o		<= MOV;
					Rd_o			<= instruct_reg[15:12];
				end
				MSR: begin
					Imm_Operand_f	<= instruct_reg[25];
					PSR_sel_f		<= instruct_reg[22];
					PSR_flags_only_f<= instruct_reg[16];
	
					B_shifter_en	<= 1;
					PSR_wr_en		<= 1;
	
					opcode_o		<= MOV;
					Rm_o			<= instruct_reg[3:0];
					Imm_o			<= instruct_reg[7:0];
					Shift_o			<= instruct_reg[25] ? instruct_reg[11:8] : instruct_reg[11:4];
				end
				Mult: begin
					cycle_count		<= 2'b11;
					cycles_types	<= {S,I};

					opcode_o		<= MOV; // MOV initial mult result do Rd
					Set_condition_f <= instruct_reg[20];
					Acumulate_f		<= instruct_reg[21];

					// Abus <= Rs_o and Bbus <= multiplier_o (Rm_o goes to Multiplier directly)				
					Bus_A_sel <= Rs;
					Bus_B_sel <= Multiplier_Lo;
					Reg_bank_en <= 0;
					Multiplier_reg_en <= 1;

					Rd_o			<= instruct_reg[19:16];
					Rn_o			<= instruct_reg[15:12];
					Rs_o			<= instruct_reg[11:8];
					Rm_o			<= instruct_reg[3:0];
				end
				Mult_L: begin
					cycle_count		<= 3'b111;
					cycles_types	<= {S,I,I};

					opcode_o		<= MOV; // MOV initial mult result do Rd
					Set_condition_f <= instruct_reg[20];
					Acumulate_f		<= instruct_reg[21];
					Mult_Long_f		<= instruct_reg[23];
					Sign_f			<= instruct_reg[22];
					set_multi_cycle	<= 1;

					// Abus <= Rs_o and Bbus <= multiplier_o (Multiplier receive Rm_o directly)				
					Bus_A_sel <= Rs;
					Bus_B_sel <= Multiplier_Lo;
					Reg_bank_en <= 0;
					Multiplier_reg_en <= 1;

					Rd_o			<= instruct_reg[15:12];
					Rn_o			<= instruct_reg[15:12];
					Rs_o			<= instruct_reg[11:8];
					Rm_o			<= instruct_reg[3:0];
				end
				SD_Swap: begin
					cycle_count 	<= 4'b1111;
					cycles_types	<= {S,N,N,I};

					opcode_o		<= MOV;
					Byte_Word_f		<= instruct_reg[20];
					data_size		<= instruct_reg[20] ? 2'b00 : 2'b10;

					Wr_Data_reg_en	<= 1'b1;
					Addr_reg_sel	<= Rn_bus; // Addr_reg receives RN to read mem
					Bus_B_sel 		<= Rm;
					Wr_Data_reg_sel <= Bus_B;

					Rn_o			<= instruct_reg[19:16];
					Rd_o			<= instruct_reg[15:12];
					Rm_o			<= instruct_reg[3:0];
				end
				BranchX: begin
					cycle_count 	<= 3'b111;
					cycles_types	<= {S,S,N};

					opcode_o		<= MOV; // MOV Rd, Rn
					Reg_bank_en		<= 1;
					Addr_reg_sel	<= ALU_bus; // Load the Addr with new PC

					Rd_o			<= 4'b1111;
					Rm_o			<= instruct_reg[3:0];
				end
				HW_LS: begin
					cycle_count		<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? 5'b11111 : 3'b111) : 2'b11;
					cycles_types	<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? {S,S,N,N,I} : {S,N,I}) : {N,N};

					opcode_o		<= instruct_reg[23] ? ADD : SUB; // Rn +- Imm (Offset)
					Sign_f			<= instruct_reg[6];
					HW_Byte_f		<= instruct_reg[5];
					Load_f			<= instruct_reg[20];
					Pre_Pos_Indx_f	<= instruct_reg[24];
					Up_Down_f		<= instruct_reg[23];
					Write_Back_f	<= instruct_reg[21];
					data_size		<= instruct_reg[5] ? 2'b01 : 2'b00;

					// Add/Sub Rn +- Offset into Addr register if pre indexing. The sum is always written into a Writeback_reg.
					// If post indexing, Addr register receives Rn through PC_bus
					Wr_Data_reg_en	<= instruct_reg[20] ? 1'b0 : 1'b1;
					Addr_reg_sel	<= instruct_reg[24] ? ALU_bus : Rn_bus; // Addr_reg, if post indexing, receives Rn
					Bus_A_sel 		<= Rn;
					Bus_B_sel 		<= instruct_reg[22] ? Immediate : Rm;

					Rn_o			<= instruct_reg[19:16];
					Rd_o			<= instruct_reg[15:12];
					Rs_o			<= instruct_reg[15:12];
					Rm_o			<= instruct_reg[3:0];
					Imm_o			<= {instruct_reg[11:8], instruct_reg[3:0]};
				end
				SD_LS: begin
					cycle_count		<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? 5'b11111 : 3'b111) : 2'b11;
					cycles_types	<= instruct_reg[20] ? ((instruct_reg[15:12] == 15) ? {S,S,N,N,I} : {S,N,I}) : {N,N};

					opcode_o		<= instruct_reg[23] ? ADD : SUB; // Rn +- Imm (Offset)
					Imm_Operand_f	<= !instruct_reg[25];
					Byte_Word_f		<= instruct_reg[22];
					Load_f			<= instruct_reg[20];
					Pre_Pos_Indx_f	<= instruct_reg[24];
					Up_Down_f		<= instruct_reg[23];
					Write_Back_f	<= instruct_reg[21];
					data_size		<= instruct_reg[22] ? 2'b00 : 2'b10;

					// Add/Sub Rn +- Offset into Addr register if pre indexing. The sum is always written into a Writeback_reg.
					// If post indexing, Addr register receives Rn through PC_bus
					Wr_Data_reg_en	<= instruct_reg[20] ? 1'b0 : 1'b1;
					B_shifter_en 	<= instruct_reg[25] ? 1'b1 : 1'b0;
					Addr_reg_sel	<= instruct_reg[24] ? ALU_bus : Rn_bus; // Addr_reg, if post indexing, receives Rn
					Bus_A_sel 		<= Rn;
					Bus_B_sel 		<= instruct_reg[25] ? Rm : Immediate;

					Rn_o			<= instruct_reg[19:16];
					Rd_o			<= instruct_reg[15:12];
					Rs_o			<= instruct_reg[15:12];
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
					cycles_types	<=	instruct_reg[20] ? (instruct_reg[15] ? {S,N,N,I} : {N,I}) : {N,N};

					opcode_o		<= instruct_reg[23] ? ADD : SUB; // Rn +- Imm (Offset)
					Load_f			<= instruct_reg[20];
					Pre_Pos_Inc_f	<= instruct_reg[24];
					Up_Down_f		<= instruct_reg[23];
					Write_Back_f	<= instruct_reg[21];
					L_PSR_UserMode_f<= instruct_reg[22];
					wait_f			<= 1;

					Addr_reg_sel <= Rn_bus;

					Rn_o			<= instruct_reg[19:16];
					register_list	<= i0;
				end
				Branch: begin
					cycle_count		<= 3'b111;
					cycles_types	<= {S,S,N};

					Link_f			<= instruct_reg[24];

					opcode_o		<= ADD; // PC := PC + Imm
					Reg_bank_en		<= 1;
					B_shifter_en	<= 1;
					Bus_B_sel		<= Immediate;
					Addr_reg_sel	<= ALU_bus;

					Rn_o			<= 4'b1111;
					Rd_o			<= 4'b1111;
					Imm_o			<= instruct_reg[23:0];
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
					Reg_bank_en  	<= 1;
					B_shifter_en 	<= 1;

					opcode_o		<= MOV; // MOV
					Rd_o			<= instruct_reg[2:0];
					Rm_o			<= instruct_reg[5:3]; // Rs in datasheet
					Shift_o			<= {instruct_reg[10:6], instruct_reg[12:11], 1'b0}; // {Offset, shift type, shift immediate sel}
				end
				Add_Sub: begin
					Imm_Operand_f 	<= instruct_reg[10];

					Reg_bank_en  	<= 1;
					Bus_B_sel 		<= instruct_reg[10] ? Immediate : Rm;

					opcode_o		<= instruct_reg[9] ? SUB : ADD; // SUB : ADD
					Rd_o			<= instruct_reg[2:0];
					Rn_o			<= instruct_reg[5:3]; // Rs in datasheet
					Rm_o			<= instruct_reg[8:6]; // Rn in datasheet
					Imm_o			<= instruct_reg[8:6];
				end
				Imm_Op: begin
					case (instruct_reg[12:11])
						'b00: opcode_o <= MOV; // MOV
						'b01: opcode_o <= CMP; // CMP
						'b10: opcode_o <= ADD; // ADD
						'b11: opcode_o <= SUB; // SUB
					endcase

					Reg_bank_en  	<= 1;
					Bus_B_sel 		<= Immediate;

					Rd_o			<= instruct_reg[10:8];
					Rn_o			<= instruct_reg[10:8]; // Rs in datasheet
					Imm_o			<= instruct_reg[7:0];
				end
				Alu_OP: begin
					Reg_bank_en <= 1;
					case (instruct_reg[9:6])
						'd0: opcode_o <= AND;
						'd1: opcode_o <= EOR;
						'd2: begin // LSL
							opcode_o 	 <= MOV;
							B_shifter_en <= 1;
							Rs_o	 	 <= instruct_reg[5:3];
							Shift_o		 <= {5{0}, 2'b00, 1'b1}; // {Offset, shift type, shift immediate sel}
						end
						'd3: begin // LSR
							opcode_o 	 <= MOV;
							B_shifter_en <= 1;
							Rs_o	 	 <= instruct_reg[5:3];
							Shift_o		 <= {5{0}, 2'b01, 1'b1}; // {Offset, shift type, shift immediate sel}
						end
						'd4: begin // ASR
							opcode_o 	 <= MOV;
							B_shifter_en <= 1;
							Rs_o	 	 <= instruct_reg[5:3];
							Shift_o		 <= {5{0}, 2'b10, 1'b1}; // {Offset, shift type, shift immediate sel}
						end
						'd5: opcode_o <= ADC;
						'd6: opcode_o <= SBC;
						'd7: begin // ROR
							opcode_o 	 <= MOV;
							B_shifter_en <= 1;
							Rs_o	 	 <= instruct_reg[5:3];
							Shift_o		 <= {5{0}, 2'b11, 1'b1}; // {Offset, shift type, shift immediate sel}
						end
						'd8: opcode_o <= TST;
						'd9: opcode_o <= RSB;
						'd10: opcode_o <= CMP;
						'd11: opcode_o <= CMN;
						'd12: opcode_o <= ORR;
						'd13: begin // Multiplication
							cycle_count		<= 2'b11;
							cycles_types	<= {S,I};
						
							opcode_o 		<= MOV;
							Bus_A_sel 		<= Rn;
							Bus_B_sel 		<= Multiplier_Lo;
							Multiplier_reg_en <= 1;
							Reg_bank_en 	<= 0;
						end
						'd14: opcode_o <= BIC;
						'd15: opcode_o <= MVN;
					endcase
										
					Rd_o			<= instruct_reg[2:0];
					Rm_o			<= instruct_reg[2:0];
					Rn_o			<= instruct_reg[5:3];
				end
				Hi_op_BranchX: begin
					case (instruct_reg[9:8])
						2'b00: opcode_o <= ADD;
						2'b01: opcode_o <= CMP;
						2'b10: opcode_o <= MOV;
						2'b11: begin							
							cycle_count 	<= 3'b111;
							cycles_types	<= {S,S,N};
							
							opcode_o 		<= MOV;
							Addr_reg_sel	<= ALU_bus; // Load the Addr with new PC
							
							Rd_o 			<= 4'b1111;
						end
					endcase
				
					H1_f			<= instruct_reg[7];
					H2_f			<= instruct_reg[6];
					
					Reg_bank_en 	<= 1;

					Rd_o			<= instruct_reg[7] ? instruct_reg[2:0]+'d8 : instruct_reg[2:0]; // Hd/Rd
					Rn_o			<= instruct_reg[7] ? instruct_reg[2:0]+'d8 : instruct_reg[2:0]; // Hd/Rd in datasheet
					Rm_o			<= instruct_reg[6] ? instruct_reg[5:3]+'d8 : instruct_reg[5:3]; // Hs/Rs in datasheet
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
		end
		
	end else if (special_flow[0]) begin
		cycle_count 	<= cycle_count >> 1;
		cycles_types	<= cycles_types >> 2;
		case (Inst_decoded_o)
			DP: begin
				if (Rd_o == 4'b1111) begin
					if (cycle_count[3:0] == 4'b0111) begin
						Reg_bank_en <= 0;
					end
				end
			end
			Mult: begin
				Multiplier_reg_en <= 0;
				Reg_bank_en <= 1;
				if (Acumulate_f) begin
					opcode_o <= ADD; // ADD Multi Result + Rn
					Bus_A_sel <= Rn;
				end
			end
			Mult_L: begin
				Multiplier_reg_en <= 0;
				Reg_bank_en <= 1;
				if (Acumulate_f) begin
					opcode_o <= ADD; // ADD Multi Result + Rn
					Bus_A_sel <= Rn;
				end
				if (cycle_count[2:1] == 2'b01) begin
					Bus_B_sel <= Multiplier_Hi;
					Rd_o <= instruct_dec[19:16];
					Rn_o <= instruct_dec[19:16];
				end
			end
			SD_Swap: begin
				Wr_Data_reg_en	<= 1'b0;
				Reg_bank_en <= (cycle_count[2:1] == 2'b01) ? 1'b1 : 1'b0;

				Addr_reg_sel <= Incrementer_bus;
				core_nRW <= (cycle_count[3:2] == 2'b01) ? 1'b1 : 1'b0;
			end
			BranchX: begin
				Reg_bank_en		<= 0;
				PSR_Thumb_bit	<= Rn0_Thumb;
			end
			Branch: begin
				Reg_bank_en		<= 0;
				B_shifter_en	<= 0;
				Link_f			<= 0;
			end
			HW_LS: begin
				Writeback_en <= Pre_Pos_Indx_f ? (Write_Back_f ? 1'b1 : 1'b0) : 1'b1;
				if (Rd_o == 4'b1111 && Load_f) begin
					case (cycle_count[4:0])
						5'b01111: begin
							opcode_o <= MOV; // Mov Rd <- Data_reg_in
							Reg_bank_en <= 1;
							Writeback_en <= 0;
							B_shifter_en <= 0;					
							Bus_B_sel <= Data_reg_in;
						end
						5'b00111: begin
							// Load pipeline with new instructions after branch
							Reg_bank_en <= 0;
							Writeback_en <= 0;
							Addr_reg_sel <= PC_bus;
						end
						5'b00011: begin
							Writeback_en <= 0;
							Addr_reg_sel <= Incrementer_bus;
						end
						default: begin
						end
					endcase
				end else if (Load_f && cycle_count[2:1] == 2'b01) begin
					opcode_o <= MOV; // Mov Rd <- Data_reg_in
					Reg_bank_en <= 1;
					Writeback_en <= 0;
					B_shifter_en <= 0;
					Addr_reg_sel <= Incrementer_bus;
					Bus_B_sel <= Data_reg_in;
				end else if (~Load_f) begin
					core_nRW <= 1;
					Writeback_en <= 0;
					Addr_reg_sel <= Incrementer_bus;
				end
			end
			SD_LS: begin
				Writeback_en <= Pre_Pos_Indx_f ? (Write_Back_f ? 1'b1 : 1'b0) : 1'b1;
				if (Rd_o == 4'b1111 && Load_f) begin
					case (cycle_count[4:0])
						5'b01111: begin
							opcode_o <= MOV; // Mov Rd <- Data_reg_in
							Writeback_en <= 0;
							Reg_bank_en  <= 1;
							B_shifter_en <= 0;					
							Bus_B_sel <= Data_reg_in;
						end
						5'b00111: begin
							// Load pipeline with new instructions after branch
							Reg_bank_en  <= 0;
							Writeback_en <= 0;
							Addr_reg_sel <= PC_bus;
						end
						5'b00011: begin
							Writeback_en <= 0;
							Addr_reg_sel <= Incrementer_bus;
						end
						default: begin
						end
					endcase
				end else if (Load_f && cycle_count[2:1] == 2'b01) begin
					opcode_o <= MOV; // Mov Rd <- Data_reg_in
					Reg_bank_en <= 1;
					Writeback_en <= 0;
					B_shifter_en <= 0;
					Addr_reg_sel <= Incrementer_bus;
					Bus_B_sel <= Data_reg_in;
				end else if (~Load_f) begin
					core_nRW <= 1;
					Addr_reg_sel <= Incrementer_bus;
				end
			end
			BD_LS: begin
				Writeback_en <= wait_f ? (Pre_Pos_Indx_f ? (Write_Back_f ? 1'b1 : 1'b0) : 1'b1) : 0;
				wait_f <= 0;

				if (cycle_count[2:1] == 2'b01) begin
					Addr_reg_sel <= PC_bus;				
					increment_sel <= Address_reg;
				end else begin
					Addr_reg_sel <= Incrementer_bus;
					increment_sel <= PC;
				end
				
				if (Load_f && ~wait_f) begin
					opcode_o <= MOV; // Mov Rd <- Data_reg_in
					
					Reg_bank_en <= 1;
					B_shifter_en <= 0;
					Addr_reg_sel <= Incrementer_bus;
					Bus_B_sel <= Data_reg_in;

					Rd_o <= register_list[3:0];
					register_list <= register_list >> 4;
				end else begin
					Rd_o <= register_list[3:0];
					register_list <= register_list >> 4;
					core_nRW <= 1;
				end
			end
			Alu_OP: begin
				Multiplier_reg_en <= 0;
				Reg_bank_en <= 1;
			end
			Hi_op_BranchX: begin
				Reg_bank_en		<= 0;
				PSR_Thumb_bit	<= Rn0_Thumb;
			end
			default: begin

			end
		endcase
	end
end

always @(*) begin
	case (Inst_decoded_o)
		SD_Swap: begin
			Addr_reg_en <= ((cycle_count[1:0] == 2'b01) ? 1'b1 : 1'b0) || cycle_count[3];
		end
		HW_LS: begin
			Addr_reg_en <= (Rd_o == 4'b1111) ? ((cycle_count[4:3] == 2'b01) ? 1'b0 : 1'b1) : ((cycle_count[2:1] == 2'b01) ? 1'b0 : 1'b1);
		end
		SD_LS: begin
			Addr_reg_en <= (Rd_o == 4'b1111) ? ((cycle_count[4:3] == 2'b01) ? 1'b0 : 1'b1) : 1'b1;
		end
		BD_LS: begin
			Addr_reg_en <= (Rd_o == 4'b1111) ? ((cycle_count[4:3] == 2'b01) ? 1'b0 : 1'b1) : 1'b1;			
		end
		default: Addr_reg_en <= (cycles_types[1:0] == S || cycles_types[1:0] == N) ? 1'b1 : 1'b0;
	endcase

	pipeline_halt_r <= (!cycle_count[1] || cycles_types[1:0] == S) ? 1'b0 : 1'b1;
end

assign	pc_we = (Addr_reg_sel == Incrementer_bus && increment_sel == PC && Addr_reg_en) ? 1 : 0;

// Listing registers for Block Load/Store instruction 
wire [3:0] i15;
wire [7:0] i14;
wire [11:0] i13;
wire [15:0] i12;
wire [19:0] i11;
wire [23:0] i10;
wire [27:0] i9;
wire [31:0] i8;
wire [35:0] i7;
wire [39:0] i6;
wire [43:0] i5;
wire [47:0] i4;
wire [51:0] i3;
wire [55:0] i2;
wire [59:0] i1;
wire [63:0] i0;

assign i15 = instruct_reg[15] ?  4'd15 : 4'd0;
assign i14 = instruct_reg[14] ? {4'd14, i15} : i15;
assign i13 = instruct_reg[13] ? {4'd13, i14} : i14;
assign i12 = instruct_reg[12] ? {4'd12, i13} : i13;
assign i11 = instruct_reg[11] ? {4'd11, i12} : i12;
assign i10 = instruct_reg[10] ? {4'd10, i11} : i11;
assign i9  = instruct_reg[9]  ? {4'd9,  i10} : i10;
assign i8  = instruct_reg[8]  ? {4'd8,  i9}  : i9;
assign i7  = instruct_reg[7]  ? {4'd7,  i8}  : i8;
assign i6  = instruct_reg[6]  ? {4'd6,  i7}  : i7;
assign i5  = instruct_reg[5]  ? {4'd5,  i6}  : i6;
assign i4  = instruct_reg[4]  ? {4'd4,  i5}  : i5;
assign i3  = instruct_reg[3]  ? {4'd3,  i4}  : i4;
assign i2  = instruct_reg[2]  ? {4'd2,  i3}  : i3;
assign i1  = instruct_reg[1]  ? {4'd1,  i2}  : i2;
assign i0  = instruct_reg[0]  ? {4'd0,  i1}  : i1;

endmodule