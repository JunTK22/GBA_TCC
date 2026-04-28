module arm7tdmi_top (
    input  wire        clk,
    input  wire        reset_n,

    // === External Memory Interface (Section 6) ===============================
    input  wire [31:0] DIN,          // Data from memory (read)
    output wire [31:0] A,            // Address bus
    output wire [31:0] DOUT,         // Data to memory (write)
    output wire        nRW,
    output wire [1:0]  MAS,
    output wire        nMREQ,
    output wire        SEQ,
    output wire        nOPC,
    output wire        nTRANS,

    output wire        nENOUT,

    // === Interrupts & Abort (Section 3.9) ===================================
    input  wire        nIRQ,
    input  wire        nFIQ,
    input  wire        ABORT,

    // === Debug outputs =============================================
    output wire        tbit_out,      // TBIT (Thumb state)

    output wire [31:0] r0,
    output wire [31:0] r1,
    output wire [31:0] r2,
    output wire [31:0] r3,
    output wire [31:0] r4,
    output wire [31:0] r5,
    output wire [31:0] r6,
    output wire [31:0] r7,
    output wire [31:0] r8,
    output wire [31:0] r9,
    output wire [31:0] r10,
    output wire [31:0] r11,
    output wire [31:0] r12,
    output wire [31:0] r13,
    output wire [31:0] r14,
    output wire [31:0] r15
);

    // A Bus Input Selector Params
    parameter	Rn = 2'b00;
    parameter	Rs = 2'b01;
    //parameter	Multiplier_Lo  = 2'b10;
    //parameter	Multiplier_Hi  = 2'b11;

    // B Bus Input Selector Params
    parameter	Rm = 3'b000;
    parameter	Immediate  	= 3'b001;
    parameter	Multiplier_Lo  = 3'b010;
    parameter	Multiplier_Hi  = 3'b011;
    parameter	Data_reg_in = 3'b100;

    // Write Data Register Selector Params
    parameter	Reg_Bank = 1'b0;
    parameter	Bus_B_data = 1'b1;

    // Data Buses
    reg  [31:0] Bus_A = 0;
    reg  [31:0] Bus_B = 0;
    wire [31:0] Alu_bus;
    wire [31:0] PC_bus;
    wire [31:0] Incrementer_bus;
    reg [31:0] wr_data;

    wire [31:0] CPSR;

    wire [4:0]  cpsr_mode;
    assign      cpsr_mode = CPSR[4:0];

    wire        tbit;
    assign      tbit = CPSR[5];

////////// Encoder //////////////
    wire [5:0] Inst_decoded;
    wire [3:0] condition;
    wire [3:0] opcode;
    wire [7:0] shift_data;

    wire       Set_PSR_Thumb_bit;
    wire       cond_valid;

    wire       core_nRW;
    assign nRW = core_nRW;

    // Register Addressess
    wire [3:0] Rn_addr;
    wire [3:0] Rd_addr;
    wire [3:0] Rs_addr;
    wire [3:0] Rm_addr;

    // Data coming out of reg bank
    wire [31:0] Rn_data;
    wire [31:0] Rs_data;
    wire [31:0] Rm_data;

    // Data coming out of decoder
    wire [31:0] Mem_Data_reg_in;
    wire [23:0] Immediate_data;

    // Enable signals
    wire        addr_reg_en;
    wire        wr_data_reg_en;
    wire        reg_bank_en;
    wire        b_shifter_en;
    wire        multiplier_reg_en;
    wire        psr_wr_en;
    wire        psr_rd_en;
    wire        writeback_en;
    wire        pc_we;

    // Selectors
    wire [1:0]  addr_reg_sel;
    wire [1:0]  Bus_A_sel;
    wire [2:0]  Bus_B_sel;
    wire        wr_data_reg_sel;
    wire        increment_sel;

    // control flags
    wire        set_condition_f;
    wire        imm_operand_f;
    wire        acumulate_f;
    wire        mult_long_f;
    wire        sign_f;
    wire        byte_word_f;
    wire        hw_byte_f;
    wire        load_f;
    wire        pre_pos_indx_f;
    wire        pre_pos_inc_f;
    wire        up_down_f;
    wire        write_back_f;
    wire        l_psr_usermode_f;
    wire        link_f;
    wire        transf_len_f;
    wire        interrupt_f;
    wire        psr_sel_f;
    wire        psr_flags_only_f;
    wire        h1_f;
    wire        h2_f;
    wire        sp_f;
    wire        pc_lr_f;
    wire        low_high_off_f;
    wire        shifter_reg_f;

///////////////////////////////////////

////////// Barrel Shifter //////////////

    wire [31:0] shifter_out;
    wire        shifter_carry;

///////////////////////////////////////

//////////////// ALU //////////////

    wire [3:0]  nzcv;

///////////////////////////////////////

    wire [31:0] incrementer_in;

    wire [31:0] Multi_result_lo;
    wire [31:0] Multi_result_hi;

    always @(*) begin
        case (Bus_A_sel)
            Rn: Bus_A <= Rn_data;
            Rs: Bus_A <= Rs_data;
            Multiplier_Lo[1:0]: Bus_A <= Multi_result_lo;
            Multiplier_Hi[1:0]: Bus_A <= Multi_result_hi;
        endcase
    end

    always @(*) begin
        case (Bus_B_sel)
            Rm: Bus_B <= Rm_data;
            Immediate: Bus_B <= Immediate_data;
            Multiplier_Lo: Bus_B <= Multi_result_lo;
            Multiplier_Hi: Bus_B <= Multi_result_hi;
            Data_reg_in: Bus_B <= Mem_Data_reg_in;
            default: Bus_B <= 32'd0;
        endcase
    end

    always @(*) begin
        case (wr_data_reg_sel)
            1'b0: wr_data <= Rs_data;
            1'b1: wr_data <= Bus_B;
        endcase
    end

    b_shifter b_shifter (
        .data_i             (Bus_B),
        .Rs_shift_ammount   (Rs_data),
        .shift_data         (shift_data),
        .carry_i            (CPSR[29]),
        .Imm_Operand_f      (imm_operand_f),
        .B_shifter_en       (b_shifter_en),
        .data_o             (shifter_out),
        .carry_o            (shifter_carry)
    );

    reg_bank reg_bank (
        .clk          (clk),
        .reset_n      (reset_n),
        .cpsr_mode    (cpsr_mode),

        .writeback_en    (writeback_en),


        .ra           (Rn_addr),
        .rb           (Rm_addr),
        .rd_a         (Rn_data),
        .rd_b         (Rm_data),
        
        .rs           (Rs_addr),
        .rd_s         (Rs_data),
        
        .rd_addr      (Rd_addr),
        .write_data   (Alu_bus),
        .Reg_bank_en  (reg_bank_en),

        .pc_we        (pc_we),
        .incrementer_wdata (Incrementer_bus),
        .pc_rdata     (PC_bus),

        .PSR_wr_en    (psr_wr_en),
        .PSR_rd_en    (psr_rd_en),
        .PSR_sel_f    (psr_sel_f),
        .PSR_flags_only_f (psr_flags_only_f),
        .cpsr_rdata   (CPSR),
        .spsr_rdata   (),

        .r0     (r0),
        .r1     (r1),
        .r2     (r2),
        .r3     (r3),
        .r4     (r4),
        .r5     (r5),
        .r6     (r6),
        .r7     (r7),
        .r8     (r8),
        .r9     (r9),
        .r10    (r10),
        .r11    (r11),
        .r12    (r12),
        .r13    (r13),
        .r14    (r14),
        .r15    (r15)
    );

    alu alu (
        .op_a          (Bus_A),
        .op_b          (shifter_out),
        .alu_opcode    (opcode),
        .cpsr_c        (CPSR[29]),
        .shifter_carry (shifter_carry),
        .result        (Alu_bus),
        .n (nzcv[3]),
        .z (nzcv[2]),
        .c (nzcv[1]),
        .v (nzcv[0])
    );

    incrementer incrementer (
        .addr_reg_in  (incrementer_in),
        .pc_in    (PC_bus),
        .increment_sel     (increment_sel),
        .tbit     (tbit),
        .clk      (clk),
        .addr_out (Incrementer_bus)
    );

    write_data_reg write_data_reg (
        .clk      (clk),
        .reset_n  (reset_n),
        .data_in  (wr_data),
        .we       (wr_data_reg_en),
        .nRW      (core_nRW),
        .data_out (DOUT),
        .nENOUT   (nENOUT),
        .data_bus_oe ()
    );

    address_reg address_reg (
        .Incrementer    (Incrementer_bus),
        .ALU            (Alu_bus),
        .PC             (PC_bus),
        .Rn             (Rn_data),

        .CLK            (clk),
        .nRST           (reset_n),
        .ABE            (),
        .ALE            (),
        .Addr_reg_sel   (addr_reg_sel),
        .Addr_reg_en    (addr_reg_en),
        .Pre_Pos_Inc_f  (pre_pos_inc_f),

        .A              (A),
        .to_incrementer (incrementer_in)
    );

    multiplier multiplier(
        .data_a             (Bus_A),
        .data_b             (Rm_data),
        .CLK                (clk),
        .Multiplier_reg_en  (multiplier_reg_en),
        .result_lo          (Multi_result_lo),
        .result_hi          (Multi_result_hi)
    );

    decoder decoder (
        .Data_i             (DIN),
        .PSR                (CPSR),
        .Rn0_Thumb          (Rm_data[0]),   // bit[0] of Rn for BX/Thumb
        .CLK                (clk),
        .pipeline_rst_n     (reset_n),

        .nIRQ               (nIRQ),
        .nFIQ               (nFIQ),
        .ABORT              (ABORT),

        .Data_o             (Mem_Data_reg_in),

        .Inst_decoded_o     (Inst_decoded),
        .cond_o             (condition),
        .opcode_o           (opcode),
        .Rn_o               (Rn_addr),
        .Rd_o               (Rd_addr),
        .Rs_o               (Rs_addr),
        .Rm_o               (Rm_addr),
        .Imm_o              (Immediate_data),
        .Shift_o            (shift_data),
        .PSR_Thumb_bit      (Set_PSR_Thumb_bit),

        .cond_valid         (cond_valid),

        .core_nRW           (core_nRW),

        .MAS                (MAS),
        .nMREQ              (nMREQ),
        .SEQ                (SEQ),
        .nOPC               (nOPC),
        .nTRANS             (nTRANS),

        .Addr_reg_en        (addr_reg_en),
        .Wr_Data_reg_en     (wr_data_reg_en),
        .Reg_bank_en        (reg_bank_en),
        .B_shifter_en       (b_shifter_en),
        .Multiplier_reg_en  (multiplier_reg_en),
        .PSR_wr_en          (psr_wr_en),
        .PSR_rd_en          (psr_rd_en),
        .Writeback_en       (writeback_en),
        .pc_we              (pc_we),

        .Addr_reg_sel       (addr_reg_sel),
        .Bus_A_sel          (Bus_A_sel),
        .Bus_B_sel          (Bus_B_sel),
        .Wr_Data_reg_sel    (wr_data_reg_sel),
        .increment_sel      (increment_sel),

        .Set_condition_f    (set_condition_f),
        .Imm_Operand_f      (imm_operand_f),
        .Acumulate_f        (acumulate_f),
        .Mult_Long_f        (mult_long_f),
        .Sign_f             (sign_f),
        .Byte_Word_f        (byte_word_f),
        .HW_Byte_f          (hw_byte_f),
        .Load_f             (load_f),
        .Pre_Pos_Indx_f     (pre_pos_indx_f),
        .Pre_Pos_Inc_f      (pre_pos_inc_f),
        .Up_Down_f          (up_down_f),
        .Write_Back_f       (write_back_f),
        .L_PSR_UserMode_f   (l_psr_usermode_f),
        .Link_f             (link_f),
        .Transf_len_f       (transf_len_f),
        .Interrupt_f        (interrupt_f),
        .PSR_sel_f          (psr_sel_f),
        .PSR_flags_only_f   (psr_flags_only_f),
        .H1_f               (h1_f),
        .H2_f               (h2_f),
        .SP_f               (sp_f),
        .PC_LR_f            (pc_lr_f),
        .Low_High_off_f     (low_high_off_f),
        .Shifter_reg_f      (shifter_reg_f)
    );

endmodule