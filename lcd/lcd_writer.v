module lcd_writer (
    input wire clk_W,          // PPU-side write clock (e.g. 17 MHz clock_cpu)
    input wire clk_R,          // LCD-side read clock (e.g. 4x clk_W); see handshake note
    input wire nrst,
    input wire nEN,            // active-low global enable

    input wire [15:0] pixel_i, // captured source pixel (already RGB565; conversion is upstream)
    input wire pixel_valid,    // source pixel present this clk_W

    output wire ppu_en,        // 1 = a buffer is free, producer may present a pixel

    input  wire rd_en,         // consumer (lcd_8080_writer) pulses to take the presented pixel
    output wire pixel_valid_o, // 1 = pixel_o is a valid scaled pixel from a ready buffer
    output wire [15:0] pixel_o // current scaled pixel (stable until an accepted rd_en)
);
    // Two 240-pixel row buffers with 2x horizontal + 2x vertical upscale on the read side.
    //
    // Buffer ownership is a producer/consumer handshake, NOT the old same-buffer collision test:
    //   * writer flips prod_tgl[k] when it finishes filling buffer k;
    //   * reader flips cons_tgl[k] when it finishes consuming buffer k (both vertical passes).
    // Each toggle is passed to the opposite domain through a 2-FF synchronizer, so the crossing
    // is a proper toggle handshake and is safe even if clk_W/clk_R are not phase-locked. Do NOT
    // "optimize" the synchronizers away on the assumption that clk_R = 4*clk_W is mesochronous.
    //
    // NOTE (design limit): this makes underrun SAFE (the reader cleanly stalls via pixel_valid_o
    // low) but two line buffers still cannot SUSTAIN the real sparse PPU cadence (1 valid pixel
    // per 4 clk_W). Frame buffers remain the real fix; see FPGA_LCD_INTEGRATION.md.

    reg [15:0] buffer_A [0:239];
    reg [15:0] buffer_B [0:239];

    // toggle handshake bits, indexed by buffer {0:A, 1:B}
    reg  [1:0] prod_tgl = 2'b00;   // clk_W domain
    reg  [1:0] cons_tgl = 2'b00;   // clk_R domain
    reg  [1:0] prod_s0  = 2'b00, prod_s1 = 2'b00;  // prod_tgl synchronized into clk_R
    reg  [1:0] cons_s0  = 2'b00, cons_s1 = 2'b00;  // cons_tgl synchronized into clk_W

    wire [1:0] ready = prod_s1 ^ cons_tgl;         // clk_R view: buffer full, owned by reader
    wire [1:0] freeb = ~(prod_tgl ^ cons_s1);      // clk_W view: buffer empty, owned by writer

    // ---- write side (clk_W) ---------------------------------------------
    reg        wsel = 1'b0;   // buffer currently being filled
    reg [7:0]  w    = 8'd0;

    always @(posedge clk_W or negedge nrst) begin
        if (!nrst) begin
            wsel     <= 1'b0;
            w        <= 8'd0;
            prod_tgl <= 2'b00;
        end else if (!nEN && pixel_valid && freeb[wsel]) begin
            if (wsel) buffer_B[w] <= pixel_i;
            else      buffer_A[w] <= pixel_i;

            if (w == 8'd239) begin
                w             <= 8'd0;
                prod_tgl[wsel] <= ~prod_tgl[wsel];  // hand this buffer to the reader
                wsel          <= ~wsel;
            end else begin
                w <= w + 8'd1;
            end
        end
    end

    // synchronize cons_tgl into clk_W
    always @(posedge clk_W or negedge nrst) begin
        if (!nrst) begin cons_s0 <= 2'b00; cons_s1 <= 2'b00; end
        else       begin cons_s0 <= cons_tgl; cons_s1 <= cons_s0; end
    end

    assign ppu_en = !nEN && freeb[wsel];

    // ---- read side (clk_R) ----------------------------------------------
    reg       rsel     = 1'b0;   // buffer currently being read
    reg [7:0] r        = 8'd0;
    reg       rHalf    = 1'b0;   // horizontal 2x: each column emitted twice
    reg       read_row = 1'b0;   // vertical 2x: each buffer emitted twice

    wire advance = !nEN && rd_en && ready[rsel];   // pixel_valid_o gates the advance

    always @(posedge clk_R or negedge nrst) begin
        if (!nrst) begin
            rsel     <= 1'b0;
            r        <= 8'd0;
            rHalf    <= 1'b0;
            read_row <= 1'b0;
            cons_tgl <= 2'b00;
        end else if (advance) begin
            rHalf <= ~rHalf;
            if (rHalf) begin                 // finished both halves of this column
                if (r == 8'd239) begin
                    r <= 8'd0;
                    if (read_row) begin       // finished the 2nd vertical pass -> buffer done
                        read_row       <= 1'b0;
                        cons_tgl[rsel] <= ~cons_tgl[rsel];  // release buffer to writer
                        rsel           <= ~rsel;
                    end else begin
                        read_row <= 1'b1;     // replay the same buffer for vertical 2x
                    end
                end else begin
                    r <= r + 8'd1;
                end
            end
        end
    end

    // synchronize prod_tgl into clk_R
    always @(posedge clk_R or negedge nrst) begin
        if (!nrst) begin prod_s0 <= 2'b00; prod_s1 <= 2'b00; end
        else       begin prod_s0 <= prod_tgl; prod_s1 <= prod_s0; end
    end

    assign pixel_valid_o = !nEN && ready[rsel];
    assign pixel_o       = rsel ? buffer_B[r] : buffer_A[r];

endmodule
