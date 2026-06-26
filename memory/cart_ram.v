// =============================================================================
//  cart_ram.v
//  Game Pak Cart RAM (battery-backed SRAM) — 64 KB, 8-bit port.
//
//  Memory map: 0x0E000000 - 0x0E00FFFF (also mirrored at 0x0F000000).
//  Per CowBite §3: 8-bit port, used for save data. Modeled here as on-chip
//  M10K — battery backing, flash erase semantics, etc. are out of scope.
//
//  CPU interface: byte-addressed, byte-only. The CPU bus controller is
//  responsible for splitting wider accesses into multiple byte transactions
//  and for any sign-extension after read.
//
//  Read timing:
//        cycle 0:  addr / we / wdata presented
//        cycle 1:  rdata valid
// =============================================================================

`timescale 1ns / 1ps

module cart_ram #(
    parameter DEPTH_POW2 = 16,                  // 2^16 = 65536 bytes = 64 KB
    parameter INIT_FILE  = "UNUSED"
)(
	input  wire                       clk,

    // CPU interface
    input  wire [DEPTH_POW2-1 : 0]    addr,           // byte address
    input  wire [31:0]                wdata,
    output reg  [31:0]                rdata,
    input  wire                       we,
    input  wire                       rden,
    input  wire [1:0]				  size,           // 0=byte 1=half
    input  wire                       sign_extend,

    // Status
    output wire                       ready,
    output reg                        misalign_fault
);

	localparam SIZE_BYTE = 2'b00;
    localparam SIZE_HALF = 2'b01;
    localparam SIZE_WORD = 2'b10;

	/////////////////////////////////////////////////////////////////////////////
	
	localparam NORMAL = 2'b00;
	localparam BYTE1  = 2'b01;
	localparam BYTE2  = 2'b10;
	localparam BYTE3  = 2'b11;
	
	reg [1:0] STATE 	 = NORMAL;
	reg [1:0] NEXT_STATE = NORMAL;
	reg	[1:0] beat = 2'b0;
	
	always @(posedge clk) begin
		STATE <= NEXT_STATE;
	end

	always @(*) begin
		case (STATE)
			NORMAL: begin
				beat = 2'b00;
				if (size != SIZE_BYTE && (rden = 1 || we == 1)) NEXT_STATE = BYTE1;
				else NEXT_STATE = NORMAL;
			end
			BYTE1: begin
				beat = 2'b01;
				if 	 (size == SIZE_HALF) NEXT_STATE = NORMAL;
				else NEXT_STATE = BYTE2;
			end
			BYTE2: begin
				beat = 2'b10;
				NEXT_STATE = BYTE3;
			end
			BYTE3: begin
				beat = 2'b11;
				NEXT_STATE = NORMAL;
			end
		endcase
	end
	
    // -------------------------------------------------------------------------
    //  Address split
    // -------------------------------------------------------------------------
	
    wire [DEPTH_POW2-1:0] byte_addr = (size == SIZE_HALF) ? {addr[DEPTH_POW2-1 : 1], beat[0]} :
									  (size == SIZE_WORD) ? {addr[DEPTH_POW2-1 : 2], beat} :
									  addr;

    // -------------------------------------------------------------------------
    //  Alignment check
    // -------------------------------------------------------------------------
    wire misalign_comb = ((size == SIZE_HALF) && addr[0]) || ((size == SIZE_WORD) && |addr[1:0]);
    assign ready = ~misalign_comb || ~(|beat);

    // -------------------------------------------------------------------------
    //  Write-data alignment
    // -------------------------------------------------------------------------
	
    reg [7:0] wdata_shifted;
    always @(*) begin
        case (beat)
            2'b00: wdata_shifted = wdata[7:0];
            2'b01: wdata_shifted = wdata[15:8];
            2'b10: wdata_shifted = wdata[23:16];
            2'b11: wdata_shifted = wdata[31:24];
        endcase
    end

    wire write_en = we & ~misalign_comb;

    // -------------------------------------------------------------------------
    //  M10K instance
    // -------------------------------------------------------------------------
    wire [7:0] read_data;

    M10K #(
        .WIDTH      (8),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) ram_inst (
        .addr    (byte_addr),
        .byteena (1'b1),
        .clk     (clk),
        .data    (wdata_shifted),
        .wren    (write_en),
        .rden    (rden),
        .q       (read_data)
    );

    // -------------------------------------------------------------------------
    //  Pipelined CPU-side qualifiers (line up with read_data)
    // -------------------------------------------------------------------------
	reg [7:0] read_data_q0, read_data_q1, read_data_q2	= 8'b0;
    reg	[1:0] size_q        = 2'b0;
    reg       byte_lane_q   = 1'b0;
    reg       sign_extend_q = 1'b0;
    reg       misalign_q    = 1'b0;
    reg       we_q          = 1'b0;

    always @(posedge clk) begin
		read_data_q0  <= read_data;
		read_data_q1  <= read_data_q0;
		read_data_q2  <= read_data_q1;
        size_q        <= size;
        byte_lane_q   <= byte_lane;
        sign_extend_q <= sign_extend;
        misalign_q    <= misalign_comb;
        we_q          <= we;
    end

    // -------------------------------------------------------------------------
    //  Output formatting (combinational on the registered read data)
    // -------------------------------------------------------------------------
    always @(*) begin
        case (size_q)
            SIZE_BYTE: rdata = sign_extend_q ? {{24{read_data[7]}}, read_data} : {24'h0, read_data};
            SIZE_HALF: rdata = sign_extend_q ? {{16{read_data_q0[15]}}, read_data, read_data_q0} : {16'h0, read_data, read_data_q0};
            SIZE_WORD: rdata = {read_data, read_data_q0, read_data_q1, read_data_q2};
            default:   rdata = 32'h0;
        endcase

        misalign_fault = misalign_q & we_q;
    end

endmodule
