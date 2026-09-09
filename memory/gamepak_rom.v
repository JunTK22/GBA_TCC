// =============================================================================
//  gamepak_rom.v
//  Read-only 128 KiB Game Pak ROM for the on-chip hw-test image path.
//
//  The host address is byte addressed. Storage is 16 bits wide, matching the
//  GBA cartridge data bus, and the low 17 address bits select the 128 KiB
//  image. The WS0/WS1/WS2 mirrors therefore read the same stored image.
//
//  GBATEK timing implemented here:
//    * WAITCNT first access:  4, 3, 2, or 8 waitstates.
//    * WAITCNT second access: WS0=2/1, WS1=4/1, WS2=8/1 waitstates.
//    * Each 16-bit transfer takes one base cycle plus its waitstates.
//    * A 32-bit transfer is two 16-bit transfers; its second half is normally
//      sequential. A DMA whose first ROM word starts exactly on a 128 KiB
//      boundary has a second N-timed half, as observed by hw-test.
//    * The first transfer at every 128 KiB boundary is non-sequential.
//    * The first Game Pak transfer within each DMA ownership is
//      non-sequential, even if earlier beats of that DMA used another region.
//    * DMA includes its bus base cycle locally because DMA consumes `ready`
//      directly; CPU accesses receive that base cycle from registered nWAIT.
//
//  Reads and writes both receive Game Pak bus timing. Writes never modify the
//  ROM contents, but they still hold `ready` low for the documented access
//  length. `request_toggle` changes once for every selected-master bus beat so
//  identical consecutive accesses remain distinguishable.
//
//  `ready` follows the project's local-memory convention. It is low as soon as
//  a new selected request is visible and rises after the required wait edges
//  and, for reads, the synchronous ROM access has completed. The top-level
//  registered nWAIT adds the documented base cycle. Keep the request payload
//  stable while ready is low.
//
//  `seq` must describe the selected bus master. CPU SEQ alone is insufficient
//  during DMA ownership. WAITCNT bit 14 enables an eight-halfword opcode
//  prefetch queue. It fills with sequential Game Pak cycles while the last
//  accepted CPU opcode came from ROM and the foreground bus is free; queued
//  opcode hits use zero waitstates. Foreground CPU or DMA traffic owns the
//  single M10K port and updates the internal mask-ROM halfword counter.
// =============================================================================

`timescale 1ns / 1ps

module gamepak_rom #(
    parameter INIT_FILE = "UNUSED"
)(
    input  wire        clk,
    input  wire        nrst,

    input  wire [27:0] addr,
    input  wire        rden,
    input  wire        wren,
    input  wire [1:0]  size,          // 00=byte, 01=halfword, 10=word
    input  wire        sign_extend,
    input  wire        seq,           // first half is sequential when allowed
    input  wire        opcode_fetch,  // selected CPU request is an opcode
    input  wire        cpu_exec_gamepak,
    input  wire        dma_access,    // selected request belongs to a DMA
    input  wire        request_toggle,
    input  wire [15:0] waitcnt,

    output wire [31:0] rdata,
    output wire        ready
);

localparam SIZE_BYTE = 2'b00;
localparam SIZE_WORD = 2'b10;

localparam FETCH_IDLE = 2'd0;
localparam FETCH_LOW  = 2'd1;
localparam FETCH_HIGH = 2'd2;

function [3:0] first_wait_count;
    input [1:0] setting;
    begin
        case (setting)
            2'b00: first_wait_count = 4'd4;
            2'b01: first_wait_count = 4'd3;
            2'b10: first_wait_count = 4'd2;
            default: first_wait_count = 4'd8;
        endcase
    end
endfunction

function [3:0] second_wait_count;
    input [2:0] region;
    input [15:0] wait_control;
    begin
        case (region)
            3'b101: second_wait_count = wait_control[7]  ? 4'd1 : 4'd4;
            3'b110: second_wait_count = wait_control[10] ? 4'd1 : 4'd8;
            default: second_wait_count = wait_control[4] ? 4'd1 : 4'd2;
        endcase
    end
endfunction

// Remember the complete request payload. The selected master changes the
// toggle on every accepted bus cycle, including identical fixed-address beats.
wire        access = rden || wren;
wire [35:0] request = {request_toggle, addr, size, sign_extend,
                       seq, opcode_fetch, rden, wren};
reg  [35:0] request_q = 36'd0;
wire        new_beat = access && (request != request_q);

always @(posedge clk or negedge nrst) begin
    if (!nrst)
        request_q <= 36'd0;
    else
        request_q <= request;
end

// WAITCNT selects independent N/S timings for the three ROM mirrors.
wire [2:0] wait_region = addr[27:25];
wire [1:0] first_wait_setting = (wait_region == 3'b101) ? waitcnt[6:5] :
                                (wait_region == 3'b110) ? waitcnt[9:8] :
                                                         waitcnt[3:2];
wire [3:0] nonseq_wait = first_wait_count(first_wait_setting);
wire [3:0] sequential_wait = second_wait_count(wait_region, waitcnt);

wire       request_word = size == SIZE_WORD;
wire [15:0] request_half_addr = request_word ?
                                    {addr[16:2], 1'b0} : addr[16:1];

// Mask ROMs latch the address on an N cycle, then use an internal halfword
// counter for S cycles. Every 16-bit cartridge bus cycle advances the counter,
// including writes and both halves of a word access. Counter wrap marks the
// 128 KiB boundary and forces the next transfer to re-latch the address pins.
reg  [15:0] rom_half_addr = 16'd0;
reg         dma_rom_seen = 1'b0;
wire        first_dma_rom_beat = dma_access && !dma_rom_seen;
wire        counter_sequential = seq && !first_dma_rom_beat &&
                                 (rom_half_addr != 16'd0);
wire        address_sequential = seq && (addr[16:0] != 17'd0);
wire        access_sequential = dma_access ? counter_sequential
                                           : address_sequential;
wire [15:0] launch_half_addr = (dma_access && counter_sequential)
                               ? rom_half_addr : request_half_addr;
wire [3:0] first_half_wait = access_sequential ? sequential_wait
                                                : nonseq_wait;

// The 128kb-boundary ROM distinguishes a DMA word which begins the first ROM
// access exactly at a boundary from one which arrives there later with SEQ
// already asserted. In the former case the first-DMA N cycle and boundary
// restart are separately visible, adding one N-versus-S halfword interval.
wire       first_dma_boundary_word = first_dma_rom_beat && !seq &&
                                     request_word &&
                                     (addr[16:0] == 17'd0);
wire [3:0] second_half_wait = first_dma_boundary_word ? nonseq_wait
                                                       : sequential_wait;

// -------------------------------------------------------------------------
//  Eight-halfword opcode prefetch queue
// -------------------------------------------------------------------------
reg [15:0] prefetch_data [0:7];
reg [15:0] prefetch_base_addr = 16'd0;
reg [2:0]  prefetch_region = 3'b100;
reg [3:0]  prefetch_count = 4'd0;
reg [3:0]  prefetch_wait_remaining = 4'd0;
reg        prefetch_busy = 1'b0;
reg        prefetch_hit_r = 1'b0;
reg [31:0] prefetch_hit_data_r = 32'd0;

wire prefetch_half_hit = opcode_fetch && rden &&
                         (size != SIZE_WORD) &&
                         (addr[27:25] == prefetch_region) &&
                         (prefetch_count >= 1) &&
                         (request_half_addr == prefetch_base_addr);
wire prefetch_word_hit = opcode_fetch && rden && request_word &&
                         (addr[27:25] == prefetch_region) &&
                         (prefetch_count >= 2) &&
                         (request_half_addr == prefetch_base_addr);
wire prefetch_hit = waitcnt[14] &&
                    (prefetch_half_hit || prefetch_word_hit);

wire [15:0] prefetch_fill_addr = prefetch_base_addr + prefetch_count +
                                 (prefetch_busy ? 16'd1 : 16'd0);
wire [3:0] prefetch_fill_wait = (prefetch_fill_addr == 16'd0) ?
        first_wait_count((prefetch_region == 3'b101) ? waitcnt[6:5] :
                         (prefetch_region == 3'b110) ? waitcnt[9:8] :
                                                      waitcnt[3:2]) :
        second_wait_count(prefetch_region, waitcnt);
wire prefetch_can_start = waitcnt[14] && cpu_exec_gamepak && !access &&
                          !prefetch_busy && (prefetch_count < 8);
wire prefetch_can_chain = waitcnt[14] && cpu_exec_gamepak && !access &&
                          prefetch_busy &&
                          (prefetch_wait_remaining == 1) &&
                          (prefetch_count < 7);
wire prefetch_rom_request = prefetch_can_start || prefetch_can_chain;

// The external nWAIT register contributes the first base cycle for CPU
// accesses. DMA consumes `ready` directly, so include that base cycle in this
// threshold instead. A word always needs one additional threshold edge for its
// second base cycle: (1+first_wait) + (1+second_wait).
wire [4:0] dma_base_wait = dma_access ? 5'd1 : 5'd0;
wire [4:0] required_wait_at_launch = request_word ?
        ({1'b0, first_half_wait} + {1'b0, second_half_wait} + 5'd1 +
         dma_base_wait) :
        ({1'b0, first_half_wait} + dma_base_wait);

reg [1:0]  fetch_state = FETCH_IDLE;
reg [27:0] addr_r = 28'd0;
reg [1:0]  size_r = 2'd0;
reg        sign_extend_r = 1'b0;
reg        read_r = 1'b0;
reg        word_r = 1'b0;
reg [15:0] base_half_addr_r = 16'd0;
reg [15:0] low_half_r = 16'd0;
reg [4:0]  required_wait_r = 5'd0;
reg [4:0]  wait_edges = 5'd0;

wire        normal_new_beat = new_beat && !prefetch_hit;
wire        fetch_second_half = !new_beat && !prefetch_hit_r &&
                                read_r && word_r &&
                                (fetch_state == FETCH_LOW);
wire [15:0] rom_addr = normal_new_beat ? launch_half_addr :
                       fetch_second_half ? (base_half_addr_r + 1'b1) :
                       prefetch_rom_request ? prefetch_fill_addr :
                                              base_half_addr_r;
wire        rom_rden = (normal_new_beat && rden) || fetch_second_half ||
                       prefetch_rom_request;
wire [15:0] rom_q;

M10K #(
    .WIDTH      (16),
    .DEPTH_POW2 (16),
    .INIT_FILE  (INIT_FILE)
) gamepak_storage (
    .addr    (rom_addr),
    .byteena (2'b11),
    .clk     (clk),
    .data    (16'd0),
    .wren    (1'b0),
    .rden    (rom_rden),
    .q       (rom_q)
);

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        rom_half_addr <= 16'd0;
        dma_rom_seen <= 1'b0;
    end else begin
        if (!dma_access)
            dma_rom_seen <= 1'b0;
        else if (normal_new_beat)
            dma_rom_seen <= 1'b1;

        if (normal_new_beat) begin
            rom_half_addr <= launch_half_addr +
                             (request_word ? 16'd2 : 16'd1);
        end else if (prefetch_rom_request) begin
            rom_half_addr <= prefetch_fill_addr + 16'd1;
        end
    end
end

integer prefetch_index;
always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        prefetch_base_addr <= 16'd0;
        prefetch_region <= 3'b100;
        prefetch_count <= 4'd0;
        prefetch_wait_remaining <= 4'd0;
        prefetch_busy <= 1'b0;
        for (prefetch_index = 0; prefetch_index < 8;
             prefetch_index = prefetch_index + 1)
            prefetch_data[prefetch_index] <= 16'd0;
    end else if (!waitcnt[14]) begin
        prefetch_count <= 4'd0;
        prefetch_wait_remaining <= 4'd0;
        prefetch_busy <= 1'b0;
    end else if (new_beat) begin
        // Any foreground Game Pak request owns the single ROM port. A new
        // opcode either consumes the queue head or starts a new stream.
        prefetch_busy <= 1'b0;
        prefetch_wait_remaining <= 4'd0;
        if (opcode_fetch && rden) begin
            prefetch_region <= addr[27:25];
            if (prefetch_hit) begin
                if (request_word) begin
                    for (prefetch_index = 0; prefetch_index < 6;
                         prefetch_index = prefetch_index + 1)
                        prefetch_data[prefetch_index] <=
                            prefetch_data[prefetch_index + 2];
                    prefetch_base_addr <= prefetch_base_addr + 16'd2;
                    prefetch_count <= prefetch_count - 4'd2;
                end else begin
                    for (prefetch_index = 0; prefetch_index < 7;
                         prefetch_index = prefetch_index + 1)
                        prefetch_data[prefetch_index] <=
                            prefetch_data[prefetch_index + 1];
                    prefetch_base_addr <= prefetch_base_addr + 16'd1;
                    prefetch_count <= prefetch_count - 4'd1;
                end
            end else begin
                prefetch_base_addr <= request_half_addr +
                                      (request_word ? 16'd2 : 16'd1);
                prefetch_count <= 4'd0;
            end
        end
    end else if (!cpu_exec_gamepak) begin
        prefetch_count <= 4'd0;
        prefetch_wait_remaining <= 4'd0;
        prefetch_busy <= 1'b0;
    end else if (access) begin
        prefetch_busy <= 1'b0;
        prefetch_wait_remaining <= 4'd0;
    end else if (prefetch_busy) begin
        if (prefetch_wait_remaining > 1) begin
            prefetch_wait_remaining <= prefetch_wait_remaining - 1'b1;
        end else begin
            // rom_q is the halfword requested when this background cycle
            // started. The combinational port mux may launch the next fill on
            // this same edge, with no artificial bubble between S cycles.
            prefetch_data[prefetch_count] <= rom_q;
            prefetch_count <= prefetch_count + 1'b1;
            if (prefetch_count < 7) begin
                prefetch_busy <= 1'b1;
                prefetch_wait_remaining <= prefetch_fill_wait;
            end else begin
                prefetch_busy <= 1'b0;
                prefetch_wait_remaining <= 4'd0;
            end
        end
    end else if (prefetch_can_start) begin
        prefetch_busy <= 1'b1;
        prefetch_wait_remaining <= prefetch_fill_wait;
    end
end

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        fetch_state     <= FETCH_IDLE;
        addr_r          <= 28'd0;
        size_r          <= 2'd0;
        sign_extend_r   <= 1'b0;
        read_r           <= 1'b0;
        word_r          <= 1'b0;
        base_half_addr_r <= 16'd0;
        low_half_r      <= 16'd0;
        required_wait_r <= 5'd0;
        wait_edges      <= 5'd0;
        prefetch_hit_r  <= 1'b0;
        prefetch_hit_data_r <= 32'd0;
    end else if (!access) begin
        fetch_state <= FETCH_IDLE;
        wait_edges  <= 5'd0;
        prefetch_hit_r <= 1'b0;
    end else if (new_beat) begin
        addr_r           <= addr;
        size_r           <= size;
        sign_extend_r    <= sign_extend;
        word_r           <= request_word;
        if (prefetch_hit) begin
            fetch_state <= FETCH_IDLE;
            read_r <= 1'b0;
            wait_edges <= 5'd0;
            prefetch_hit_r <= 1'b1;
            prefetch_hit_data_r <= request_word
                                   ? {prefetch_data[1], prefetch_data[0]}
                                   : {16'd0, prefetch_data[0]};
        end else begin
            fetch_state      <= FETCH_LOW;
            read_r           <= rden;
            base_half_addr_r <= launch_half_addr;
            required_wait_r  <= required_wait_at_launch;
            wait_edges       <= 5'd1;
            prefetch_hit_r   <= 1'b0;
        end
    end else if (!prefetch_hit_r) begin
        if (wait_edges != 5'd31)
            wait_edges <= wait_edges + 1'b1;

        // During FETCH_LOW the ROM output contains the first halfword and the
        // ROM port is simultaneously sampling the second word address.
        if (word_r && (fetch_state == FETCH_LOW)) begin
            if (read_r)
                low_half_r <= rom_q;
            fetch_state <= FETCH_HIGH;
        end
    end
end

wire data_available = !read_r ||
                      (!word_r && (fetch_state == FETCH_LOW)) ||
                      ( word_r && (fetch_state == FETCH_HIGH));
wire timing_ready = wait_edges >= required_wait_r;

assign ready = !access || prefetch_hit || prefetch_hit_r ||
               (!new_beat && data_available && timing_ready);

wire [7:0] byte_value = addr_r[0] ? rom_q[15:8] : rom_q[7:0];
wire [31:0] byte_result = sign_extend_r ?
                          {{24{byte_value[7]}}, byte_value} :
                          {24'd0, byte_value};
wire [31:0] half_result = sign_extend_r ?
                          {{16{rom_q[15]}}, rom_q} :
                          {16'd0, rom_q};

assign rdata = prefetch_hit_r ? prefetch_hit_data_r :
               word_r            ? {rom_q, low_half_r} :
               (size_r == SIZE_BYTE) ? byte_result : half_result;

endmodule
