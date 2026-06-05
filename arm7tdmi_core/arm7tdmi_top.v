module arm7tdmi_top (
    input  wire        MCLK,
    input  wire        reset_n,

    input  wire        nWAIT,

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

    output wire        sign_f,

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

    wire clk = MCLK && nWAIT;

    // A Bus Input Selector Params
    parameter	Rn = 2'b00;
    parameter	Rs = 2'b01;

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
    reg [31:0] writeback_addr;
    reg [31:0] wr_data;

    wire [31:0] CPSR;

    reg [4:0]  cpsr_mode;

    wire [2:0] exception_type;
    wire       exception_req;
    wire       exception_entry;
    wire       exception_rst;
    wire       exc_I_set;
    wire       exc_F_set;

    always @(*) begin
        if (exception_entry) begin
            case (exception_type)
                3'd0: cpsr_mode = 5'b10011; // Supervisor (Reset)
                3'd1: cpsr_mode = 5'b11011; // Undefined
                3'd2: cpsr_mode = 5'b10011; // Supervisor (SWI)
                3'd3: cpsr_mode = 5'b10111; // Prefetch Abort
                3'd4: cpsr_mode = 5'b10111; // Data Abort
                3'd6: cpsr_mode = 5'b10010; // IRQ
                3'd7: cpsr_mode = 5'b10001; // FIQ
                default: cpsr_mode = 5'b10000; // User
            endcase
        end else begin
            cpsr_mode = CPSR[4:0];
        end
    end

    wire        tbit;
    assign      tbit = CPSR[5];
    assign      tbit_out = tbit;

////////// Encoder //////////////
    wire [5:0] Inst_decoded;
    wire [3:0] condition;
    wire [3:0] opcode;
    wire [7:0] shift_data;

    wire       set_thumb_bit;
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
    wire        imm_operand_f;
    wire        acumulate_f;
    wire        mult_long_f;
    wire        byte_word_f;
    wire        hw_byte_f;
    wire        load_f;
    wire        pre_pos_indx_f;
    wire        up_down_f;
    wire        write_back_f;
    wire        l_psr_usermode_f;
    wire        link_f;
    wire        transf_len_f;
    wire        interrupt_f;
    wire        psr_sel_f;
    wire        set_condition_f;
    wire        h1_f;
    wire        h2_f;
    wire        sp_f;
    wire        pc_lr_f;
    wire        low_high_off_f;
    wire        shifter_reg_f;
    wire        signEx_f;

///////////////////////////////////////

////////// Barrel Shifter //////////////

    wire [31:0] shifter_out;
    wire        shifter_carry;

///////////////////////////////////////

//////////////// ALU //////////////

    wire [3:0]  nzcv;

///////////////////////////////////////

    wire [31:0] Multi_result_lo;
    wire [31:0] Multi_result_hi;
    wire        alu_cin_sel;
    reg         alu_carry_r = 0;
    wire        alu_cin_mux = alu_cin_sel ? alu_carry_r : CPSR[29];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) alu_carry_r <= 0;
        else alu_carry_r <= nzcv[1];
    end

    always @(*) begin
        case (Bus_A_sel)
            Rn: Bus_A = Rn_data;
            Rs: Bus_A = Rs_data;
            default: Bus_A = Rn_data;
        endcase
    end

    always @(*) begin
        case (Bus_B_sel)
            Rm: Bus_B = Rm_data;
            Immediate: Bus_B = {{8{signEx_f ? Immediate_data[23] : 1'b0}}, Immediate_data};
            Multiplier_Lo: Bus_B = Multi_result_lo;
            Multiplier_Hi: Bus_B = Multi_result_hi;
            Data_reg_in: Bus_B = Mem_Data_reg_in;
            default: Bus_B = 32'd0;
        endcase
    end

    always @(*) begin
        case (wr_data_reg_sel)
            1'b0: wr_data = Rs_data;
            1'b1: wr_data = Bus_B;
        endcase
    end

    always @(*) begin
        case (pre_pos_indx_f)
            1'b0: writeback_addr = Incrementer_bus;
            1'b1: writeback_addr = A;
        endcase
    end

    b_shifter b_shifter (
        .data_i             (Bus_B),
        .Rs_shift_ammount   (Rs_data[7:0]),
        .shift_data         (shift_data),
        .carry_i            (CPSR[29]),
        .Imm_Operand_f      (imm_operand_f),
        .B_shifter_en       (b_shifter_en),
        .data_o             (shifter_out),
        .carry_o            (shifter_carry)
    );

    reg_bank reg_bank (
        .clk          (clk),
        .cpsr_mode    (cpsr_mode),

        .writeback_addr  (writeback_addr),
        .writeback_en    (writeback_en),
        .exception_rst   (exception_rst),
        .exception_entry (exception_entry),
        .exception_type  (exception_type),
        .exc_I_set (exc_I_set),
        .exc_F_set (exc_F_set),

        .link_f         (link_f),
        .low_high_off_f (low_high_off_f),

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

        .nzcv         (nzcv),
        .set_condition_f (set_condition_f),
        .PSR_wr_en    (psr_wr_en),
        .PSR_rd_en    (psr_rd_en),
        .PSR_sel_f    (psr_sel_f),
        .cpsr_rdata   (CPSR),
        .spsr_rdata   (SPSR),

        .set_thumb    (set_thumb_bit),

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
        .cpsr_c        (alu_cin_mux),
        .shifter_carry (shifter_carry),
        .result        (Alu_bus),
        .n (nzcv[3]),
        .z (nzcv[2]),
        .c (nzcv[1]),
        .v (nzcv[0])
    );

    incrementer incrementer (
        .addr_reg_in    (A),
        .pc_in          (PC_bus),
        .increment_sel  (increment_sel),
        .tbit           (tbit),
        .writeback_en   (writeback_en),
        .up_down_f      (up_down_f),
        .addr_out       (Incrementer_bus)
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
        //.ABE            (),
        //.ALE            (),
        .Addr_reg_sel   (addr_reg_sel),
        .Addr_reg_en    (addr_reg_en),

        .A              (A)
    );

    multiplier multiplier(
        .data_a             (Bus_A),
        .data_b             (Rm_data),
        .CLK                (clk),
        .Multiplier_reg_en  (multiplier_reg_en),
        .sign_f             (sign_f),
        .result_lo          (Multi_result_lo),
        .result_hi          (Multi_result_hi)
    );

    decoder decoder (
        .Data_i             (DIN),
        .CPSR               (CPSR),
        .SPSR               (SPSR),
        .CLK                (clk),
        .nrst               (reset_n),
        .addr_odd           (A[1]),

        .nIRQ               (nIRQ),
        .nFIQ               (nFIQ),
        .ABORT              (ABORT),

        .exc_I_set          (exc_I_set),
        .exc_F_set          (exc_F_set),

        .exception_type     (exception_type),
        .exception_req      (exception_req),
        .exception_entry    (exception_entry),
        .exception_rst      (exception_rst),

        .nzcv               (nzcv),
        .reg_cond_field     (Alu_bus[31:28]),

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
        .set_thumb_bit      (set_thumb_bit),

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
        .alu_cin_sel        (alu_cin_sel),

        .Imm_Operand_f      (imm_operand_f),
        .Acumulate_f        (acumulate_f),
        .Mult_Long_f        (mult_long_f),
        .Sign_f             (sign_f),
        .Byte_Word_f        (byte_word_f),
        .HW_Byte_f          (hw_byte_f),
        .Load_f             (load_f),
        .Pre_Pos_Indx_f     (pre_pos_indx_f),
        .Up_Down_f          (up_down_f),
        .Write_Back_f       (write_back_f),
        .L_PSR_UserMode_f   (l_psr_usermode_f),
        .Link_f             (link_f),
        .Transf_len_f       (transf_len_f),
        .Interrupt_f        (interrupt_f),
        .PSR_sel_f          (psr_sel_f),
        .set_condition_f    (set_condition_f),
        .H1_f               (h1_f),
        .H2_f               (h2_f),
        .SP_f               (sp_f),
        .PC_LR_f            (pc_lr_f),
        .Low_High_off_f     (low_high_off_f),
        .Shifter_reg_f      (shifter_reg_f),
        .signEx_f           (signEx_f)
    );

endmodule