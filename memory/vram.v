// =============================================================================
//  vram.v
//  96 KiB dual-port Video RAM behind the 128 KiB GBA VRAM aperture.
//
//  One 64 KiB BG bank and two 16 KiB OBJ banks implement the documented
//  aperture mirroring. Each physical bank has a CPU/DMA read-write port and a
//  PPU read-only port. BG/OBJ routing depends on the display mode; force blank
//  suppresses PPU requests.
//
//  CPU/DMA and PPU addresses at this boundary are byte addresses. CPU/DMA
//  32-bit accesses use two 16-bit beats. The first same-bank CPU/PPU collision
//  adds one wait cycle without stopping the PPU port or losing a pending beat.
// =============================================================================

`timescale 1ns / 1ps

module vram (
    input  wire        clk,
    input  wire [16:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire        rden,
    input  wire [1:0]  size,
    input  wire        sign_extend,
    output wire        ready,
    output wire        misalign_fault,

    input  wire [16:0] bg_addr,
    output wire [15:0] bg_rdata,
    input  wire        bg_rden,

    input  wire [14:0] obj_addr,
    output wire [15:0] obj_rdata,
    input  wire        obj_rden,

    input  wire [2:0]  bg_mode,
    input  wire        force_blank
);

    localparam [1:0] BANK_BG       = 2'd0;
    localparam [1:0] BANK_OBJ_LOW  = 2'd1;
    localparam [1:0] BANK_OBJ_HIGH = 2'd2;
    localparam [1:0] BANK_ZERO     = 2'd3;

    wire bitmap_mode = bg_mode > 3'd2;

    wire cpu_bg_sel       = !addr[16];
    wire cpu_obj_low_sel  = addr[16] && !addr[14];
    wire cpu_obj_high_sel = addr[16] && addr[14];
    wire cpu_request = rden || we;

    wire bg_request  = bg_rden && !force_blank;
    wire obj_request = obj_rden && !force_blank;

    wire ppu_bg_read = bg_request && !bg_addr[16];
    wire ppu_obj_low_bg_read =
        bg_request && bitmap_mode && bg_addr[16] && !bg_addr[14];
    wire ppu_obj_low_obj_read =
        obj_request && !bitmap_mode && !obj_addr[14];
    wire ppu_obj_low_read =
        ppu_obj_low_bg_read || ppu_obj_low_obj_read;
    wire ppu_obj_high_read = obj_request && obj_addr[14];

    wire cpu_bg_request = cpu_request && cpu_bg_sel;
    wire cpu_obj_low_request = cpu_request && cpu_obj_low_sel;
    wire cpu_obj_high_request = cpu_request && cpu_obj_high_sel;

    wire cpu_bg_collision = cpu_bg_request && ppu_bg_read;
    wire cpu_obj_low_collision =
        cpu_obj_low_request && ppu_obj_low_read;
    wire cpu_obj_high_collision =
        cpu_obj_high_request && ppu_obj_high_read;
    wire cpu_collision =
        cpu_bg_collision || cpu_obj_low_collision || cpu_obj_high_collision;

    // Only the first collision in a held CPU/DMA transaction inserts a wait.
    // The physical second port lets the PPU continue while the held CPU beat is
    // serviced on the following cycle.
    reg cpu_collision_waited = 1'b0;
    wire cpu_collision_stall =
        cpu_request && cpu_collision && !cpu_collision_waited;
    wire cpu_access_issued = cpu_request && !cpu_collision_stall;

    wire bg_cpu_access = cpu_access_issued && cpu_bg_sel;
    wire obj_low_cpu_access = cpu_access_issued && cpu_obj_low_sel;
    wire obj_high_cpu_access = cpu_access_issued && cpu_obj_high_sel;

    wire [31:0] bg_mem_rdata;
    wire [15:0] bg_ppu_rdata;
    wire bg_ready;
    wire bg_misalign_fault;

    gba_ram_w16_dualport #(
        .DEPTH_POW2 (15),
        .INIT_FILE  ("UNUSED")
    ) bg_mem (
        .clk            (clk),
        .addr           (addr[15:0]),
        .wdata          (wdata),
        .rdata          (bg_mem_rdata),
        .we             (bg_cpu_access && we),
        .rden           (bg_cpu_access && rden),
        .size           (size),
        .sign_extend    (sign_extend),
        .ready          (bg_ready),
        .misalign_fault (bg_misalign_fault),
        .ppu_addr       (bg_addr[15:1]),
        .ppu_rden       (ppu_bg_read),
        .ppu_rdata      (bg_ppu_rdata)
    );

    wire [12:0] obj_low_ppu_addr =
        ppu_obj_low_bg_read ? bg_addr[13:1] : obj_addr[13:1];
    wire [31:0] obj_low_mem_rdata;
    wire [15:0] obj_low_ppu_rdata;
    wire obj_low_ready;
    wire obj_low_misalign_fault;

    gba_ram_w16_dualport #(
        .DEPTH_POW2 (13),
        .INIT_FILE  ("UNUSED")
    ) obj_low_mem (
        .clk            (clk),
        .addr           (addr[13:0]),
        .wdata          (wdata),
        .rdata          (obj_low_mem_rdata),
        .we             (obj_low_cpu_access && we),
        .rden           (obj_low_cpu_access && rden),
        .size           (size),
        .sign_extend    (sign_extend),
        .ready          (obj_low_ready),
        .misalign_fault (obj_low_misalign_fault),
        .ppu_addr       (obj_low_ppu_addr),
        .ppu_rden       (ppu_obj_low_read),
        .ppu_rdata      (obj_low_ppu_rdata)
    );

    wire [31:0] obj_high_mem_rdata;
    wire [15:0] obj_high_ppu_rdata;
    wire obj_high_ready;
    wire obj_high_misalign_fault;

    gba_ram_w16_dualport #(
        .DEPTH_POW2 (13),
        .INIT_FILE  ("UNUSED")
    ) obj_high_mem (
        .clk            (clk),
        .addr           (addr[13:0]),
        .wdata          (wdata),
        .rdata          (obj_high_mem_rdata),
        .we             (obj_high_cpu_access && we),
        .rden           (obj_high_cpu_access && rden),
        .size           (size),
        .sign_extend    (sign_extend),
        .ready          (obj_high_ready),
        .misalign_fault (obj_high_misalign_fault),
        .ppu_addr       (obj_addr[13:1]),
        .ppu_rden       (ppu_obj_high_read),
        .ppu_rdata      (obj_high_ppu_rdata)
    );

    reg [1:0] bg_response_bank = BANK_ZERO;
    reg [1:0] obj_response_bank = BANK_ZERO;
    reg [1:0] cpu_response_bank = BANK_BG;

    always @(posedge clk) begin
        if (bg_request) begin
            if (ppu_bg_read)
                bg_response_bank <= BANK_BG;
            else if (ppu_obj_low_bg_read)
                bg_response_bank <= BANK_OBJ_LOW;
            else
                bg_response_bank <= BANK_ZERO;
        end

        if (obj_request) begin
            if (ppu_obj_high_read)
                obj_response_bank <= BANK_OBJ_HIGH;
            else if (ppu_obj_low_obj_read)
                obj_response_bank <= BANK_OBJ_LOW;
            else
                obj_response_bank <= BANK_ZERO;
        end

        if (cpu_access_issued) begin
            if (cpu_bg_sel)
                cpu_response_bank <= BANK_BG;
            else if (cpu_obj_high_sel)
                cpu_response_bank <= BANK_OBJ_HIGH;
            else
                cpu_response_bank <= BANK_OBJ_LOW;
        end
    end

    assign bg_rdata =
        bg_response_bank == BANK_BG      ? bg_ppu_rdata
      : bg_response_bank == BANK_OBJ_LOW ? obj_low_ppu_rdata
      : 16'h0000;

    assign obj_rdata =
        obj_response_bank == BANK_OBJ_HIGH ? obj_high_ppu_rdata
      : obj_response_bank == BANK_OBJ_LOW  ? obj_low_ppu_rdata
      : 16'h0000;

    assign rdata =
        cpu_response_bank == BANK_BG       ? bg_mem_rdata
      : cpu_response_bank == BANK_OBJ_HIGH ? obj_high_mem_rdata
      : obj_low_mem_rdata;

    wire selected_ready =
        cpu_bg_sel       ? bg_ready
      : cpu_obj_high_sel ? obj_high_ready
      : obj_low_ready;

    always @(posedge clk) begin
        if (!cpu_request)
            cpu_collision_waited <= 1'b0;
        else if (cpu_collision_stall)
            cpu_collision_waited <= 1'b1;
        else if (cpu_access_issued && selected_ready)
            cpu_collision_waited <= 1'b0;
    end

    assign ready =
        !cpu_request || (!cpu_collision_stall && selected_ready);

    assign misalign_fault =
        cpu_response_bank == BANK_BG       ? bg_misalign_fault
      : cpu_response_bank == BANK_OBJ_HIGH ? obj_high_misalign_fault
      : obj_low_misalign_fault;

endmodule
