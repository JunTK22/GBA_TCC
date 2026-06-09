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
//
// Clock-domain-crossing host wrapper for sdram_controller.
//
// The sdram_controller core runs in the clock_sdram domain and holds
// exactly one transaction in flight (busy is high for the whole
// ACT -> CAS -> READ/WRIT sequence; it samples rd_enable/wr_enable as a
// level only while in IDLE). The CPU side runs in the slower `clock`
// domain. A toggle req/ack handshake carries one request across and
// brings completion back, so a single CPU request issues EXACTLY ONE
// SDRAM transaction regardless of how long rd_en/wr_en is held.
//
// CPU-side contract (clock domain):
//   - Present addr (+ wr_data for writes) and assert rd_en or wr_en.
//     The request is taken on the rising edge of (rd_en | wr_en);
//     wr_en wins if both are asserted on the same edge.
//   - `ready` is low while a transaction is in flight and returns high
//     when it completes; for reads, rd_data is valid on the cycle ready
//     goes high. The CPU/bus MUST stall (e.g. via nWAIT) while ready==0.
//
//////////////////////////////////////////////////////////////////////

module sdram_controller_top (
    input   wire        clock,        // CPU / core frequency
    input   wire        clock_sdram,  // SDRAM frequency
    input   wire        nrst,

    input   wire        rd_en,
    input   wire        wr_en,

	input   wire [24:0] addr,
    input   wire [15:0] wr_data,
    output  wire [15:0] rd_data,
    output  wire        ready,

    output  wire [12:0] SA,
    output  wire [1:0]  BA,
    output  wire        CS_N,
    output  wire        CKE,
    output  wire        RAS_N,
    output  wire        CAS_N,
    output  wire        WE_N,
    output  wire [15:0] DQ,
    output  wire [1:0]  DQM
);

// ---- shared / core-facing nets ---------------------------------------
wire        core_busy;
wire        core_rd_ready;
wire [15:0] rd_data_i;

// ---- CPU clock domain registers --------------------------------------
reg  [24:0] addr_h;
reg  [15:0] wr_data_h;
reg  [15:0] rd_data_h;
reg         we_h;        // 1 = write, 0 = read
reg         busy_cpu;
reg         req_tgl;     // toggles once per accepted request
reg         rd_en_d, wr_en_d;
reg         ack_s1, ack_s2, ack_s3;   // ack toggle synchronizer (2 FF) + edge tap

// ---- SDRAM clock domain registers ------------------------------------
localparam W_IDLE = 2'd0,
           W_REQ  = 2'd1,
           W_RUN  = 2'd2;

reg  [1:0]  wstate;
reg         core_rd_en, core_wr_en;
reg         ack_tgl;
reg  [15:0] rd_data_s;
reg         req_s1, req_s2, req_s3;   // req toggle synchronizer (2 FF) + edge tap

// ======================================================================
// CPU clock domain
// ======================================================================
wire start    = ((rd_en & ~rd_en_d) | (wr_en & ~wr_en_d)) & ~busy_cpu;
wire ack_edge = ack_s2 ^ ack_s3; // XOR for edge detection

always @(posedge clock or negedge nrst) begin
    if (!nrst) begin
        addr_h    <= 25'b0;
        wr_data_h <= 16'b0;
        rd_data_h <= 16'b0;
        we_h      <= 1'b0;
        busy_cpu  <= 1'b0;
        req_tgl   <= 1'b0;
        rd_en_d   <= 1'b0;
        wr_en_d   <= 1'b0;
        {ack_s3, ack_s2, ack_s1} <= 3'b0;
    end else begin
        rd_en_d <= rd_en;
        wr_en_d <= wr_en;
        {ack_s3, ack_s2, ack_s1} <= {ack_s2, ack_s1, ack_tgl};

        if (start) begin
            addr_h    <= addr;
            wr_data_h <= wr_data;
            we_h      <= wr_en;     // wr_en wins if both asserted
            req_tgl   <= ~req_tgl;
            busy_cpu  <= 1'b1;
        end else if (ack_edge) begin
            rd_data_h <= rd_data_s; // stable data, qualified by synchronized ack
            busy_cpu  <= 1'b0;
        end
    end
end

assign rd_data = rd_data_h;
assign ready   = ~busy_cpu & ~start;   // ~start avoids a false 'ready' on the accept cycle

// ======================================================================
// SDRAM clock domain
// ======================================================================
wire req_edge = req_s2 ^ req_s3; // XOR for edge detection

always @(posedge clock_sdram or negedge nrst) begin
    if (!nrst) begin
        wstate     <= W_IDLE;
        core_rd_en <= 1'b0;
        core_wr_en <= 1'b0;
        ack_tgl    <= 1'b0;
        rd_data_s  <= 16'b0;
        {req_s3, req_s2, req_s1} <= 3'b0;
    end else begin
        {req_s3, req_s2, req_s1} <= {req_s2, req_s1, req_tgl};

        case (wstate)
            W_IDLE:
                if (req_edge) begin
                    // we_h / addr_h / wr_data_h are stable in the CPU domain
                    // (held by busy_cpu) before req crosses, so sampling them
                    // here is a safe data-with-synchronized-qualifier crossing.
                    core_rd_en <= ~we_h;
                    core_wr_en <=  we_h;
                    wstate     <= W_REQ;
                end

            // Hold the enable as a level until the core accepts it (busy
            // rises). This lets the core finish init or insert a pending
            // refresh first, then take this command exactly once.
            W_REQ:
                if (core_busy) begin
                    core_rd_en <= 1'b0;
                    core_wr_en <= 1'b0;
                    wstate     <= W_RUN;
                end

            // For reads, rd_ready pulses one cycle before busy falls, so the
            // capture and the ack are separate, consecutive conditionals.
            W_RUN: begin
                if (core_rd_ready)
                    rd_data_s <= rd_data_i;
                if (!core_busy) begin
                    ack_tgl <= ~ack_tgl;
                    wstate  <= W_IDLE;
                end
            end

            default: wstate <= W_IDLE;
        endcase
    end
end

// ======================================================================
// SDRAM controller core (clock_sdram domain)
// ======================================================================
sdram_controller sdram_controlleri (
    /* HOST INTERFACE */
    .wr_addr       (addr_h),
    .wr_data       (wr_data_h),
    .wr_enable     (core_wr_en),

    .rd_addr       (addr_h),
    .rd_data       (rd_data_i),
    .rd_ready      (core_rd_ready),
    .rd_enable     (core_rd_en),

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
