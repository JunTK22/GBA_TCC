module lcd_writer_fifo #(
    parameter integer NBUF = 32,    // number of row buffers; MUST be a power of 2 and >= 4
    parameter integer COLS = 240    // pixels per source row (GBA width)
) (
    input  wire clk_W,          // PPU-side write clock
    input  wire clk_R,          // LCD-side read clock
    input  wire nrst,
    input  wire nEN,            // active-low global enable

    input  wire [15:0] pixel_i, // captured source pixel (already RGB565)
    input  wire        pixel_valid,

    output wire        ppu_en,        // 1 = a row buffer is free (producer may present a pixel)

    input  wire        rd_en,         // consumer takes the presented scaled pixel
    output wire        pixel_valid_o, // 1 = pixel_o is valid (a full row buffer is available)
    output wire [15:0] pixel_o,

    output wire [$clog2(NBUF):0] wr_level, // full-buffer occupancy, write-domain view (0..NBUF)

    // frame-drop policy (producer domain). frame_start is a 1-cycle pulse at each source-frame
    // boundary, BEFORE that frame's first pixel. A frame is captured only if the FIFO has fully
    // drained by then; otherwise the WHOLE frame is skipped (never a partial row) so the output
    // stays row-aligned instead of scrambling. Requires NBUF >= a single frame's peak backlog.
    input  wire        frame_start,
    output wire        frame_dropped  // high while the current source frame is being dropped
);
    // Prototype: a DEEP row-buffer FIFO (vs the 2-buffer lcd_writer) to absorb the per-row
    // producer/consumer rate mismatch across a frame and drain it in VBlank. Buffer granularity
    // uses a textbook gray-code async FIFO (hence NBUF must be 2^k); each entry is one COLS-pixel
    // source row. The read side applies the 2x horizontal + 2x vertical upscale (rHalf/read_row)
    // and pops a buffer only after its second vertical pass. Async read of buf_mem is fine in sim;
    // a synthesis pass may force a registered read (which shifts the pull protocol by one cycle).
    localparam integer AW = $clog2(NBUF);   // buffer-index width; pointer width is AW+1

    reg [15:0] buf_mem [0:NBUF*COLS-1];      // flattened: addr = buf*COLS + col

    function [AW:0] bin2gray(input [AW:0] b); bin2gray = b ^ (b >> 1); endfunction
    function [AW:0] gray2bin(input [AW:0] g);
        integer i; reg [AW:0] b;
        begin
            b[AW] = g[AW];
            for (i = AW-1; i >= 0; i = i - 1) b[i] = b[i+1] ^ g[i];
            gray2bin = b;
        end
    endfunction

    // buffer-granular pointers (declared before the cross-domain syncs that reference them)
    reg  [AW:0]   wbin = 0, wgray = 0;       // write pointer (clk_W)
    reg  [AW:0]   rbin = 0, rgray = 0;       // read pointer  (clk_R)

    // ---- write side (producer, clk_W) ----
    reg  [AW:0]   rq1 = 0, rq2 = 0;          // read gray pointer synced into clk_W
    reg  [15:0]   w = 0;                      // column index within the current write buffer
    reg           capturing = 0;              // 1 = accepting the current source frame's pixels
    reg           dropped = 0;                // 1 = current source frame is being skipped
    wire [AW-1:0] wbuf = wbin[AW-1:0];

    // full: pointers NBUF apart (top two gray bits inverted) -> no free buffer
    wire wfull = (wgray == {~rq2[AW:AW-1], rq2[AW-2:0]});

    always @(posedge clk_W or negedge nrst) begin
        if (!nrst) begin
            w <= 0; wbin <= 0; wgray <= 0; capturing <= 1'b0; dropped <= 1'b0;
        end else if (frame_start) begin
            // admit this frame only if the FIFO fully drained since the last one
            capturing <= (wr_level == 0);
            dropped   <= (wr_level != 0);
            w         <= 0;                      // align to row 0, discard any partial row
        end else if (capturing && !nEN && pixel_valid) begin
            if (!wfull) begin
                buf_mem[wbuf*COLS + w] <= pixel_i;
                if (w == COLS-1) begin
                    w    <= 0;
                    wbin <= wbin + 1'b1;                 // push a completed row buffer
                    wgray<= bin2gray(wbin + 1'b1);
                end else begin
                    w <= w + 16'd1;
                end
            end else begin
                capturing <= 1'b0;               // overflow backstop: abandon rest of frame,
                dropped   <= 1'b1;               // never continue with a corrupt partial row
            end
        end
    end

    always @(posedge clk_W or negedge nrst) begin   // sync read pointer into clk_W
        if (!nrst) begin rq1 <= 0; rq2 <= 0; end
        else       begin rq1 <= rgray; rq2 <= rq1; end
    end

    assign ppu_en       = !nEN && capturing && !wfull;   // advisory: are we accepting right now
    assign frame_dropped= dropped;
    assign wr_level     = wbin - gray2bin(rq2);          // full buffers waiting (write-domain view)

    // ---- read side (consumer, clk_R) ----
    reg  [AW:0]   wq1 = 0, wq2 = 0;          // write gray pointer synced into clk_R
    reg  [15:0]   r = 0;                      // column index within the current read buffer
    reg           rHalf = 0, read_row = 0;
    wire [AW-1:0] rbuf = rbin[AW-1:0];

    wire rempty = (rgray == wq2);            // no full buffer available
    wire adv    = !nEN && rd_en && !rempty;

    always @(posedge clk_R or negedge nrst) begin
        if (!nrst) begin
            r <= 0; rHalf <= 0; read_row <= 0; rbin <= 0; rgray <= 0;
        end else if (adv) begin
            rHalf <= ~rHalf;
            if (rHalf) begin                          // both halves of this column emitted
                if (r == COLS-1) begin
                    r <= 0;
                    if (read_row) begin               // 2nd vertical pass done -> pop buffer
                        read_row <= 0;
                        rbin  <= rbin + 1'b1;
                        rgray <= bin2gray(rbin + 1'b1);
                    end else begin
                        read_row <= 1'b1;             // replay same buffer for vertical 2x
                    end
                end else begin
                    r <= r + 16'd1;
                end
            end
        end
    end

    always @(posedge clk_R or negedge nrst) begin   // sync write pointer into clk_R
        if (!nrst) begin wq1 <= 0; wq2 <= 0; end
        else       begin wq1 <= wgray; wq2 <= wq1; end
    end

    // Synchronous (registered) read so buf_mem infers M10K instead of fabric registers.
    // The registered output lags the read address by one clk_R, so after an advance the output
    // is stale for exactly one cycle; addr_changed masks pixel_valid_o during that warmup so the
    // consumer (which already gates on pixel_valid_o) self-times to the read latency.
    wire [$clog2(NBUF*COLS)-1:0] rd_addr = rbuf*COLS + r;
    reg  [15:0] pixel_o_r    = 16'd0;
    reg         addr_changed = 1'b1;
    always @(posedge clk_R or negedge nrst) begin
        if (!nrst) begin
            pixel_o_r    <= 16'd0;
            addr_changed <= 1'b1;
        end else begin
            pixel_o_r    <= buf_mem[rd_addr];   // 1-cycle read latency -> maps to M10K
            addr_changed <= adv;                // output stale for the cycle after an advance
        end
    end

    assign pixel_valid_o = !nEN && !rempty && !addr_changed;
    assign pixel_o       = pixel_o_r;

endmodule
