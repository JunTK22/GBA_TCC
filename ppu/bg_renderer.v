`default_nettype none

// =============================================================================
//  bg_renderer.v
//  Four-layer GBA background fetch engine.
//
//  The renderer implements text, affine, and bitmap fetch paths over one
//  synchronous VRAM read interface. `vram_address` is a 16-bit halfword index;
//  the parent PPU converts it to a byte address at the memory boundary.
//
//  Each background has an independent valid/ready pixel lane. Verilog-2001
//  ports are flattened with BG0 in the least-significant packed element.
//  Affine-reference write pulses reload the internal BG2/BG3 coordinates;
//  vertical mosaic and scanline/frame progression update those coordinates.
// =============================================================================
module bg_renderer (
    input                            clock,
    input                            reset,
    input                            enable,

    input      [2:0]                 display_mode,
    input                            display_frame,
    input      [3:0]                 display_enable_bg,

    input      [7:0]                 bg_size,
    input      [3:0]                 bg_affine_wrap,
    input      [19:0]                bg_screen_base,
    input      [3:0]                 bg_bpp8,
    input      [3:0]                 bg_mosaic,
    input      [7:0]                 bg_char_base,

    input      [63:0]                bg_off_x,
    input      [63:0]                bg_off_y,

    input      [31:0]                bg_aff_pa,
    input      [31:0]                bg_aff_pb,
    input      [31:0]                bg_aff_pc,
    input      [31:0]                bg_aff_pd,
    input      [55:0]                bg_aff_x,
    input      [55:0]                bg_aff_y,
    input      [1:0]                 write_aff_x,
    input      [1:0]                 write_aff_y,
    input      [3:0]                 mosaic_y,

    output reg                       vram_read,
    output reg [15:0]                vram_address,
    input      [15:0]                vram_read_data,

    input      [10:0]                tick,
    input      [7:0]                 scanline,

    output reg [3:0]                 pixels_valid,
    input      [3:0]                 pixels_ready,
    output reg [3:0]                 pixels_opaque,
    output     [31:0]                pixels_color
);

    localparam [1:0] PHASE_REQUEST = 2'd0;
    localparam [1:0] PHASE_USE     = 2'd1;
    localparam [1:0] PHASE_WAIT_A  = 2'd2;
    localparam [1:0] PHASE_WAIT_B  = 2'd3;

    reg                            layer_active       [0:3];
    reg [1:0]                      state              [0:3];
    reg [1:0]                      next_state         [0:3];
    reg [2:0]                      tile_stage         [0:3];
    reg [7:0]                      layer_pos          [0:3];
    reg [3:0]                      layer_palette_bank [0:3];
    reg                            layer_flip_y       [0:3];
    reg                            layer_flip_x       [0:3];
    reg [9:0]                      layer_tile         [0:3];
    reg                            layer_pixel_opaque [0:3][0:3];
    reg [7:0]                      layer_pixel_color  [0:3][0:3];

    reg signed [27:0]              aff_x              [0:1];
    reg signed [27:0]              aff_y              [0:1];
    reg signed [27:0]              aff_x_line         [0:1];
    reg signed [27:0]              aff_y_line         [0:1];
    reg signed [27:0]              aff_x_mosaic       [0:1];
    reg signed [27:0]              aff_y_mosaic       [0:1];
    reg [7:0]                      aff_pixel_color    [0:1];
    wire signed [27:0]             aff_line_next_x    [0:1];
    wire signed [27:0]             aff_line_next_y    [0:1];
    reg [3:0]                      mosaic_counter;

    reg [3:0]                      regular_selected;
    reg [1:0]                      affine_selected;
    reg                            bitmap_selected;
    wire                           is_vdraw;
    wire                           fifo_flush;

    wire [15:0]                    regular_x          [0:3];
    wire [15:0]                    regular_y          [0:3];
    wire                           regular_fetch_4bpp [0:3];
    wire                           regular_fetch_8bpp [0:3];
    wire [10:0]                    regular_start_tick [0:3];

    wire [37:0]                    bitmap_linear_240;
    wire [37:0]                    bitmap_linear_160;

    reg [3:0]                      enqueue_valid;
    reg [3:0]                      enqueue_opaque;
    reg [7:0]                      enqueue_color      [0:3];

    reg                            fifo_mem_opaque    [0:3][0:4];
    reg [7:0]                      fifo_mem_color     [0:3][0:4];
    reg [2:0]                      fifo_enqueue_ptr   [0:3];
    reg [2:0]                      fifo_dequeue_ptr   [0:3];
    reg [2:0]                      fifo_count         [0:3];
    reg [3:0]                      fifo_enqueue_ready;
    reg [3:0]                      fifo_enqueue_fire;
    reg [3:0]                      fifo_dequeue_fire;
    reg [7:0]                      pixels_color_i     [0:3];

    wire [1:0]                     bg_size_i          [0:3];
    wire                           bg_affine_wrap_i   [0:3];
    wire [4:0]                     bg_screen_base_i   [0:3];
    wire                           bg_bpp8_i          [0:3];
    wire                           bg_mosaic_i        [0:3];
    wire [1:0]                     bg_char_base_i     [0:3];
    wire [15:0]                    bg_off_x_i         [0:3];
    wire [15:0]                    bg_off_y_i         [0:3];

    wire signed [15:0]             bg_aff_pa_i        [0:1];
    wire signed [15:0]             bg_aff_pb_i        [0:1];
    wire signed [15:0]             bg_aff_pc_i        [0:1];
    wire signed [15:0]             bg_aff_pd_i        [0:1];
    wire signed [27:0]             bg_aff_x_i         [0:1];
    wire signed [27:0]             bg_aff_y_i         [0:1];

    genvar port_bg;
    generate
        for (port_bg = 0; port_bg < 4; port_bg = port_bg + 1) begin : g_port_bg
            assign bg_size_i[port_bg] = bg_size[(port_bg * 2) +: 2];
            assign bg_affine_wrap_i[port_bg] = bg_affine_wrap[port_bg];
            assign bg_screen_base_i[port_bg] =
                bg_screen_base[(port_bg * 5) +: 5];
            assign bg_bpp8_i[port_bg] = bg_bpp8[port_bg];
            assign bg_mosaic_i[port_bg] = bg_mosaic[port_bg];
            assign bg_char_base_i[port_bg] =
                bg_char_base[(port_bg * 2) +: 2];
            assign bg_off_x_i[port_bg] = bg_off_x[(port_bg * 16) +: 16];
            assign bg_off_y_i[port_bg] = bg_off_y[(port_bg * 16) +: 16];
            assign pixels_color[(port_bg * 8) +: 8] = pixels_color_i[port_bg];
        end
    endgenerate

    genvar port_aff;
    generate
        for (port_aff = 0; port_aff < 2; port_aff = port_aff + 1) begin : g_port_aff
            assign bg_aff_pa_i[port_aff] = bg_aff_pa[(port_aff * 16) +: 16];
            assign bg_aff_pb_i[port_aff] = bg_aff_pb[(port_aff * 16) +: 16];
            assign bg_aff_pc_i[port_aff] = bg_aff_pc[(port_aff * 16) +: 16];
            assign bg_aff_pd_i[port_aff] = bg_aff_pd[(port_aff * 16) +: 16];
            assign bg_aff_x_i[port_aff] = bg_aff_x[(port_aff * 28) +: 28];
            assign bg_aff_y_i[port_aff] = bg_aff_y[(port_aff * 28) +: 28];
        end
    endgenerate

    function automatic [15:0] regular_map_address;
        input [4:0] screen_base;
        input [1:0] size;
        input [15:0] x;
        input [15:0] y;
        reg [1:0] screen_offset;
        reg [4:0] screen_block;
        begin
            case (size)
                2'd0: screen_offset = 2'd0;
                2'd1: screen_offset = {1'b0, x[8]};
                2'd2: screen_offset = {1'b0, y[8]};
                default: screen_offset = {y[8], x[8]};
            endcase
            screen_block = screen_base + screen_offset;
            regular_map_address = {1'b0, screen_block, y[7:3], x[7:3]};
        end
    endfunction

    function automatic [15:0] regular_4bpp_address;
        input [1:0] char_base;
        input [9:0] tile_index;
        input flip_x;
        input flip_y;
        input [15:0] y;
        input [2:0] stage;
        reg [11:0] tile;
        reg [2:0] row;
        reg col;
        begin
            tile = {1'b0, char_base, 9'b0} + {2'b0, tile_index};
            row = flip_y ? ~y[2:0] : y[2:0];
            col = stage[2] ^ flip_x;
            regular_4bpp_address = {tile, row, col};
        end
    endfunction

    function automatic [15:0] regular_8bpp_address;
        input [1:0] char_base;
        input [9:0] tile_index;
        input flip_x;
        input flip_y;
        input [15:0] y;
        input [2:0] stage;
        reg [10:0] tile;
        reg [2:0] row;
        reg [1:0] col;
        begin
            tile = {1'b0, char_base, 8'b0} + {1'b0, tile_index};
            row = flip_y ? ~y[2:0] : y[2:0];
            col = flip_x ? ~stage[2:1] : stage[2:1];
            regular_8bpp_address = {tile, row, col};
        end
    endfunction

    function automatic [15:0] affine_map_address;
        input [4:0] screen_base;
        input [1:0] size;
        input signed [27:0] ref_x;
        input signed [27:0] ref_y;
        reg [15:0] tile_offset;
        reg [15:0] byte_address;
        begin
            case (size)
                2'd0: tile_offset = {8'b0, ref_y[14:11], ref_x[14:11]};
                2'd1: tile_offset = {6'b0, ref_y[15:11], ref_x[15:11]};
                2'd2: tile_offset = {4'b0, ref_y[16:11], ref_x[16:11]};
                default: tile_offset = {2'b0, ref_y[17:11], ref_x[17:11]};
            endcase
            byte_address = {screen_base, 11'b0} + tile_offset;
            affine_map_address = byte_address >> 1;
        end
    endfunction

    function automatic [15:0] affine_tile_address;
        input [1:0] char_base;
        input [7:0] tile_index;
        input signed [27:0] ref_x;
        input signed [27:0] ref_y;
        reg [10:0] tile;
        reg [16:0] byte_address;
        begin
            tile = {1'b0, char_base, 8'b0} + {3'b0, tile_index};
            byte_address = {tile, ref_y[10:8], ref_x[10:8]};
            affine_tile_address = byte_address[16:1];
        end
    endfunction

    function automatic [10:0] affine_size_pixels;
        input [1:0] size;
        begin
            case (size)
                2'd0: affine_size_pixels = 11'd128;
                2'd1: affine_size_pixels = 11'd256;
                2'd2: affine_size_pixels = 11'd512;
                default: affine_size_pixels = 11'd1024;
            endcase
        end
    endfunction

    assign is_vdraw = scanline < 8'd160;
    assign fifo_flush = enable && is_vdraw && (tick == 11'd1005);

    always @* begin : combinational_0
        integer i;
        integer a;
        regular_selected = 4'b0000;
        affine_selected = 2'b00;
        bitmap_selected = 1'b0;
        case (display_mode)
            3'd0: regular_selected = display_enable_bg;
            3'd1: begin
                regular_selected[0] = display_enable_bg[0];
                regular_selected[1] = display_enable_bg[1];
                affine_selected[0] = display_enable_bg[2];
            end
            3'd2: begin
                affine_selected[0] = display_enable_bg[2];
                affine_selected[1] = display_enable_bg[3];
            end
            3'd3, 3'd4, 3'd5: bitmap_selected = display_enable_bg[2];
            default: begin end
        endcase
    end

    genvar regular_g;
    generate
        for (regular_g = 0; regular_g < 4; regular_g = regular_g + 1) begin : g_regular_derived
            localparam [10:0] START_BASE = 11'd30 + regular_g;
            assign regular_x[regular_g] = layer_pos[regular_g] + bg_off_x_i[regular_g];
            assign regular_y[regular_g] = scanline + bg_off_y_i[regular_g]
                                  - (bg_mosaic_i[regular_g] ? mosaic_counter : 4'd0);
            assign regular_fetch_4bpp[regular_g] = (tile_stage[regular_g][1:0] == 2'd1)
                                                  && !bg_bpp8_i[regular_g];
            assign regular_fetch_8bpp[regular_g] = tile_stage[regular_g][0] && bg_bpp8_i[regular_g];
            assign regular_start_tick[regular_g] = START_BASE
                                          - {6'b0, bg_off_x_i[regular_g][2:0], 2'b0};
        end
    endgenerate

    genvar affine_g;
    generate
        for (affine_g = 0; affine_g < 2; affine_g = affine_g + 1) begin : g_affine_derived
            assign aff_line_next_x[affine_g] = $signed(aff_x_line[affine_g]) + $signed(bg_aff_pb_i[affine_g]);
            assign aff_line_next_y[affine_g] = $signed(aff_y_line[affine_g]) + $signed(bg_aff_pd_i[affine_g]);
        end
    endgenerate

    assign bitmap_linear_240 = (aff_y[0][26:8] * 19'd240) + aff_x[0][26:8];
    assign bitmap_linear_160 = (aff_y[0][26:8] * 19'd160) + aff_x[0][26:8];

    // Traditional combinational next-state decoder.
    always @* begin : combinational_1
        integer i;
        integer a;
        for (i = 0; i < 4; i = i + 1) begin
            next_state[i] = state[i];
            case (state[i])
                PHASE_REQUEST: next_state[i] = PHASE_USE;
                PHASE_USE:     next_state[i] = PHASE_WAIT_A;
                PHASE_WAIT_A:  next_state[i] = PHASE_WAIT_B;
                PHASE_WAIT_B:  next_state[i] = PHASE_REQUEST;
                default: begin end
            endcase
        end
    end

    // State register and regular-background pixel-stage counter.
    always @(posedge clock) begin : sequential_0
        integer i;
        integer a;
        if (reset) begin
            for (i = 0; i < 4; i = i + 1) begin
                state[i] <= PHASE_REQUEST;
                tile_stage[i] <= 3'd0;
            end
        end else if (enable && is_vdraw) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (layer_active[i]) begin
                    state[i] <= next_state[i];
                    if (state[i] == PHASE_WAIT_B) begin
                        tile_stage[i] <= tile_stage[i] + 3'd1;
                    end
                end
            end

            if (tick == 11'd1005) begin
                for (i = 0; i < 4; i = i + 1) begin
                    state[i] <= PHASE_REQUEST;
                    tile_stage[i] <= 3'd0;
                end
            end
        end
    end

    // Combinational actions associated with FSM states.
    always @* begin : combinational_2
        integer i;
        integer a;
        vram_read = 1'b0;
        vram_address = 16'b0;
        enqueue_valid = 4'b0000;
        enqueue_opaque = 4'b0000;
        for (i = 0; i < 4; i = i + 1) begin
            enqueue_color[i] = 8'b0;
        end

        for (i = 0; i < 4; i = i + 1) begin
            if (regular_selected[i] && enable && layer_active[i]
                && (state[i] == PHASE_REQUEST)) begin
                if (tile_stage[i] == 3'd0) begin
                    vram_read = 1'b1;
                    vram_address = regular_map_address(
                        bg_screen_base_i[i], bg_size_i[i], regular_x[i], regular_y[i]
                    );
                end
                if (regular_fetch_4bpp[i]) begin
                    vram_address = regular_4bpp_address(
                        bg_char_base_i[i], layer_tile[i], layer_flip_x[i],
                        layer_flip_y[i], regular_y[i], tile_stage[i]
                    );
                    vram_read = vram_address < 16'h8000;
                end
                if (regular_fetch_8bpp[i]) begin
                    vram_address = regular_8bpp_address(
                        bg_char_base_i[i], layer_tile[i], layer_flip_x[i],
                        layer_flip_y[i], regular_y[i], tile_stage[i]
                    );
                    vram_read = vram_address < 16'h8000;
                end

                if (tick >= 11'd39) begin
                    enqueue_valid[i] = 1'b1;
                    enqueue_opaque[i] = layer_pixel_opaque[i][0];
                    enqueue_color[i] = layer_pixel_color[i][0];
                end
            end
        end

        for (a = 0; a < 2; a = a + 1) begin
            if (affine_selected[a] && enable && layer_active[a + 2]) begin
                if (state[a + 2] == PHASE_REQUEST) begin
                    vram_read = 1'b1;
                    vram_address = affine_map_address(
                        bg_screen_base_i[a + 2], bg_size_i[a + 2], aff_x[a], aff_y[a]
                    );
                end
                if (state[a + 2] == PHASE_USE) begin
                    vram_read = 1'b1;
                    vram_address = affine_tile_address(
                        bg_char_base_i[a + 2],
                        aff_x[a][11] ? vram_read_data[15:8] : vram_read_data[7:0],
                        aff_x[a], aff_y[a]
                    );
                end
                if (state[a + 2] == PHASE_WAIT_A) begin
                    enqueue_valid[a + 2] = 1'b1;
                    enqueue_color[a + 2] = aff_pixel_color[a];
                    enqueue_opaque[a + 2] = enqueue_color[a + 2] != 8'd0;
                    if (!bg_affine_wrap_i[a + 2]
                        && (aff_x[a][27] || aff_y[a][27]
                            || (aff_x[a][26:8] >= affine_size_pixels(bg_size_i[a + 2]))
                            || (aff_y[a][26:8] >= affine_size_pixels(bg_size_i[a + 2])))) begin
                        enqueue_opaque[a + 2] = 1'b0;
                    end
                end
            end
        end

        if (bitmap_selected && enable && layer_active[2]) begin
            if (state[2] == PHASE_REQUEST) begin
                vram_read = 1'b1;
                case (display_mode)
                    3'd3: vram_address = bitmap_linear_240[15:0];
                    3'd4: vram_address = (bitmap_linear_240 >> 1)
                                               + (display_frame ? 16'h5000 : 16'h0000);
                    3'd5: vram_address = bitmap_linear_160
                                               + (display_frame ? 16'h5000 : 16'h0000);
                    default: vram_address = 16'b0;
                endcase
            end

            if (state[2] == PHASE_USE) begin
                enqueue_valid[2] = 1'b1;
                enqueue_opaque[2] = 1'b1;
                case (display_mode)
                    3'd4: begin
                        enqueue_color[2] = aff_x[0][8]
                                                   ? vram_read_data[15:8]
                                                   : vram_read_data[7:0];
                        if (enqueue_color[2] == 8'd0) begin
                            enqueue_opaque[2] = 1'b0;
                        end
                    end
                    3'd3, 3'd5: begin
                        enqueue_valid[3] = 1'b1;
                        enqueue_opaque[3] = 1'b0;
                        enqueue_color[2] = vram_read_data[7:0];
                        enqueue_color[3] = vram_read_data[15:8];
                    end
                    default: begin end
                endcase

                if (aff_x[0][27] || aff_y[0][27]
                    || (aff_x[0][26:8] >= ((display_mode == 3'd5) ? 19'd160 : 19'd240))
                    || (aff_y[0][26:8] >= ((display_mode == 3'd5) ? 19'd128 : 19'd160))) begin
                    enqueue_opaque[2] = 1'b0;
                end
            end
        end
    end

    // Sequential datapath actions controlled by the registered state.
    always @(posedge clock) begin : sequential_1
        integer i;
        integer a;
        integer pixel_i;
        if (reset) begin
            for (i = 0; i < 4; i = i + 1) begin
                layer_active[i] <= 1'b0;
                layer_pos[i] <= 8'd0;
                layer_palette_bank[i] <= 4'd0;
                layer_flip_y[i] <= 1'b0;
                layer_flip_x[i] <= 1'b0;
                layer_tile[i] <= 10'd0;
                for (pixel_i = 0; pixel_i < 4; pixel_i = pixel_i + 1) begin
                    layer_pixel_opaque[i][pixel_i] <= 1'b0;
                    layer_pixel_color[i][pixel_i] <= 8'd0;
                end
            end
            for (a = 0; a < 2; a = a + 1) begin
                aff_x[a] <= bg_aff_x_i[a];
                aff_y[a] <= bg_aff_y_i[a];
                aff_x_line[a] <= bg_aff_x_i[a];
                aff_y_line[a] <= bg_aff_y_i[a];
                aff_x_mosaic[a] <= bg_aff_x_i[a];
                aff_y_mosaic[a] <= bg_aff_y_i[a];
                aff_pixel_color[a] <= 8'd0;
            end
            mosaic_counter <= 4'd0;
        end else begin
            for (i = 0; i < 4; i = i + 1) begin
                if (regular_selected[i]) begin
                    if (enable && is_vdraw && (tick == regular_start_tick[i])) begin
                        layer_active[i] <= 1'b1;
                    end

                    if (enable && layer_active[i]) begin
                        if (state[i] == PHASE_REQUEST) begin
                            layer_pixel_opaque[i][0] <= layer_pixel_opaque[i][1];
                            layer_pixel_opaque[i][1] <= layer_pixel_opaque[i][2];
                            layer_pixel_opaque[i][2] <= layer_pixel_opaque[i][3];
                            layer_pixel_color[i][0] <= layer_pixel_color[i][1];
                            layer_pixel_color[i][1] <= layer_pixel_color[i][2];
                            layer_pixel_color[i][2] <= layer_pixel_color[i][3];
                        end

                        if (state[i] == PHASE_USE) begin
                            layer_pos[i] <= layer_pos[i] + 8'd1;
                            if (tile_stage[i] == 3'd0) begin
                                layer_palette_bank[i] <= vram_read_data[15:12];
                                layer_flip_y[i] <= vram_read_data[11];
                                layer_flip_x[i] <= vram_read_data[10];
                                layer_tile[i] <= vram_read_data[9:0];
                            end

                            if (regular_fetch_4bpp[i]) begin
                                layer_pixel_opaque[i][0] <= (layer_flip_x[i]
                                    ? vram_read_data[15:12] : vram_read_data[3:0]) != 4'd0;
                                layer_pixel_opaque[i][1] <= (layer_flip_x[i]
                                    ? vram_read_data[11:8] : vram_read_data[7:4]) != 4'd0;
                                layer_pixel_opaque[i][2] <= (layer_flip_x[i]
                                    ? vram_read_data[7:4] : vram_read_data[11:8]) != 4'd0;
                                layer_pixel_opaque[i][3] <= (layer_flip_x[i]
                                    ? vram_read_data[3:0] : vram_read_data[15:12]) != 4'd0;
                                layer_pixel_color[i][0] <= {layer_palette_bank[i],
                                    layer_flip_x[i] ? vram_read_data[15:12] : vram_read_data[3:0]};
                                layer_pixel_color[i][1] <= {layer_palette_bank[i],
                                    layer_flip_x[i] ? vram_read_data[11:8] : vram_read_data[7:4]};
                                layer_pixel_color[i][2] <= {layer_palette_bank[i],
                                    layer_flip_x[i] ? vram_read_data[7:4] : vram_read_data[11:8]};
                                layer_pixel_color[i][3] <= {layer_palette_bank[i],
                                    layer_flip_x[i] ? vram_read_data[3:0] : vram_read_data[15:12]};
                            end

                            if (regular_fetch_8bpp[i]) begin
                                layer_pixel_opaque[i][0] <= (layer_flip_x[i]
                                    ? vram_read_data[15:8] : vram_read_data[7:0]) != 8'd0;
                                layer_pixel_opaque[i][1] <= (layer_flip_x[i]
                                    ? vram_read_data[7:0] : vram_read_data[15:8]) != 8'd0;
                                layer_pixel_color[i][0] <= layer_flip_x[i]
                                    ? vram_read_data[15:8] : vram_read_data[7:0];
                                layer_pixel_color[i][1] <= layer_flip_x[i]
                                    ? vram_read_data[7:0] : vram_read_data[15:8];
                            end
                        end
                    end
                end
            end

            for (a = 0; a < 2; a = a + 1) begin
                if (affine_selected[a]) begin
                    if (enable && is_vdraw
                        && (tick == ((a == 0) ? 11'd32 : 11'd30))) begin
                        layer_active[a + 2] <= 1'b1;
                    end
                    if (enable && layer_active[a + 2]
                        && (state[a + 2] == PHASE_USE)) begin
                        // Preserve the tile response across the next BG request
                        // without moving the existing WAIT_A FIFO commit.
                        aff_pixel_color[a] <= aff_x[a][8]
                            ? vram_read_data[15:8] : vram_read_data[7:0];
                    end
                    if (enable && layer_active[a + 2]
                        && (state[a + 2] == PHASE_WAIT_A)) begin
                        aff_x[a] <= $signed(aff_x[a]) + $signed(bg_aff_pa_i[a]);
                        aff_y[a] <= $signed(aff_y[a]) + $signed(bg_aff_pc_i[a]);
                    end
                end
            end

            if (bitmap_selected) begin
                if (enable && is_vdraw && (tick == 11'd33)) begin
                    layer_active[2] <= 1'b1;
                end
                if (enable && layer_active[2] && (state[2] == PHASE_USE)) begin
                    aff_x[0] <= $signed(aff_x[0]) + $signed(bg_aff_pa_i[0]);
                    aff_y[0] <= $signed(aff_y[0]) + $signed(bg_aff_pc_i[0]);
                end
            end

            if (enable && is_vdraw) begin
                if (tick == 11'd1005) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        layer_active[i] <= 1'b0;
                        layer_pos[i] <= 8'd0;
                    end

                    for (a = 0; a < 2; a = a + 1) begin
                        aff_x[a] <= aff_line_next_x[a];
                        aff_y[a] <= aff_line_next_y[a];
                        aff_x_line[a] <= aff_line_next_x[a];
                        aff_y_line[a] <= aff_line_next_y[a];
                        if (mosaic_counter == mosaic_y) begin
                            aff_x_mosaic[a] <= aff_line_next_x[a];
                            aff_y_mosaic[a] <= aff_line_next_y[a];
                        end else if (bg_mosaic_i[a + 2]) begin
                            aff_x[a] <= aff_x_mosaic[a];
                            aff_y[a] <= aff_y_mosaic[a];
                        end
                    end

                    mosaic_counter <= mosaic_counter + 4'd1;
                    if (mosaic_counter == mosaic_y) begin
                        mosaic_counter <= 4'd0;
                    end
                end
            end

            if (enable) begin
                if (is_vdraw) begin
                    for (a = 0; a < 2; a = a + 1) begin
                        if (write_aff_x[a]) begin
                            aff_x[a] <= bg_aff_x_i[a];
                            aff_x_line[a] <= bg_aff_x_i[a];
                        end
                        if (write_aff_y[a]) begin
                            aff_y[a] <= bg_aff_y_i[a];
                            aff_y_line[a] <= bg_aff_y_i[a];
                        end
                    end
                end else begin
                    for (a = 0; a < 2; a = a + 1) begin
                        aff_x[a] <= bg_aff_x_i[a];
                        aff_y[a] <= bg_aff_y_i[a];
                        aff_x_line[a] <= bg_aff_x_i[a];
                        aff_y_line[a] <= bg_aff_y_i[a];
                        aff_x_mosaic[a] <= bg_aff_x_i[a];
                        aff_y_mosaic[a] <= bg_aff_y_i[a];
                    end
                    mosaic_counter <= 4'd0;
                end
            end
        end
    end

    always @* begin : combinational_3
        integer i;
        integer a;
        for (i = 0; i < 4; i = i + 1) begin
            fifo_enqueue_ready[i] = fifo_count[i] != 3'd5;
            fifo_enqueue_fire[i] = enqueue_valid[i] && fifo_enqueue_ready[i];
            pixels_valid[i] = fifo_count[i] != 3'd0;
            pixels_opaque[i] = fifo_mem_opaque[i][fifo_dequeue_ptr[i]];
            pixels_color_i[i] = fifo_mem_color[i][fifo_dequeue_ptr[i]];
            fifo_dequeue_fire[i] = pixels_valid[i] && pixels_ready[i];
        end
    end

    always @(posedge clock) begin : sequential_2
        integer i;
        integer a;
        if (reset || fifo_flush) begin
            for (i = 0; i < 4; i = i + 1) begin
                fifo_enqueue_ptr[i] <= 3'd0;
                fifo_dequeue_ptr[i] <= 3'd0;
                fifo_count[i] <= 3'd0;
            end
        end else begin
            for (i = 0; i < 4; i = i + 1) begin
                if (fifo_enqueue_fire[i]) begin
                    fifo_mem_opaque[i][fifo_enqueue_ptr[i]] <= enqueue_opaque[i];
                    fifo_mem_color[i][fifo_enqueue_ptr[i]] <= enqueue_color[i];
                    fifo_enqueue_ptr[i] <= (fifo_enqueue_ptr[i] == 3'd4)
                        ? 3'd0 : fifo_enqueue_ptr[i] + 3'd1;
                end
                if (fifo_dequeue_fire[i]) begin
                    fifo_dequeue_ptr[i] <= (fifo_dequeue_ptr[i] == 3'd4)
                        ? 3'd0 : fifo_dequeue_ptr[i] + 3'd1;
                end
                case ({fifo_enqueue_fire[i], fifo_dequeue_fire[i]})
                    2'b10: fifo_count[i] <= fifo_count[i] + 3'd1;
                    2'b01: fifo_count[i] <= fifo_count[i] - 3'd1;
                    default: begin end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
