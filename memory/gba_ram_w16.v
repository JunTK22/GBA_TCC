// =============================================================================
//  gba_ram_w16.v
//  16-bit-port ARM-bus RAM template (M10K-backed).
//
//  Used by GBA memory regions whose port size is 16 bits per CowBite §3:
//    EWRAM (256 KB), VRAM (96 KB rounded to 128 KB), Palette RAM (1 KB).
//
//  CPU interface:
//    addr   — byte address (DEPTH_POW2+1 bits wide).
//    size   — 0 = byte, 1 = halfword.
//    The CPU bus controller is responsible for issuing two transactions for
//    32-bit accesses on this 16-bit port.
//
//  Behaviour:
//    1-cycle read latency. Byte accesses optionally sign-extend to 16 bits.
//    Halfword accesses must be 2-byte aligned; misaligned halfword sets
//    misalign_fault on the next cycle (paired with we_q for write faults)
//    and `ready` deasserts the same cycle.
//
//  Implementation follows the same M10K-inferable pattern as sram.v: storage
//  and the synchronous read register live in the M10K instance, all ARM
//  size/sign-extension logic operates on the registered output one stage
//  later.
// =============================================================================

`timescale 1ns / 1ps

module gba_ram_w16 #(
    parameter DEPTH_POW2 = 9,                 // 2^DEPTH_POW2 halfwords
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire                       clk,

    // CPU interface
    input  wire [DEPTH_POW2 : 0]      addr,           // byte address
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
	
	localparam NORMAL = 1'b0;
	localparam WORD   = 1'b1;
	
	reg STATE 	   = NORMAL;
	reg NEXT_STATE = NORMAL;
	reg	beat = 0;
	
	always @(posedge clk) begin
		STATE <= NEXT_STATE;
	end

	always @(*) begin
		case (STATE)
			NORMAL: begin
				beat = 0;
				if (size == SIZE_WORD && (rden = 1 || we == 1)) NEXT_STATE = WORD;
				else NEXT_STATE = NORMAL;
			end
			WORD: begin
				beat = 1;
				NEXT_STATE = NORMAL;
			end
		endcase
	end

    // -------------------------------------------------------------------------
    //  Address split
    // -------------------------------------------------------------------------
    wire [DEPTH_POW2-1:0] hword_addr = (size == SIZE_WORD) ? {addr[DEPTH_POW2 : 2], beat} : addr[DEPTH_POW2 : 1];
    wire                  byte_lane  = addr[0];

    // -------------------------------------------------------------------------
    //  Alignment check
    // -------------------------------------------------------------------------
    wire misalign_comb = ((size == SIZE_HALF) && addr[0]) || ((size == SIZE_WORD) && |addr[1:0]);
    assign ready = ~misalign_comb || ~beat;

    // -------------------------------------------------------------------------
    //  Byte-enable generation
    // -------------------------------------------------------------------------
    reg [1:0] byteena;
    always @(*) begin
        case (size)
            SIZE_BYTE: byteena = byte_lane ? 2'b10 : 2'b01;
            SIZE_HALF: byteena = 2'b11;
            SIZE_WORD: byteena = 2'b11;
            default:   byteena = 2'b00;
        endcase
    end

    // -------------------------------------------------------------------------
    //  Write-data alignment: replicate byte into both lanes; byteena selects.
    // -------------------------------------------------------------------------
    reg [15:0] wdata_shifted;
    always @(*) begin
        case (size)
            SIZE_BYTE: wdata_shifted = {2{wdata[7:0]}};
            SIZE_HALF: wdata_shifted = wdata[15:0];
            SIZE_WORD: wdata_shifted = beat ? wdata[31:16] : wdata[15:0];
            default:   wdata_shifted = 16'h0;
        endcase
    end

    wire write_en = we & ~misalign_comb;

    // -------------------------------------------------------------------------
    //  M10K instance
    // -------------------------------------------------------------------------
    wire [15:0] read_data;

    M10K #(
        .WIDTH      (16),
        .DEPTH_POW2 (DEPTH_POW2),
        .INIT_FILE  (INIT_FILE)
    ) ram_inst (
        .addr    (hword_addr),
        .byteena (byteena),
        .clk     (clk),
        .data    (wdata_shifted),
        .wren    (write_en),
        .rden    (rden),
        .q       (read_data)
    );

    // -------------------------------------------------------------------------
    //  Pipelined CPU-side qualifiers (line up with read_data)
    // -------------------------------------------------------------------------
	reg [15:0]read_data_q	= 16'b0;
    reg	[1:0] size_q        = 2'b0;
    reg       byte_lane_q   = 1'b0;
    reg       sign_extend_q = 1'b0;
    reg       misalign_q    = 1'b0;
    reg       we_q          = 1'b0;

    always @(posedge clk) begin
		read_data_q	  <= read_data;
        size_q        <= size;
        byte_lane_q   <= byte_lane;
        sign_extend_q <= sign_extend;
        misalign_q    <= misalign_comb;
        we_q          <= we;
    end

    // -------------------------------------------------------------------------
    //  Output formatting (combinational on the registered read data)
    // -------------------------------------------------------------------------
    reg [7:0] byte_sel;
    always @(*) begin
        byte_sel = byte_lane_q ? read_data[15:8] : read_data[7:0];

        case (size_q)
            SIZE_BYTE: rdata = sign_extend_q ? {{24{byte_sel[7]}}, byte_sel} : {24'h0, byte_sel};
            SIZE_HALF: rdata = sign_extend_q ? {{16{read_data[15]}}, read_data} : {16'h0, read_data};
            SIZE_WORD: rdata = {read_data, read_data_q};
            default:   rdata = 32'h0;
        endcase

        misalign_fault = misalign_q & we_q;
    end

endmodule
