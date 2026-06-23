//////////////////////////////////////////////////////////////////////
//
// This source file may be used and distributed without
// restriction provided that this copyright statement is not
// removed from the file and that any derivative work contains
// the original copyright notice and the associated disclaimer.
//
// This source file is free software; you can redistribute it
// and/or modify it under the terms of the GNU Lesser General
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any
// later version.
//
// This source is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
// PURPOSE.  See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General
// Public License along with this source; if not, download it
// from http://www.opencores.org/lgpl.shtml
//
//////////////////////////////////////////////////////////////////////

module sdram_controller_top (
    input   wire        clock,        // CPU / core frequency
    input   wire        clock_sdram,  // SDRAM frequency
    input   wire        nrst,

    input   wire        rd_en,
    input   wire        wr_en,
    input   wire [1:0]  MAS,          // active master size: 00=byte 01=half 10=word
    input   wire        sign_extend,  // CPU sign_f, for byte loads

	input   wire [27:0] addr,
    input   wire [31:0] wr_data,
    output  wire [31:0] rd_data,
    output  wire        busy,

    output  wire [12:0] SA,
    output  wire [1:0]  BA,
    output  wire        CS_N,
    output  wire        CKE,
    output  wire        RAS_N,
    output  wire        CAS_N,
    output  wire        WE_N,
    inout   wire [15:0] DQ,
    output  wire [1:0]  DQM
);

wire is_ewram = addr[27:24] == 4'h2;
wire is_byte  = (MAS == 2'b00);
wire is_word  = MAS[1];            // MAS: 10=word, 01=half, 00=byte

reg [24:0] addr_r = 0;
reg [31:0] wr_data_r = 0;
reg [1:0]  byte_mask_r = 2'b00;   // DQM {low,high} for the latched write beat

// Read-beat qualifiers, latched at request time, used to format read data.
reg        rd_byte_r = 0;   // this beat is a byte load
reg        rd_word_r = 0;   // this beat is a 32-bit word load
reg        rd_lane_r = 0;   // addr[0]: which byte within the halfword
reg        rd_sign_r = 0;   // sign-extend the loaded byte

always @(posedge clock) begin
    if (wr_en || rd_en) addr_r <= is_ewram ? {8'b0,addr[17:1]} : {1'b1,addr[24:1]};
    if (wr_en) begin
        // Byte: replicate into the low lane (core uses [15:0]); DQM picks the
        // addressed byte. Half/word: pass the full 32 bits; the core writes the
        // low half then the high half on a word access.
        wr_data_r   <= is_byte ? {16'b0, {2{wr_data[7:0]}}} : wr_data;
        byte_mask_r <= is_byte ? (addr[0] ? 2'b10 : 2'b01) : 2'b00;
    end
    if (rd_en) begin
        rd_byte_r <= is_byte;
        rd_word_r <= is_word;
        rd_lane_r <= addr[0];
        rd_sign_r <= sign_extend;
    end
end

// Read Data

wire [15:0] rd_data_i;
wire        rd_ready;
reg [15:0]  rd_data_r0 = 0, rd_data_r1 = 0, rd_data_r2 = 0;
reg         rd_ready_r0 = 0, rd_ready_r1 = 0;

wire rd_ready_pulse = !rd_ready_r1 && rd_ready_r0;

always @(posedge clock_sdram) begin
    rd_ready_r0 <= rd_ready;
    rd_ready_r1 <= rd_ready_r0;
    rd_data_r0 <= rd_data_i;
    rd_data_r1 <= rd_data_r0;
    if (rd_ready_pulse) rd_data_r2 <= rd_data_r0;
end

// Byte loads: select the addressed lane and (optionally) sign-extend.
// Halfword/word loads keep the prior zero-extended-halfword behaviour.
wire [7:0]  rd_byte     = rd_lane_r ? rd_data_r2[15:8] : rd_data_r2[7:0];
wire [31:0] rd_byte_ext = rd_sign_r ? {{24{rd_byte[7]}}, rd_byte} : {24'b0, rd_byte};
assign rd_data = rd_byte_r ? rd_byte_ext : {16'b0, rd_data_r2};

///////////////////////////////////////////////////////////////////////

wire        access   = rd_en || wr_en;
reg  [29:0] acc_q = 0;
wire [29:0] acc      = {addr, rd_en, wr_en};
wire        new_beat = access && (acc != acc_q);
always @(posedge clock) acc_q <= acc;

reg rd_start = 0, wr_start = 0;
always @(posedge clock) begin
    rd_start <= new_beat && rd_en;
    wr_start <= new_beat && wr_en;
end

// 2-FF synchronizer
reg rd_s0 = 0, rd_s1 = 0, rd_s2 = 0;
reg wr_s0 = 0, wr_s1 = 0, wr_s2 = 0;
always @(posedge clock_sdram) begin
    rd_s0 <= rd_start; rd_s1 <= rd_s0; rd_s2 <= rd_s1;
    wr_s0 <= wr_start; wr_s1 <= wr_s0; wr_s2 <= wr_s1;
end
wire rd_edge = rd_s1 && !rd_s2;
wire wr_edge = wr_s1 && !wr_s2;

// "accept" = core enters a transaction; "busy_end" = core leaves one.
wire core_busy;
reg core_busy_d = 0;
always @(posedge clock_sdram) core_busy_d <= core_busy;
wire accept    =  core_busy && !core_busy_d;
wire busy_end  = !core_busy &&  core_busy_d;

// Hold each request until the core accepts it.
reg rd_req = 0, wr_req = 0;
always @(posedge clock_sdram)
    if (!nrst) begin
        rd_req <= 0;
        wr_req <= 0;
    end else begin
        if (rd_edge)                          rd_req <= 1;
        else if (accept && rd_req)            rd_req <= 0;

        if (wr_edge)                          wr_req <= 1;
        else if (accept && !rd_req && wr_req) wr_req <= 0;
    end

wire rd_en_pulse = rd_req;
wire wr_en_pulse = wr_req;

//////////////////////////////////////////

reg done = 0;
always @(posedge clock_sdram or negedge nrst)
    if (!nrst)                            done <= 0;
    else if (rd_ready_pulse || busy_end)  done <= 1;
    else if (rd_edge || wr_edge)          done <= 0;

assign busy = access && !(done && !new_beat);

// ======================================================================
// SDRAM controller core (clock_sdram domain)
// ======================================================================
sdram_controller sdram_controlleri (
    /* HOST INTERFACE */
    .wr_addr       (addr_r),
    .wr_data       (wr_data_r),
    .byte_mask     (byte_mask_r),
    .wr_enable     (wr_en_pulse),

    .rd_addr       (addr_r),
    .rd_data       (rd_data_i),
    .rd_ready      (rd_ready),
    .rd_enable     (rd_en_pulse),

    .busy          (core_busy),
    .rst_n         (nrst),
    .clk           (clock_sdram),

    /* SDRAM SIDE */
    .addr          (SA),
    .bank_addr     (BA),
    .data          (DQ),
    .clock_enable  (CKE),
    .cs_n          (CS_N),
    .ras_n         (RAS_N),
    .cas_n         (CAS_N),
    .we_n          (WE_N),
    .data_mask_low (DQM[0]),
    .data_mask_high(DQM[1])
);

endmodule // sdram_controller_top
