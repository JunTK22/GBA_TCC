module dma #(
    parameter DMA_Control_Register_Addr = 32'h0400_00BA // DMA0: 0x040000BA | DMA1: 0x040000C6 | DMA2: 0x040000D2 | DMA3: 0x040000DE
)(
    input wire          clock,
    input wire  [31:0]  dmasad_o, dmadad_o,
    input wire  [15:0]  dmacnt_l_o, dmacnt_h_o,
    input wire  [31:0]  data_i,
    input wire          vblank, hblank,
    input wire          halt,

    output reg  [31:0]  src_addr,
    output reg  [31:0]  dst_addr,
    output reg  [31:0]  data_o = 0,
    output reg          wr_en = 0,
    output reg  [1:0]   MAS = 2'b10,
    output reg          dma_active = 0,
    output reg          nIRQ = 1
);

localparam IDLE     = 3'd0;
localparam DMA_SET  = 3'd1;
localparam LOAD     = 3'd2;
localparam STORE    = 3'd3;
localparam DMA_END  = 3'd4;

reg [13:0] transf_count = 0;

reg [1:0] ctrl_src = 0;         // 0=Increment,1=Decrement,2=Fixed,3=Increment/Reload
reg [1:0] ctrl_dst = 0;         // 0=Increment,1=Decrement,2=Fixed,3=Prohibited
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

always @(posedge clock) begin
    if (!halt) STATE <= NEXT_STATE;
    else STATE <= STATE;
end

always @(*) begin
    case (STATE)
        IDLE: begin
            if (dma_en) begin
                case (dmacnt_h_o[13:12])
                    2'b00: NEXT_STATE = DMA_SET; 
                    2'b01: NEXT_STATE = vblank ? DMA_SET : IDLE; 
                    2'b10: NEXT_STATE = hblank ? DMA_SET : IDLE; 
                    2'b11: NEXT_STATE = vblank ? DMA_SET : IDLE; // to-do
                endcase
            end else NEXT_STATE = IDLE;
        end
        DMA_SET: begin
            NEXT_STATE = LOAD;
        end
        LOAD: begin
            NEXT_STATE = STORE;
        end
        STORE: begin
            NEXT_STATE = transf_count == 14'b0 ? DMA_END : LOAD;
        end
        DMA_END: begin
            NEXT_STATE = IDLE;
        end
        default: NEXT_STATE = STATE;
    endcase
end

always @(posedge clock) begin
    if (!halt) begin
        case (STATE)
            IDLE: begin
                src_addr <= 32'b0;
                dst_addr <= 32'b0;
                data_o <= 32'b0;
                wr_en <= 0;
                MAS <= 2'b10;
                dma_active <= 0;
                nIRQ <= 1;
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
                dma_active <= 1;
                MAS <= dmacnt_h_o[10] ? 2'b10 : 2'b01;
            end
            LOAD: begin
                case (ctrl_src)
                    2'b00: src_addr <= ctrl_type ? src_addr + 32'd4 : src_addr + 32'd2; 
                    2'b01: src_addr <= ctrl_type ? src_addr - 32'd4 : src_addr - 32'd2; 
                    2'b10: src_addr <= src_addr; 
                    2'b11: src_addr <= ctrl_type ? src_addr + 32'd4 : src_addr + 32'd2; // is illegal
                endcase

                data_o <= ctrl_type ? data_i : {16'b0, data_i[15:0]};
                transf_count <= transf_count - 14'b1;
                wr_en    <= 1;
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
            end
            DMA_END: begin
                dst_addr <= DMA_Control_Register_Addr;
                data_o <= {17'b0,dmacnt_h_o[14:0]};
                wr_en <= ctrl_timing == 2'b0 ? 1'b1 : !ctrl_repeat;
                MAS   <= 2'b01;
                nIRQ   <= !ctrl_irq;
            end
        endcase
    end
end

endmodule