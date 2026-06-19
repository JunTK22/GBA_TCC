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

	input   wire [27:0] addr,
    input   wire [15:0] wr_data,
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

reg [24:0] addr_r = 0;
reg [15:0] wr_data_r = 0;

always @(posedge clock) begin
    if (wr_en || rd_en) addr_r <= is_ewram ? {8'b0,addr[17:1]} : {1'b1,addr[24:1]};
    if (wr_en) wr_data_r <= wr_data;
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

assign rd_data = {16'b0,rd_data_r2};

// Write/Read request-hold

reg wr_en_r0 = 0, rd_en_r0 = 0;
always @(posedge clock) begin
    wr_en_r0 <= wr_en;
    rd_en_r0 <= rd_en;
end

// 2-FF synchronizer (+1 stage for edge detect) into the SDRAM domain
reg rd_s0 = 0, rd_s1 = 0, rd_s2 = 0;
reg wr_s0 = 0, wr_s1 = 0, wr_s2 = 0;
always @(posedge clock_sdram) begin
    rd_s0 <= rd_en_r0; rd_s1 <= rd_s0; rd_s2 <= rd_s1;
    wr_s0 <= wr_en_r0; wr_s1 <= wr_s0; wr_s2 <= wr_s1;
end
wire rd_edge = rd_s1 && !rd_s2;
wire wr_edge = wr_s1 && !wr_s2;

// "accept" = the cycle the core enters a transaction (core_busy rising edge)
wire core_busy;
reg core_busy_d = 0;
always @(posedge clock_sdram) core_busy_d <= core_busy;
wire accept = core_busy && !core_busy_d;

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

assign busy = core_busy && (wr_en_r0 || rd_en_r0);

// ======================================================================
// SDRAM controller core (clock_sdram domain)
// ======================================================================
sdram_controller sdram_controlleri (
    /* HOST INTERFACE */
    .wr_addr       (addr_r),
    .wr_data       (wr_data_r),
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
