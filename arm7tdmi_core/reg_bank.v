// =============================================================================
// ARM7TDMI Register File Module (37 x 32-bit registers)
// =============================================================================
// 
// Reference: ARM7TDMI Data Sheet (ARM DDI 0029E)
// - Section 1.4: ARM7TDMI Core Diagram (page 1-5) → "Register Bank
//   (31 x 32-bit registers) (6 status registers)"
// - Section 3.7: Registers (pages 3-4 to 3-7) → full banking details
// - Section 3.6: Operating Modes (page 3-4) → mode encoding (CPSR[4:0])
// - Section 3.8: The Program Status Registers (pages 3-8 to 3-9)
//   → CPSR + 5×SPSR (one per exception mode)
// - Section 3.9: Exceptions (banking on mode switch)
// - Section 4.6: PSR Transfer (MRS, MSR) → direct CPSR/SPSR access
// 
// Physical registers:
//   - r0–r7     : 8 shared
//   - r8–r12    : 5 normal + 5 FIQ
//   - r13–r14   : 6 banks (User/System, FIQ, IRQ, SVC, Abort, Undefined)
//   - r15       : PC (not banked, special pipeline behaviour)
//   - CPSR      : 1
//   - SPSR      : 5 (FIQ, IRQ, SVC, Abort, Undefined)
//   Total = 31 GPR + 6 status = 37 registers (exact match to core diagram)
// 
// FPGA notes:
// - Dual read ports (combinational reads → fast critical path)
// - Single write port for GPRs (clocked)
// - Separate ports for CPSR/SPSR (used by MRS/MSR and exception entry)
// - PC has dedicated write port (used by BX, data processing to r15, branches)
// - Fully synthesizable on any FPGA (distributed RAM or registers, ~1.2 kbits)
// - No block RAM required — tiny logic.
// =============================================================================

module reg_bank (
    input  wire        clk,
    input  wire [4:0]  cpsr_mode,

    input  wire [31:0] writeback_addr,
    input  wire        writeback_en,
    input  wire        exception_rst,       // optional (PC=0 on reset, per 3.11)
    input  wire        exception_entry,
    input  wire [2:0]  exception_type,
    input  wire        exc_I_set,
    input  wire        exc_F_set,

    input  wire        link_f,
    input  wire        low_high_off_f,

    // === GPR Read Ports (r0–r15) ============================================
    input  wire [3:0]  ra,            // register A address (Rn)
    input  wire [3:0]  rb,            // register B address (Rm)
    output wire [31:0] rd_a,          // read data A
    output wire [31:0] rd_b,          // read data B

    input  wire [3:0]  rs,            // register S address (Rs)
    output wire [31:0] rd_s,          // read data S

    // === GPR Write Port =====================================================
    input  wire [3:0]  rd_addr,       // destination register (0–15)
    input  wire [31:0] write_data,    // write data
    input  wire        Reg_bank_en,   // write enable (from control)

    // === PC (r15) special interface =========================================
    // (pipeline adds +8 / +4 when reading r15 — see 3.7 and 10.x timing)
    input  wire        pc_we,
    input  wire [31:0] incrementer_wdata,
    output wire [31:0] pc_rdata,      // current PC value

    // === Status Registers (CPSR + SPSR) =====================================
    input  wire [3:0]  nzcv,
    input  wire        set_condition_f,
    input  wire        PSR_wr_en,
    input  wire        PSR_rd_en,
    input  wire        PSR_sel_f,
    output wire [31:0] cpsr_rdata,

    output wire [31:0] spsr_rdata,     // SPSR of current mode (control prevents user mode)

    input  wire        set_thumb,

    // Debug outputs     
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

    wire [31:0] cpsr_wdata;
    wire [31:0] spsr_wdata;

    // =========================================================================
    // Internal storage — exactly the 31 GPR + 6 status registers
    // =========================================================================
    reg [31:0] r_low     [0:7];   // r0–r7 (shared)
    reg [31:0] r_mid     [0:4];   // r8–r12 (normal)
    reg [31:0] r_mid_fiq [0:4];   // r8–r12 (FIQ only)
    reg [31:0] r_sp_lr   [0:5][1:0]; // r13–r14 × 6 banks
    reg [31:0] pc_reg;            // r15
    reg [31:0] cpsr_reg;          // CPSR
    reg [31:0] spsr_reg  [0:4];   // SPSR[FIQ, IRQ, SVC, Abort, Undef]

    // =========================================================================
    // Helper functions (pure combinational, synthesis-friendly)
    // =========================================================================
    function integer bank_idx;
        input [4:0] mode;
        begin
            case (mode)
                5'b10000, 5'b11111: bank_idx = 0; // User / System
                5'b10001:           bank_idx = 1; // FIQ
                5'b10010:           bank_idx = 2; // IRQ
                5'b10011:           bank_idx = 3; // SVC
                5'b10111:           bank_idx = 4; // Abort
                5'b11011:           bank_idx = 5; // Undefined
                default:            bank_idx = 0;
            endcase
        end
    endfunction

    function integer spsr_idx;
        input [4:0] mode;
        begin
            case (mode)
                5'b10001: spsr_idx = 0; // FIQ
                5'b10010: spsr_idx = 1; // IRQ
                5'b10011: spsr_idx = 2; // SVC
                5'b10111: spsr_idx = 3; // Abort
                5'b11011: spsr_idx = 4; // Undefined
                default:  spsr_idx = -1; // User/System → invalid (control blocks)
            endcase
        end
    endfunction

    // =========================================================================
    // Synchronous writes (reset + normal operation)
    // =========================================================================
    integer i;
    always @(posedge clk) begin
        if (exception_rst) begin
            // Synchronous reset triggered by a Reset-type exception entry
            pc_reg   <= 32'h0000_0000;
            cpsr_reg <= 32'h0000_00D3;
            for (i = 0; i < 8; i = i + 1) r_low[i] <= 32'b0;
            for (i = 0; i < 5; i = i + 1) begin
                r_mid[i]     <= 32'b0;
                r_mid_fiq[i] <= 32'b0;
                spsr_reg[i]  <= 32'b0;
            end
            for (i = 0; i < 6; i = i + 1) begin
                r_sp_lr[i][0] <= 32'b0;
                r_sp_lr[i][1] <= 32'b0;
            end
        end else begin
            // GPR write (r0–r15)
            if (Reg_bank_en) begin
                if (rd_addr < 8) begin
                    r_low[rd_addr] <= write_data;
                end else if (rd_addr < 13) begin
                    if (cpsr_mode == 5'b10001) // FIQ
                        r_mid_fiq[rd_addr-8] <= write_data;
                    else
                        r_mid[rd_addr-8] <= write_data;
                end else if (rd_addr < 15) begin
                    r_sp_lr[bank_idx(cpsr_mode)][rd_addr-13] <= write_data;
                end else if (rd_addr == 15) begin
                    if (PSR_wr_en && set_condition_f && spsr_idx(cpsr_mode) != -1) pc_reg <= spsr_reg[spsr_idx(cpsr_mode)][5] ? {write_data[31:1], 1'b0} : {write_data[31:2], 2'b00};
                    else pc_reg <= cpsr_reg[5] ? {write_data[31:1], 1'b0} : {write_data[31:2], 2'b00};
                end
            end

            // Dedicated PC write (branches, data ops to r15, etc.)
            if (pc_we)
                pc_reg <= cpsr_reg[5] ? {incrementer_wdata[31:1], 1'b0} : {incrementer_wdata[31:2], 2'b00};

            if (link_f) begin
                if (exception_entry) begin
                    case (exception_type)
                        3'd1: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg - (cpsr_reg[5] ? 32'd2 : 32'd4); // Undefined
                        3'd2: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg - (cpsr_reg[5] ? 32'd2 : 32'd4); // Supervisor (SWI)
                        3'd3: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg; // Prefetch Abort
                        3'd4: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg; // Data Abort
                        3'd6: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg; // IRQ
                        3'd7: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg; // FIQ
                        default: r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg - (cpsr_reg[5] ? 32'd2 : 32'd4) + low_high_off_f;
                    endcase
                end else begin
                    r_sp_lr[bank_idx(cpsr_mode)][1] <= pc_reg - (cpsr_reg[5] ? 32'd2 : 32'd4) + low_high_off_f;
                end                
            end

            // Dedicated Thumb Set
            if (set_thumb) begin
                if (rb < 8)
                    cpsr_reg[5] <= r_low[rb][0];
                else if (rb < 13)
                    cpsr_reg[5] <= (cpsr_mode == 5'b10001) ? r_mid_fiq[rb-8][0] : r_mid[rb-8][0];
                else if (rb < 15)
                    cpsr_reg[5] <= r_sp_lr[bank_idx(cpsr_mode)][rb-13][0];
                else
                    cpsr_reg[5] <= pc_reg[0];
            end

            // Dedicated writeback write
            if (writeback_en) begin
                if (ra < 8) begin
                    r_low[ra] <= writeback_addr;
                end else if (ra < 13) begin
                    if (cpsr_mode == 5'b10001) // FIQ
                        r_mid_fiq[ra-8] <= writeback_addr;
                    else
                        r_mid[ra-8] <= writeback_addr;
                end else if (ra < 15) begin
                    r_sp_lr[bank_idx(cpsr_mode)][ra-13] <= writeback_addr;
                end else if (ra == 15) begin
                    pc_reg <= cpsr_reg[5] ? {writeback_addr[31:1], 1'b0} : {writeback_addr[31:2], 2'b00};
                end
            end

            // CPSR/SPSR write (MSR, exception entry, etc.)
            if (PSR_wr_en) begin
                if (PSR_sel_f) begin
                    if (spsr_idx(cpsr_mode) != -1) begin
                        if (exception_entry) begin // Exception Entry Handler
                            spsr_reg[spsr_idx(cpsr_mode)] <= cpsr_reg;
                            cpsr_reg[5:0] <= {1'b0, cpsr_mode};
                            if (exc_F_set) cpsr_reg[6] <= 1;
                            if (exc_I_set) cpsr_reg[7] <= 1;
                        end else if (set_condition_f) begin                            
                            spsr_reg[spsr_idx(cpsr_mode)][31:28] <= write_data[31:28];
                        end else begin
                            spsr_reg[spsr_idx(cpsr_mode)] <= write_data;
                        end
                    end
                end else begin
                    if (set_condition_f) begin
                        if (rd_addr == 4'b1111 && spsr_idx(cpsr_mode) != -1) begin
                            cpsr_reg <= spsr_reg[spsr_idx(cpsr_mode)];
                        end else begin
                            cpsr_reg[31:28] <= nzcv;
                        end
                    end else begin
                        cpsr_reg <= write_data;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Combinational reads (dual port — critical for datapath timing)
    // =========================================================================
    reg [31:0] rd_a_int = 0;
    reg [31:0] rd_b_int = 0;
    reg [31:0] rd_s_int = 0;

    always @* begin
        // Read port A
        if (ra < 8)
            rd_a_int = r_low[ra];
        else if (ra < 13)
            rd_a_int = (cpsr_mode == 5'b10001) ? r_mid_fiq[ra-8] : r_mid[ra-8];
        else if (ra < 15)
            rd_a_int = r_sp_lr[bank_idx(cpsr_mode)][ra-13];
        else
            rd_a_int = pc_reg;               // r15 → current PC (pipeline adds +8/+4)
    end

    always @* begin
        // Read port B (identical logic)
        if (rb < 8)
            rd_b_int = r_low[rb];
        else if (rb < 13)
            rd_b_int = (cpsr_mode == 5'b10001) ? r_mid_fiq[rb-8] : r_mid[rb-8];
        else if (rb < 15)
            rd_b_int = r_sp_lr[bank_idx(cpsr_mode)][rb-13];
        else
            rd_b_int = pc_reg;
    end

    always @* begin
        // Read port S (identical logic)
        if (rs < 8)
            rd_s_int = r_low[rs];
        else if (rs < 13)
            rd_s_int = (cpsr_mode == 5'b10001) ? r_mid_fiq[rs-8] : r_mid[rs-8];
        else if (rs < 15)
            rd_s_int = r_sp_lr[bank_idx(cpsr_mode)][rs-13];
        else
            rd_s_int = pc_reg;
    end

    // Output assignments
    assign rd_a      = rd_a_int;
    assign rd_b      = PSR_rd_en ? (PSR_sel_f ? ((spsr_idx(cpsr_mode) != -1) ? spsr_reg[spsr_idx(cpsr_mode)] : 32'b0) : cpsr_reg) : rd_b_int;
    assign rd_s      = rd_s_int;
    assign pc_rdata  = pc_reg;
    assign cpsr_rdata = cpsr_reg;
    assign spsr_rdata = (spsr_idx(cpsr_mode) != -1) ? spsr_reg[spsr_idx(cpsr_mode)] : 32'b0;

    // Debug
    
    assign r0   = r_low[0];
    assign r1   = r_low[1];
    assign r2   = r_low[2];
    assign r3   = r_low[3];
    assign r4   = r_low[4];
    assign r5   = r_low[5];
    assign r6   = r_low[6];
    assign r7   = r_low[7];
    assign r8   = r_mid[0];
    assign r9   = r_mid[1];
    assign r10  = r_mid[2];
    assign r11  = r_mid[3];
    assign r12  = r_mid[4];
    assign r13  = r_sp_lr[bank_idx(cpsr_mode)][0];   
    assign r14  = r_sp_lr[bank_idx(cpsr_mode)][1];
    assign r15  = pc_reg;

endmodule