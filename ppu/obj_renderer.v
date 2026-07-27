`timescale 1ns/1ps
`default_nettype none

// =============================================================================
//  obj_renderer.v
//  GBA object scanner, tile fetcher, and double-buffered scanline renderer.
//
//  The OAM state machine scans 128 objects and their affine parameters. The
//  fetch path handles affine/non-affine objects, 4/8 bpp tiles, 1D/2D mapping,
//  OBJ-window/semitransparent flags, and vertical mosaic. It renders into one
//  240-pixel buffer while the compositor reads the previous scanline.
//
//  VRAM addresses are 16-bit halfword indices within OBJ character VRAM; OAM
//  addresses are 32-bit word indices. Requests use the even-tick/odd-tick
//  pipeline cadence. `buffer_data` is
//  {opaque, color[7:0], priority[1:0], window, blend, mosaic}.
// =============================================================================
module obj_renderer (
    input              clock,
    input              reset,
    input              enable,

    input              display_enable_obj,
    input              display_obj_mapping,
    input              display_hblank_free,
    input      [3:0]   mosaic_y,

    output reg         vram_read,
    output reg [13:0]  vram_address,
    input      [15:0]  vram_read_data,

    output reg         oam_read,
    output reg [7:0]   oam_address,
    input      [31:0]  oam_read_data,

    input      [10:0]  tick,
    input      [7:0]   scanline,

    input      [7:0]   buffer_index,
    input              buffer_read,
    output     [13:0]  buffer_data
);

    localparam [2:0] OAM_ATTR01 = 3'd0;
    localparam [2:0] OAM_ATTR2  = 3'd1;
    localparam [2:0] OAM_PA     = 3'd2;
    localparam [2:0] OAM_PB     = 3'd3;
    localparam [2:0] OAM_PC     = 3'd4;
    localparam [2:0] OAM_PD     = 3'd5;
    localparam [2:0] OAM_START  = 3'd6;
    localparam [2:0] OAM_DONE   = 3'd7;

    reg active;
    reg [7:0] render_y;
    reg [7:0] render_y_mosaic;
    reg [3:0] mosaic_counter;
    wire even_tick;

    reg [13:0] buffer0 [0:239];
    reg [13:0] buffer1 [0:239];
    reg buffer_page;

    reg [8:0] draw_x;
    reg [1:0] draw_count;
    reg [13:0] draw_data0;
    reg [13:0] draw_data1;

    reg fetch_active;
    reg allow_oam;
    reg [7:0] fetch_col;

    reg [8:0] fetch_obj_x;
    reg [6:0] fetch_obj_row;
    reg [4:0] fetch_obj_w;
    reg [4:0] fetch_obj_h;
    reg [3:0] fetch_obj_tex_w;
    reg [3:0] fetch_obj_tex_h;
    reg [9:0] fetch_obj_tile;
    reg [3:0] fetch_obj_palette_bank;
    reg fetch_obj_bpp8;
    reg [1:0] fetch_obj_priority;
    reg fetch_obj_flip_x;
    reg fetch_obj_affine;
    reg fetch_obj_window;
    reg fetch_obj_blend;
    reg fetch_obj_mosaic;

    reg signed [27:0] fetch_aff_x;
    reg signed [27:0] fetch_aff_y;
    reg signed [15:0] fetch_pa;
    reg signed [15:0] fetch_pb;
    reg signed [15:0] fetch_pc;
    reg signed [15:0] fetch_pd;

    reg [6:0] oam_index;
    reg [6:0] next_oam_index;
    reg [2:0] state;
    reg [2:0] next_state;
    reg [4:0] oam_affine_index;

    reg [8:0] oam_attrs_x;
    reg [6:0] oam_attrs_row;
    reg [4:0] oam_attrs_w;
    reg [4:0] oam_attrs_h;
    reg [3:0] oam_attrs_tex_w;
    reg [3:0] oam_attrs_tex_h;
    reg oam_attrs_bpp8;
    reg oam_attrs_flip_x;
    reg oam_attrs_affine;
    reg oam_attrs_window;
    reg oam_attrs_blend;
    reg oam_attrs_mosaic;

    reg [15:0] fetch_coord_col;
    reg [15:0] fetch_coord_row;
    reg [3:0] fetch_tile_x;
    reg [3:0] fetch_tile_y;
    reg [2:0] fetch_subtile_x;
    reg [2:0] fetch_subtile_y;
    reg [2:0] fetch_tile_stride;
    reg [9:0] fetch_tile_offset;

    wire [15:0] attr0;
    wire [15:0] attr1;
    wire [15:0] attr2;
    wire [3:0] decoded_width;
    wire [3:0] decoded_height;
    wire [7:0] decoded_obj_y;
    wire [7:0] decoded_row;
    wire [7:0] decoded_bounding_h;
    wire [7:0] decoded_y_max;
    wire decoded_in_range;

    wire [8:0] fetch_width_pixels;
    wire [8:0] fetch_height_pixels;
    wire [8:0] affine_clip_full;
    wire [7:0] affine_start_col;
    wire signed [9:0] affine_offset_x;
    wire signed [9:0] affine_offset_y;
    wire signed [27:0] affine_start_x;
    wire signed [27:0] affine_start_y;

    function [3:0] object_width_tiles;
        input [1:0] shape;
        input [1:0] size;
        begin
            case (shape)
                2'd0: object_width_tiles = 4'd1 << size;
                2'd1: begin
                    case (size)
                        2'd0: object_width_tiles = 4'd2;
                        2'd1: object_width_tiles = 4'd4;
                        2'd2: object_width_tiles = 4'd4;
                        default: object_width_tiles = 4'd8;
                    endcase
                end
                2'd2: begin
                    case (size)
                        2'd0: object_width_tiles = 4'd1;
                        2'd1: object_width_tiles = 4'd1;
                        2'd2: object_width_tiles = 4'd2;
                        default: object_width_tiles = 4'd4;
                    endcase
                end
                default: object_width_tiles = 4'd1;
            endcase
        end
    endfunction

    function [3:0] object_height_tiles;
        input [1:0] shape;
        input [1:0] size;
        begin
            case (shape)
                2'd0: object_height_tiles = 4'd1 << size;
                2'd1: begin
                    case (size)
                        2'd0: object_height_tiles = 4'd1;
                        2'd1: object_height_tiles = 4'd1;
                        2'd2: object_height_tiles = 4'd2;
                        default: object_height_tiles = 4'd4;
                    endcase
                end
                2'd2: begin
                    case (size)
                        2'd0: object_height_tiles = 4'd2;
                        2'd1: object_height_tiles = 4'd4;
                        2'd2: object_height_tiles = 4'd4;
                        default: object_height_tiles = 4'd8;
                    endcase
                end
                default: object_height_tiles = 4'd1;
            endcase
        end
    endfunction

    function [2:0] width_to_stride;
        input [3:0] width;
        begin
            case (width)
                4'd1: width_to_stride = 3'd0;
                4'd2: width_to_stride = 3'd1;
                4'd4: width_to_stride = 3'd2;
                default: width_to_stride = 3'd3;
            endcase
        end
    endfunction

    function [3:0] select_nibble;
        input [15:0] data;
        input [1:0] index;
        begin
            case (index)
                2'd0: select_nibble = data[3:0];
                2'd1: select_nibble = data[7:4];
                2'd2: select_nibble = data[11:8];
                default: select_nibble = data[15:12];
            endcase
        end
    endfunction

    function [13:0] make_buffer_entry;
        input opaque;
        input [7:0] color;
        input [1:0] prio;
        input window;
        input blend;
        input mosaic;
        begin
            make_buffer_entry = {opaque, color, prio, window, blend, mosaic};
        end
    endfunction

    assign even_tick = tick[0] == 1'b0;
    assign attr0 = oam_read_data[15:0];
    assign attr1 = oam_read_data[31:16];
    assign attr2 = oam_read_data[15:0];

    assign decoded_width = object_width_tiles(attr0[15:14], attr1[15:14]);
    assign decoded_height = object_height_tiles(attr0[15:14], attr1[15:14]);
    assign decoded_obj_y = attr0[12] ? render_y_mosaic : render_y;
    assign decoded_row = decoded_obj_y - attr0[7:0];
    assign decoded_bounding_h = attr0[9]
        ? ({4'd0, decoded_height} << 4)
        : ({4'd0, decoded_height} << 3);
    assign decoded_y_max = attr0[7:0] + decoded_bounding_h;
    assign decoded_in_range =
        ((render_y >= attr0[7:0]) || (decoded_y_max < attr0[7:0]))
        && (render_y < decoded_y_max);

    assign fetch_width_pixels = {4'd0, fetch_obj_w} << 3;
    assign fetch_height_pixels = {4'd0, fetch_obj_h} << 3;
    assign affine_clip_full = (~fetch_obj_x) + 9'd1;
    assign affine_start_col = (fetch_obj_x >= 9'd240)
        ? affine_clip_full[7:0] : 8'd0;
    assign affine_offset_x = $signed({2'b00, affine_start_col})
        - $signed({3'b000, fetch_obj_w, 2'b00});
    assign affine_offset_y = $signed({3'b000, oam_attrs_row})
        - $signed({3'b000, fetch_obj_h, 2'b00});
    assign affine_start_x =
        ($signed(fetch_pb) * $signed(affine_offset_y))
        + ($signed(fetch_pa) * $signed(affine_offset_x));
    assign affine_start_y =
        ($signed(fetch_pd) * $signed(affine_offset_y))
        + ($signed(fetch_pc) * $signed(affine_offset_x));

    // The compositor reads the page completed on the previous scanline.
    assign buffer_data = buffer_page ? buffer0[buffer_index] : buffer1[buffer_index];

    // Traditional OAM current-state/next-state decoder.
    always @* begin
        next_state = state;
        next_oam_index = oam_index;

        if (enable && active && allow_oam && !even_tick) begin
            case (state)
                OAM_ATTR01: begin
                    if (decoded_in_range && !(attr0[9] && !attr0[8])) begin
                        next_state = OAM_ATTR2;
                    end else if (oam_index == 7'd127) begin
                        next_state = OAM_DONE;
                        next_oam_index = 7'd0;
                    end else begin
                        next_state = OAM_ATTR01;
                        next_oam_index = oam_index + 7'd1;
                    end
                end
                OAM_ATTR2: begin
                    if (oam_attrs_affine) begin
                        next_state = OAM_PA;
                    end else if (oam_index == 7'd127) begin
                        next_state = OAM_DONE;
                        next_oam_index = 7'd0;
                    end else begin
                        next_state = OAM_ATTR01;
                        next_oam_index = oam_index + 7'd1;
                    end
                end
                OAM_PA: next_state = OAM_PB;
                OAM_PB: next_state = OAM_PC;
                OAM_PC: next_state = OAM_PD;
                OAM_PD: next_state = OAM_START;
                OAM_START: begin
                    if (oam_index == 7'd127) begin
                        next_state = OAM_DONE;
                        next_oam_index = 7'd0;
                    end else begin
                        next_state = OAM_ATTR01;
                        next_oam_index = oam_index + 7'd1;
                    end
                end
                default: begin
                    next_state = OAM_DONE;
                end
            endcase
        end
    end

    // OAM requests occupy even ticks; their data is consumed on odd ticks.
    always @* begin
        oam_read = 1'b0;
        oam_address = 8'd0;
        if (enable && active && allow_oam && even_tick) begin
            case (state)
                OAM_ATTR01: begin
                    oam_read = 1'b1;
                    oam_address = {oam_index, 1'b0};
                end
                OAM_ATTR2: begin
                    oam_read = 1'b1;
                    oam_address = {oam_index, 1'b1};
                end
                OAM_PA: begin
                    oam_read = 1'b1;
                    oam_address = {oam_affine_index, 3'b001};
                end
                OAM_PB: begin
                    oam_read = 1'b1;
                    oam_address = {oam_affine_index, 3'b011};
                end
                OAM_PC: begin
                    oam_read = 1'b1;
                    oam_address = {oam_affine_index, 3'b101};
                end
                OAM_PD: begin
                    oam_read = 1'b1;
                    oam_address = {oam_affine_index, 3'b111};
                end
                default: begin end
            endcase
        end
    end

    // OBJ character address generation.
    always @* begin
        fetch_coord_col = 16'd0;
        fetch_coord_row = 16'd0;
        fetch_tile_x = 4'd0;
        fetch_tile_y = 4'd0;
        fetch_subtile_x = 3'd0;
        fetch_subtile_y = 3'd0;
        fetch_tile_stride = 3'd0;
        fetch_tile_offset = 10'd0;
        vram_read = 1'b0;
        vram_address = 14'd0;

        if (!fetch_obj_affine) begin
            fetch_coord_col = fetch_obj_flip_x
                ? (fetch_col ^ (fetch_width_pixels[7:0] - 8'd1))
                : fetch_col;
            fetch_coord_row = fetch_obj_row;
        end else begin
            fetch_coord_col = fetch_aff_x[23:8]
                + ({12'd0, fetch_obj_tex_w} << 2);
            fetch_coord_row = fetch_aff_y[23:8]
                + ({12'd0, fetch_obj_tex_h} << 2);
        end

        fetch_tile_x = fetch_coord_col[6:3];
        fetch_tile_y = fetch_coord_row[6:3];
        fetch_subtile_x = fetch_coord_col[2:0];
        fetch_subtile_y = fetch_coord_row[2:0];
        fetch_tile_stride = display_obj_mapping
            ? width_to_stride(fetch_obj_tex_w)
            : (fetch_obj_bpp8 ? 3'd4 : 3'd5);
        fetch_tile_offset = {6'd0, fetch_tile_x}
            + ({6'd0, fetch_tile_y} << fetch_tile_stride);

        if (enable && fetch_active && even_tick) begin
            vram_read = 1'b1;
            if (fetch_obj_bpp8) begin
                vram_address = ({6'd0, fetch_tile_offset} << 5)
                    + ({6'd0, fetch_obj_tile} << 4)
                    + {9'd0, fetch_subtile_y, fetch_subtile_x[2:1]};
            end else begin
                vram_address = ({6'd0,
                                 (fetch_obj_tile + fetch_tile_offset)} << 4)
                    + {10'd0, fetch_subtile_y, fetch_subtile_x[2]};
            end
        end
    end

    always @(posedge clock) begin : renderer_sequential
        integer i;
        reg [13:0] old_entry;
        reg [13:0] new_entry;
        reg [8:0] clipped;
        reg [7:0] color0;
        reg [7:0] color1;
        reg pixel_opaque0;
        reg pixel_opaque1;
        reg [3:0] pixel_nibble;
        reg [1:0] nibble_index0;
        reg [1:0] nibble_index1;
        reg affine_in_bounds;

        if (reset) begin
            active <= 1'b0;
            render_y <= 8'd0;
            render_y_mosaic <= 8'd0;
            mosaic_counter <= 4'd0;
            buffer_page <= 1'b0;
            draw_x <= 9'd0;
            draw_count <= 2'd0;
            draw_data0 <= 14'd0;
            draw_data1 <= 14'd0;
            fetch_active <= 1'b0;
            allow_oam <= 1'b1;
            fetch_col <= 8'd0;
            fetch_aff_x <= 28'sd0;
            fetch_aff_y <= 28'sd0;
            fetch_pa <= 16'sd0;
            fetch_pb <= 16'sd0;
            fetch_pc <= 16'sd0;
            fetch_pd <= 16'sd0;
            oam_index <= 7'd0;
            state <= OAM_ATTR01;
            oam_affine_index <= 5'd0;
            for (i = 0; i < 240; i = i + 1) begin
                buffer0[i] <= 14'd0;
                buffer1[i] <= 14'd0;
            end
        end else if (enable) begin
            // Drain one queued pixel per clock into the current write page.
            if (draw_count != 2'd0) begin
                if (draw_x < 9'd240) begin
                    old_entry = buffer_page ? buffer1[draw_x] : buffer0[draw_x];
                    new_entry = old_entry;
                    if (draw_data0[2] && draw_data0[13]) begin
                        new_entry[2] = 1'b1;
                    end else if (!old_entry[13]
                                 || (draw_data0[4:3] < old_entry[4:3])) begin
                        if (draw_data0[13]) begin
                            new_entry[13] = 1'b1;
                            new_entry[12:5] = draw_data0[12:5];
                            new_entry[1] = draw_data0[1];
                        end
                        // Preserve the GBA transparent-pixel prio bug.
                        new_entry[4:3] = draw_data0[4:3];
                        new_entry[0] = draw_data0[0];
                    end

                    if (buffer_page) begin
                        buffer1[draw_x] <= new_entry;
                    end else begin
                        buffer0[draw_x] <= new_entry;
                    end
                end
                draw_data0 <= draw_data1;
                draw_count <= draw_count - 2'd1;
                draw_x <= draw_x + 9'd1;
            end

            // Register the next OAM state and consume returned OAM data.
            if (active && allow_oam) begin
                state <= next_state;
                oam_index <= next_oam_index;

                if (!even_tick) begin
                    case (state)
                        OAM_ATTR01: begin
                            oam_attrs_x <= attr1[8:0];
                            oam_attrs_row <= (attr1[13] && !attr0[8])
                                ? (decoded_row[6:0]
                                   ^ (({3'd0, decoded_height} << 3) - 7'd1))
                                : decoded_row[6:0];
                            oam_attrs_w <= attr0[9]
                                ? ({1'b0, decoded_width} << 1)
                                : {1'b0, decoded_width};
                            oam_attrs_h <= attr0[9]
                                ? ({1'b0, decoded_height} << 1)
                                : {1'b0, decoded_height};
                            oam_attrs_tex_w <= decoded_width;
                            oam_attrs_tex_h <= decoded_height;
                            oam_attrs_bpp8 <= attr0[13];
                            oam_attrs_flip_x <= attr1[12];
                            oam_attrs_affine <= attr0[8];
                            oam_attrs_window <= attr0[11:10] == 2'd2;
                            oam_attrs_blend <= attr0[11:10] == 2'd1;
                            oam_attrs_mosaic <= attr0[12];
                            oam_affine_index <= attr1[13:9];
                        end

                        OAM_ATTR2: begin
                            fetch_obj_x <= oam_attrs_x;
                            fetch_obj_row <= oam_attrs_row;
                            fetch_obj_w <= oam_attrs_w;
                            fetch_obj_h <= oam_attrs_h;
                            fetch_obj_tex_w <= oam_attrs_tex_w;
                            fetch_obj_tex_h <= oam_attrs_tex_h;
                            fetch_obj_tile <= attr2[9:0];
                            fetch_obj_palette_bank <= attr2[15:12];
                            fetch_obj_bpp8 <= oam_attrs_bpp8;
                            fetch_obj_priority <= attr2[11:10];
                            fetch_obj_flip_x <= oam_attrs_flip_x;
                            fetch_obj_affine <= oam_attrs_affine;
                            fetch_obj_window <= oam_attrs_window;
                            fetch_obj_blend <= oam_attrs_blend;
                            fetch_obj_mosaic <= oam_attrs_mosaic;

                            if (!oam_attrs_affine) begin
                                fetch_active <= 1'b1;
                                fetch_col <= 8'd0;
                                if (oam_attrs_x >= 9'd240) begin
                                    clipped = (~oam_attrs_x) + 9'd1;
                                    fetch_col <= {clipped[7:1], 1'b0};
                                    if (clipped >= ({4'd0, oam_attrs_w} << 3)) begin
                                        fetch_active <= 1'b0;
                                    end
                                end
                            end
                        end

                        OAM_PA: fetch_pa <= oam_read_data[31:16];
                        OAM_PB: fetch_pb <= oam_read_data[31:16];
                        OAM_PC: fetch_pc <= oam_read_data[31:16];
                        OAM_PD: fetch_pd <= oam_read_data[31:16];

                        OAM_START: begin
                            fetch_active <= 1'b1;
                            fetch_col <= affine_start_col;
                            if ((fetch_obj_x >= 9'd240)
                                && ({1'b0, affine_start_col}
                                    >= fetch_width_pixels)) begin
                                fetch_active <= 1'b0;
                            end
                            fetch_aff_x <= affine_start_x;
                            fetch_aff_y <= affine_start_y;
                        end
                        default: begin end
                    endcase
                end
            end

            // Consume VRAM data on odd ticks and advance the fetch column.
            if (fetch_active) begin
                if (!even_tick) begin
                    if (!fetch_obj_affine) begin
                        draw_x <= fetch_obj_x + fetch_col - 9'd1;
                        draw_count <= 2'd2;
                        if (fetch_obj_bpp8) begin
                            color0 = fetch_obj_flip_x
                                ? vram_read_data[15:8] : vram_read_data[7:0];
                            color1 = fetch_obj_flip_x
                                ? vram_read_data[7:0] : vram_read_data[15:8];
                            pixel_opaque0 = color0 != 8'd0;
                            pixel_opaque1 = color1 != 8'd0;
                        end else begin
                            nibble_index0 = {fetch_col[1], 1'b0};
                            nibble_index1 = {fetch_col[1], 1'b1};
                            if (fetch_obj_flip_x) begin
                                nibble_index0 = ~nibble_index0;
                                nibble_index1 = ~nibble_index1;
                            end
                            pixel_nibble = select_nibble(
                                vram_read_data, nibble_index0);
                            color0 = {fetch_obj_palette_bank, pixel_nibble};
                            pixel_opaque0 = pixel_nibble != 4'd0;
                            pixel_nibble = select_nibble(
                                vram_read_data, nibble_index1);
                            color1 = {fetch_obj_palette_bank, pixel_nibble};
                            pixel_opaque1 = pixel_nibble != 4'd0;
                        end
                        draw_data0 <= make_buffer_entry(
                            pixel_opaque0, color0, fetch_obj_priority,
                            fetch_obj_window, fetch_obj_blend, fetch_obj_mosaic);
                        draw_data1 <= make_buffer_entry(
                            pixel_opaque1, color1, fetch_obj_priority,
                            fetch_obj_window, fetch_obj_blend, fetch_obj_mosaic);
                    end else begin
                        affine_in_bounds =
                            (fetch_coord_col < ({12'd0, fetch_obj_tex_w} << 3))
                            && (fetch_coord_row < ({12'd0, fetch_obj_tex_h} << 3));
                        draw_x <= fetch_obj_x + fetch_col;
                        draw_count <= 2'd1;
                        if (fetch_obj_bpp8) begin
                            color0 = fetch_subtile_x[0]
                                ? vram_read_data[15:8] : vram_read_data[7:0];
                            pixel_opaque0 = color0 != 8'd0;
                        end else begin
                            pixel_nibble = select_nibble(
                                vram_read_data, fetch_subtile_x[1:0]);
                            color0 = {fetch_obj_palette_bank, pixel_nibble};
                            pixel_opaque0 = pixel_nibble != 4'd0;
                        end
                        draw_data0 <= make_buffer_entry(
                            affine_in_bounds && pixel_opaque0,
                            color0, fetch_obj_priority, fetch_obj_window,
                            fetch_obj_blend, fetch_obj_mosaic);
                        fetch_aff_x <= $signed(fetch_aff_x) + $signed(fetch_pa);
                        fetch_aff_y <= $signed(fetch_aff_y) + $signed(fetch_pc);
                    end

                    if (fetch_obj_affine) begin
                        allow_oam <= ((fetch_col + 8'd2) >> 3) == fetch_obj_w;
                    end else begin
                        allow_oam <= ((fetch_col + 8'd3) >> 3) == fetch_obj_w;
                    end
                end

                if (!fetch_obj_affine || !even_tick) begin
                    if ((({1'b0, fetch_col} + 9'd1) >> 3) == fetch_obj_w) begin
                        // OAM can launch the next object on the same odd tick
                        // as the previous object's final fetch. In the Scala
                        // source the later OAM block wins that assignment.
                        if (!(active && allow_oam && !even_tick
                              && (((state == OAM_ATTR2)
                                   && !oam_attrs_affine)
                                  || (state == OAM_START)))) begin
                            fetch_active <= 1'b0;
                        end
                    end else begin
                        fetch_col <= fetch_col + 8'd1;
                    end
                end
            end

            // Object rendering prepares the following scanline.
            if (active && (tick == (display_hblank_free ? 11'd1005 : 11'd39))) begin
                active <= 1'b0;
            end

            if (display_enable_obj
                && ((scanline < 8'd160) || (scanline == 8'd227))
                && (tick == 11'd39)) begin
                active <= 1'b1;
                render_y <= scanline + 8'd1;
                mosaic_counter <= mosaic_counter + 4'd1;
                if (mosaic_counter == mosaic_y) begin
                    mosaic_counter <= 4'd0;
                    render_y_mosaic <= scanline + 8'd1;
                end
                if (scanline == 8'd227) begin
                    render_y <= 8'd0;
                    render_y_mosaic <= 8'd0;
                    mosaic_counter <= 4'd0;
                end

                buffer_page <= !buffer_page;
                if (buffer_page == 1'b0) begin
                    for (i = 0; i < 240; i = i + 1) begin
                        buffer1[i] <= 14'd0;
                    end
                end else begin
                    for (i = 0; i < 240; i = i + 1) begin
                        buffer0[i] <= 14'd0;
                    end
                end

                oam_index <= 7'd0;
                state <= OAM_ATTR01;
                allow_oam <= 1'b1;
                fetch_active <= 1'b0;
                draw_count <= 2'd0;
            end
        end
    end

    // buffer_read is retained for interface compatibility; the Scala buffer
    // also exposes asynchronous read data regardless of this qualifier.
    wire unused_buffer_read;
    assign unused_buffer_read = buffer_read;

endmodule

`default_nettype wire
