// =============================================================================
//  dma.v
//  Single GBA-style DMA channel transfer engine.
//
//  Consumes DMAxSAD/DAD/CNT_L/CNT_H register values from `io_registers`, emits
//  source/destination addresses, transfer size (`MAS`), write-phase flag,
//  sequential-cycle qualifier, bus-request/active status, completion disable,
//  and an active-low completion IRQ.
//  The first source and destination units are non-sequential; later units are
//  sequential, independently for each side of the alternating DMA bus cycle.
//  The per-channel 32-bit data latch implements invalid-source/open-bus behavior
//  and duplicates valid 16-bit reads across both lanes.
//
//  Enable has two elapsed activation cycles. Immediate DMA then enters
//  DMA_START; timed DMA waits in DMA_ARMED with its internal SAD/DAD/count
//  already loaded. A CPU access already in flight completes before ownership
//  changes; a newly presented CPU request remains held. DMA_END supplies the
//  final bus-idle internal cycle, requests CNT_H enable-bit clear, and
//  optionally pulses the active-low IRQ. Immediate, VBlank, HBlank, and
//  channel-qualified special starts are inputs from the synthesis top.
//  `halt == 1` freezes a memory wait; `priority_hold` pauses a lower-priority
//  channel without repeating its held bus phase.
// =============================================================================

module dma(
    input wire          clock,
    input wire  [31:0]  dmasad_o, dmadad_o,
    input wire  [15:0]  dmacnt_l_o, dmacnt_h_o,
    input wire  [31:0]  data_i,
    input wire          vblank, hblank, special,
    input wire          halt,
    input wire          priority_hold,
    input wire          cpu_cycle_accepted,

    output reg  [31:0]  src_addr,
    output reg  [31:0]  dst_addr,
    output reg  [31:0]  data_o = 0,
    output reg          wr_en = 0,
    output reg          seq = 0,
    output reg  [1:0]   MAS = 2'b10,
    output wire         dma_pending,
    output wire         dma_request,
    output wire         dma_disable,
    output reg          dma_active = 0,
    output reg          nIRQ = 1
);

localparam IDLE     = 3'd0;
localparam DMA_SET  = 3'd1;
localparam LOAD     = 3'd2;
localparam STORE    = 3'd3;
localparam DMA_END  = 3'd4;
localparam DMA_WAIT = 3'd5;
localparam DMA_START = 3'd6;
localparam DMA_ARMED = 3'd7;

reg [13:0] transf_count = 0;
reg        source_seq = 0;
reg        destination_seq = 0;
reg        startup_waiting = 0;
reg [31:0] data_latch = 0;

reg [1:0] ctrl_src = 0;         // 0=Increment,1=Decrement,2=Fixed,3=Prohibited
reg [1:0] ctrl_dst = 0;         // 0=Increment,1=Decrement,2=Fixed,3=Increment/Reload
reg       ctrl_repeat = 0;      // 0=Off, 1=On
reg       ctrl_type = 0;        // 0=16bit, 1=32bit
reg       ctrl_gpak_drq = 0;    // DMA3 only -  (0=Normal, 1=DRQ <from> Game Pak, DMA3)
reg [1:0] ctrl_timing = 0;      // 0=Immediately, 1=VBlank, 2=HBlank, 3=Special
                                // The 'Special' setting (Start Timing=3) depends on the DMA channel:
                                // DMA0=Prohibited, DMA1/DMA2=Sound FIFO, DMA3=Video Capture
reg       ctrl_irq = 0;         // 0=Disable, 1=Enable
wire      dma_en = dmacnt_h_o[15];

reg [2:0] STATE      = IDLE;
reg [2:0] NEXT_STATE = IDLE;

// DMA enable has a two-cycle activation delay followed by one internal startup
// cycle. A CPU access which was already stalled when that delay expired must
// complete before DMA takes the bus; a new CPU access is held in DMA_START.
assign dma_pending = (STATE == DMA_START) && !startup_waiting;
assign dma_request = dma_active && !priority_hold &&
                     ((STATE == LOAD) || (STATE == STORE));
assign dma_disable = (STATE == DMA_END) &&
                     ((ctrl_timing == 2'b0) || !ctrl_repeat);
wire enable_delay_state = (STATE == DMA_WAIT) || (STATE == DMA_SET);
wire transfer_hold = halt || priority_hold;
wire timed_start = ((ctrl_timing == 2'b01) && vblank) ||
                   ((ctrl_timing == 2'b10) && hblank) ||
                   ((ctrl_timing == 2'b11) && special);
wire capture_timed_start = (STATE == DMA_ARMED) && timed_start;

always @(posedge clock) begin
    // The enable delay is elapsed time, not a memory transaction. Count it
    // while an in-flight CPU access is waiting; DMA_START still waits for that
    // access to become ready before changing bus ownership.
    if (!transfer_hold || enable_delay_state || capture_timed_start)
        STATE <= NEXT_STATE;
    else STATE <= STATE;
end

always @(*) begin
    case (STATE)
        IDLE: begin
            NEXT_STATE = dma_en ? DMA_WAIT : IDLE;
        end
        DMA_WAIT: begin
            NEXT_STATE = dma_en ? DMA_SET : IDLE;
        end
        DMA_SET: begin
            if (!dma_en)
                NEXT_STATE = IDLE;
            else if (dmacnt_h_o[13:12] == 2'b00)
                NEXT_STATE = DMA_START;
            else
                NEXT_STATE = DMA_ARMED;
        end
        DMA_ARMED: begin
            if (!dma_en)
                NEXT_STATE = IDLE;
            else
                NEXT_STATE = timed_start ? DMA_START : DMA_ARMED;
        end
        DMA_START: begin
            NEXT_STATE = startup_waiting ? DMA_START : LOAD;
        end
        LOAD: begin
            NEXT_STATE = STORE;
        end
        STORE: begin
            NEXT_STATE = transf_count == 14'b0 ? DMA_END : LOAD;
        end
        DMA_END: begin
            NEXT_STATE = (ctrl_repeat && (ctrl_timing != 2'b00) && dma_en)
                       ? DMA_ARMED : IDLE;
        end
        default: NEXT_STATE = STATE;
    endcase
end

always @(posedge clock) begin
    // DMA_SET must latch the programmed registers even if the CPU request that
    // overlaps the enable delay is still holding the shared ready path low.
    if (!transfer_hold || (STATE == DMA_SET)) begin
        case (STATE)
            IDLE: begin
                src_addr <= 32'b0;
                dst_addr <= 32'b0;
                data_o <= 32'b0;
                wr_en <= 0;
                seq <= 0;
                MAS <= 2'b10;
                dma_active <= 0;
                nIRQ <= 1;
                source_seq <= 0;
                destination_seq <= 0;
                startup_waiting <= 0;
            end
            DMA_SET: begin
                src_addr <= dmasad_o;
                dst_addr <= dmadad_o;
                transf_count <= dmacnt_l_o[13:0];
                ctrl_dst    <= dmacnt_h_o[6:5];
                ctrl_src    <= dmacnt_h_o[8:7];
                ctrl_repeat <= dmacnt_h_o[9];
                ctrl_type   <= dmacnt_h_o[10];
                ctrl_gpak_drq <= dmacnt_h_o[11];
                ctrl_timing <= dmacnt_h_o[13:12];
                ctrl_irq    <= dmacnt_h_o[14];
                seq <= 0;
                MAS <= dmacnt_h_o[10] ? 2'b10 : 2'b01;
                source_seq <= 0;
                destination_seq <= 0;
                startup_waiting <= (dmacnt_h_o[13:12] == 2'b00) &&
                                   halt && !cpu_cycle_accepted;
            end
            DMA_ARMED: begin
                dma_active <= 0;
                wr_en <= 0;
                seq <= 0;
                nIRQ <= 1;
                if (timed_start)
                    startup_waiting <= halt && !cpu_cycle_accepted;
            end
            DMA_START: begin
                if (startup_waiting) begin
                    if (cpu_cycle_accepted)
                        startup_waiting <= 0;
                end else begin
                    dma_active <= 1;
                    wr_en <= 0;
                    seq <= 0;
                end
            end
            LOAD: begin
                case (ctrl_src)
                    2'b00: src_addr <= ctrl_type ? src_addr + 32'd4 : src_addr + 32'd2; 
                    2'b01: src_addr <= ctrl_type ? src_addr - 32'd4 : src_addr - 32'd2; 
                    2'b10: src_addr <= src_addr; 
                    2'b11: src_addr <= ctrl_type ? src_addr + 32'd4 : src_addr + 32'd2; // is illegal
                endcase

                // Each DMA channel owns a 32-bit bus latch. Reads below
                // 0x02000000 do not update it; a 16-bit valid read duplicates
                // the halfword into both lanes. Invalid 16-bit reads select a
                // lane from the old latch according to destination alignment.
                if (src_addr[27:24] >= 4'h2) begin
                    data_latch <= ctrl_type ? data_i
                                            : {2{data_i[15:0]}};
                    data_o <= ctrl_type ? data_i : {16'd0, data_i[15:0]};
                end else begin
                    data_latch <= data_latch;
                    data_o <= ctrl_type ? data_latch
                                        : {16'd0, dst_addr[1]
                                                   ? data_latch[31:16]
                                                   : data_latch[15:0]};
                end
                transf_count <= transf_count - 14'b1;
                wr_en    <= 1;
                seq      <= destination_seq;
                source_seq <= 1'b1;
            end
            STORE: begin
                case (ctrl_dst)
                    2'b00: dst_addr <= ctrl_type ? dst_addr + 32'd4 : dst_addr + 32'd2; 
                    2'b01: dst_addr <= ctrl_type ? dst_addr - 32'd4 : dst_addr - 32'd2; 
                    2'b10: dst_addr <= dst_addr; 
                    2'b11: dst_addr <= ctrl_type ? dst_addr + 32'd4 : dst_addr + 32'd2; 
                    default:;
                endcase
                wr_en <= 0;
                seq <= source_seq;
                destination_seq <= 1'b1;
            end
            DMA_END: begin
                wr_en <= 0;
                seq   <= 0;
                dma_active <= 0;
                nIRQ   <= !ctrl_irq;
                if (ctrl_repeat && (ctrl_timing != 2'b00)) begin
                    transf_count <= dmacnt_l_o[13:0];
                    if (ctrl_dst == 2'b11)
                        dst_addr <= dmadad_o;
                end
            end
        endcase
    end
end

endmodule
