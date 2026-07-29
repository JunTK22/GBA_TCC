`timescale 1ns/1ps
`default_nettype none

// The GBA compositor is a fixed four-phase pipeline rather than a controller
// with variable transitions. The phase is derived from the PPU tick so that
// palette requests and returned data remain cycle-for-cycle compatible with
// the Scala implementation:
//   0: request top palette entry     1: capture top palette entry
//   2: request bottom palette entry  3: capture bottom/pass to blend
//
// Packed inputs use BG0 in the least-significant element. Window controls are
// packed as {blend, obj, bg[3:0]}. object_data is packed as
// {opaque, color[7:0], priority[1:0], window, blend, mosaic}.
module compositor (
    input              clock,
    input              reset,
    input              enable,

    input      [2:0]   display_mode,
    input              display_force_blank,
    input              display_enable_obj,
    input      [3:0]   display_enable_bg,
    input      [1:0]   display_window,
    input              display_obj_window,

    input      [7:0]   bg_priority,
    input      [3:0]   bg_mosaic,

    input      [7:0]   win0_x_start,
    input      [7:0]   win0_x_end,
    input      [7:0]   win0_y_start,
    input      [7:0]   win0_y_end,
    input      [7:0]   win1_x_start,
    input      [7:0]   win1_x_end,
    input      [7:0]   win1_y_start,
    input      [7:0]   win1_y_end,
    input      [5:0]   win0_control,
    input      [5:0]   win1_control,
    input      [5:0]   win_out_control,
    input      [5:0]   win_obj_control,

    input      [1:0]   blend_effect,
    input      [3:0]   blend_top_bg,
    input              blend_top_obj,
    input              blend_top_backdrop,
    input      [3:0]   blend_bottom_bg,
    input              blend_bottom_obj,
    input              blend_bottom_backdrop,
    input      [4:0]   blend_alpha_a,
    input      [4:0]   blend_alpha_b,
    input      [4:0]   blend_fade,

    input      [3:0]   mosaic_bg_x,
    input      [3:0]   mosaic_obj_x,

    input      [10:0]  tick,
    input      [7:0]   scanline,

    output reg         palette_read,
    output reg [8:0]   palette_address,
    input      [15:0]  palette_read_data,

    output reg         valid,
    output reg [14:0]  pixel,

    input      [3:0]   bg_valid,
    output reg [3:0]   bg_ready,
    input      [3:0]   bg_opaque,
    input      [31:0]  bg_color,

    output reg [7:0]   object_index,
    output reg         object_read,
    input      [13:0]  object_data
);

    localparam [1:0] PHASE_TOP_REQUEST    = 2'd0;
    localparam [1:0] PHASE_TOP_CAPTURE    = 2'd1;
    localparam [1:0] PHASE_BOTTOM_REQUEST = 2'd2;
    localparam [1:0] PHASE_BOTTOM_CAPTURE = 2'd3;

    localparam [1:0] EFFECT_NONE  = 2'd0;
    localparam [1:0] EFFECT_ALPHA = 2'd1;
    localparam [1:0] EFFECT_WHITE = 2'd2;
    localparam [1:0] EFFECT_BLACK = 2'd3;

    wire [1:0] phase;
    wire is_bitmap_16bpp;

    reg active;
    reg [7:0] fetch_x;
    reg win0_active_x;
    reg win1_active_x;
    reg win0_active_y;
    reg win1_active_y;
    reg [3:0] mosaic_obj_counter;
    reg [3:0] mosaic_bg_counter;

    reg sort_first_backdrop;
    reg sort_first_obj;
    reg [3:0] sort_first_bg;
    reg [14:0] sort_first_color;
    reg [1:0] sort_first_priority;
    reg sort_second_backdrop;
    reg sort_second_obj;
    reg [3:0] sort_second_bg;
    reg [14:0] sort_second_color;
    reg [1:0] sort_second_priority;
    reg [5:0] sort_window;
    reg sort_obj_blend;

    reg next_first_backdrop;
    reg next_first_obj;
    reg [3:0] next_first_bg;
    reg [14:0] next_first_color;
    reg [1:0] next_first_priority;
    reg next_second_backdrop;
    reg next_second_obj;
    reg [3:0] next_second_bg;
    reg [14:0] next_second_color;
    reg [1:0] next_second_priority;

    reg layer_first_backdrop;
    reg layer_first_obj;
    reg [3:0] layer_first_bg;
    reg [14:0] layer_first_color;
    reg layer_second_backdrop;
    reg layer_second_obj;
    reg [3:0] layer_second_bg;
    reg [14:0] layer_second_color;
    reg layer_window_blend;
    reg layer_obj_blend;

    reg blend_first_backdrop;
    reg blend_first_obj;
    reg [3:0] blend_first_bg;
    reg [14:0] blend_first_color;
    reg blend_second_backdrop;
    reg blend_second_obj;
    reg [3:0] blend_second_bg;
    reg [14:0] blend_second_color;
    reg blend_window;
    reg blend_obj;

    reg [13:0] sort_obj_mosaic;
    reg mosaic_bg_opaque [0:3];
    reg [14:0] mosaic_bg_color [0:3];

    wire [7:0] bg_color_i [0:3];
    wire [1:0] bg_priority_i [0:3];
    genvar bg_port;
    generate
        for (bg_port = 0; bg_port < 4; bg_port = bg_port + 1) begin : g_bg_ports
            assign bg_color_i[bg_port] = bg_color[(bg_port * 8) +: 8];
            assign bg_priority_i[bg_port] =
                bg_priority[(bg_port * 2) +: 2];
        end
    endgenerate

    reg [5:0] selected_window;
    reg [13:0] selected_object;
    reg object_mosaic_update;
    reg [14:0] raw_bg_color;
    reg raw_bg_opaque;
    reg [14:0] selected_bg_color;
    reg selected_bg_opaque;
    reg capture_bg_mosaic;

    wire object_opaque;
    wire [7:0] object_color;
    wire [1:0] object_priority;
    wire object_blend;

    wire blend_first_selected;
    wire blend_second_selected;
    wire is_obj_blend;
    wire [1:0] selected_blend_effect;
    wire blend_enabled;

    reg [14:0] effect_color_b;
    reg [4:0] effect_weight_a;
    reg [4:0] effect_weight_b;

    integer reset_i;

    function [4:0] blend_component;
        input [4:0] color_a;
        input [4:0] color_b;
        input [4:0] weight_a;
        input [4:0] weight_b;
        reg [9:0] product_a;
        reg [9:0] product_b;
        reg [10:0] result;
        begin
            product_a = color_a * weight_a;
            product_b = color_b * weight_b;
            result = (product_a + product_b) >> 4;
            blend_component = (result > 11'd31) ? 5'd31 : result[4:0];
        end
    endfunction

    function [14:0] do_blend;
        input [14:0] color_a;
        input [14:0] color_b;
        input [4:0] weight_a;
        input [4:0] weight_b;
        begin
            do_blend[4:0] = blend_component(
                color_a[4:0], color_b[4:0], weight_a, weight_b);
            do_blend[9:5] = blend_component(
                color_a[9:5], color_b[9:5], weight_a, weight_b);
            do_blend[14:10] = blend_component(
                color_a[14:10], color_b[14:10], weight_a, weight_b);
        end
    endfunction

    assign phase = tick[1:0] - 2'd2;
    assign is_bitmap_16bpp = (display_mode == 3'd3)
        || (display_mode == 3'd5);

    assign object_opaque = selected_object[13];
    assign object_color = selected_object[12:5];
    assign object_priority = selected_object[4:3];
    assign object_blend = selected_object[1];

    assign blend_first_selected =
        (blend_first_backdrop && blend_top_backdrop)
        || (blend_first_obj && blend_top_obj)
        || (|(blend_first_bg & blend_top_bg));
    assign blend_second_selected =
        (blend_second_backdrop && blend_bottom_backdrop)
        || (blend_second_obj && blend_bottom_obj)
        || (|(blend_second_bg & blend_bottom_bg));
    assign is_obj_blend = blend_first_obj && blend_obj;
    assign selected_blend_effect = (is_obj_blend && blend_second_selected)
        ? EFFECT_ALPHA : blend_effect;
    assign blend_enabled =
        (blend_window || is_obj_blend)
        && (selected_blend_effect != EFFECT_NONE)
        && (blend_first_selected
            || (is_obj_blend && blend_second_selected))
        && !((selected_blend_effect == EFFECT_ALPHA)
             && !blend_second_selected);

    // Window selection applies to the object and backgrounds of the next
    // pixel. Window 0 has priority over window 1 and the object window.
    always @* begin : window_selection
        selected_window = 6'b11_1111;
        if ((display_window != 2'b00) || display_obj_window) begin
            if (display_window[0] && win0_active_x && win0_active_y) begin
                selected_window = win0_control;
            end else if (display_window[1]
                         && win1_active_x && win1_active_y) begin
                selected_window = win1_control;
            end else if (display_obj_window && object_data[2]) begin
                selected_window = win_obj_control;
            end else begin
                selected_window = win_out_control;
            end
        end
    end

    // Horizontal OBJ mosaic is evaluated only once per pixel, during phase 3.
    always @* begin : object_mosaic_selection
        object_mosaic_update = !object_data[0]
            || !sort_obj_mosaic[0]
            || (mosaic_obj_counter == 4'd0);
        selected_object = object_mosaic_update
            ? object_data : sort_obj_mosaic;
    end

    // Pull one background FIFO per phase and insert its pixel into the
    // already-sorted top-two list. Strict-less comparisons reproduce GBA tie
    // ordering: OBJ wins ties with BG, and lower-numbered BG wins BG ties.
    always @* begin : sort_next
        next_first_backdrop = sort_first_backdrop;
        next_first_obj = sort_first_obj;
        next_first_bg = sort_first_bg;
        next_first_color = sort_first_color;
        next_first_priority = sort_first_priority;
        next_second_backdrop = sort_second_backdrop;
        next_second_obj = sort_second_obj;
        next_second_bg = sort_second_bg;
        next_second_color = sort_second_color;
        next_second_priority = sort_second_priority;

        bg_ready = 4'b0000;
        raw_bg_color = {7'd0, bg_color_i[phase]};
        raw_bg_opaque = bg_opaque[phase];
        if (is_bitmap_16bpp && (phase == 2'd2)) begin
            raw_bg_color = {bg_color_i[3][6:0], bg_color_i[2]};
        end

        capture_bg_mosaic = !(bg_mosaic[phase]
                              && (mosaic_bg_counter != 4'd0));
        if (capture_bg_mosaic) begin
            selected_bg_color = raw_bg_color;
            selected_bg_opaque = raw_bg_opaque;
        end else begin
            selected_bg_color = mosaic_bg_color[phase];
            selected_bg_opaque = mosaic_bg_opaque[phase];
        end

        if (enable && active) begin
            if (display_enable_bg[phase]
                && !(is_bitmap_16bpp && (phase == 2'd3))) begin
                bg_ready[phase] = 1'b1;
            end
            if (is_bitmap_16bpp && (phase == 2'd2)) begin
                bg_ready[3] = 1'b1;
            end

            if (bg_valid[phase] && selected_bg_opaque
                && display_enable_bg[phase] && sort_window[phase]) begin
                if (sort_first_backdrop
                    || (bg_priority_i[phase] < sort_first_priority)) begin
                    next_first_backdrop = 1'b0;
                    next_first_obj = 1'b0;
                    next_first_bg = 4'b0001 << phase;
                    next_first_color = selected_bg_color;
                    next_first_priority = bg_priority_i[phase];

                    next_second_backdrop = sort_first_backdrop;
                    next_second_obj = sort_first_obj;
                    next_second_bg = sort_first_bg;
                    next_second_color = sort_first_color;
                    next_second_priority = sort_first_priority;
                end else if (sort_second_backdrop
                             || (bg_priority_i[phase]
                                 < sort_second_priority)) begin
                    next_second_backdrop = 1'b0;
                    next_second_obj = 1'b0;
                    next_second_bg = 4'b0001 << phase;
                    next_second_color = selected_bg_color;
                    next_second_priority = bg_priority_i[phase];
                end
            end
        end
    end

    // Memory request ports are combinational, as in PpuMemoryInterface.
    always @* begin : request_outputs
        palette_read = 1'b0;
        palette_address = 9'd0;
        object_read = 1'b0;
        object_index = fetch_x;

        // The OBJ scanline buffer is synchronous. Prefetch during phase 2 so
        // object_data is available for windowing and sorting during phase 3.
        // tick 40 is the first request cycle, before active is registered.
        if (enable && (phase == PHASE_BOTTOM_REQUEST)
            && (active
                || ((tick == 11'd40) && (scanline < 8'd160)))) begin
            object_read = 1'b1;
            object_index = fetch_x;
        end

        if (enable && active) begin
            if (tick >= 11'd46) begin
                case (phase)
                    PHASE_TOP_REQUEST: begin
                        if (layer_first_backdrop) begin
                            palette_read = 1'b1;
                            palette_address = 9'd0;
                        end else if (!(layer_first_bg[2]
                                       && is_bitmap_16bpp)) begin
                            palette_read = 1'b1;
                            palette_address = {
                                layer_first_obj, layer_first_color[7:0]};
                        end
                    end
                    PHASE_BOTTOM_REQUEST: begin
                        if (layer_second_backdrop) begin
                            palette_read = 1'b1;
                            palette_address = 9'd0;
                        end else if (!(layer_second_bg[2]
                                       && is_bitmap_16bpp)) begin
                            palette_read = 1'b1;
                            palette_address = {
                                layer_second_obj, layer_second_color[7:0]};
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end

    always @* begin : blend_values
        effect_color_b = blend_second_color;
        if (selected_blend_effect == EFFECT_WHITE) begin
            effect_color_b = 15'h7FFF;
        end else if (selected_blend_effect == EFFECT_BLACK) begin
            effect_color_b = 15'd0;
        end

        if (selected_blend_effect == EFFECT_ALPHA) begin
            effect_weight_a = blend_alpha_a[4] ? 5'd16 : blend_alpha_a;
            effect_weight_b = blend_alpha_b[4] ? 5'd16 : blend_alpha_b;
        end else begin
            effect_weight_b = blend_fade[4] ? 5'd16 : blend_fade;
            effect_weight_a = 5'd16 - effect_weight_b;
        end
    end

    always @* begin : pixel_output
        valid = 1'b0;
        pixel = blend_first_color;
        if (enable && active && (tick >= 11'd50)
            && (phase == PHASE_TOP_REQUEST)) begin
            valid = 1'b1;
            if (display_force_blank) begin
                pixel = 15'h7FFF;
            end else if (blend_enabled) begin
                pixel = do_blend(
                    blend_first_color, effect_color_b,
                    effect_weight_a, effect_weight_b);
            end
        end
    end

    always @(posedge clock) begin : compositor_sequential
        reg object_visible;
        if (reset) begin
            active <= 1'b0;
            fetch_x <= 8'd0;
            win0_active_x <= 1'b0;
            win1_active_x <= 1'b0;
            win0_active_y <= 1'b0;
            win1_active_y <= 1'b0;
            mosaic_obj_counter <= 4'd0;
            mosaic_bg_counter <= 4'd0;

            sort_first_backdrop <= 1'b1;
            sort_first_obj <= 1'b0;
            sort_first_bg <= 4'd0;
            sort_first_color <= 15'd0;
            sort_first_priority <= 2'd0;
            sort_second_backdrop <= 1'b1;
            sort_second_obj <= 1'b0;
            sort_second_bg <= 4'd0;
            sort_second_color <= 15'd0;
            sort_second_priority <= 2'd0;
            sort_window <= 6'b11_1111;
            sort_obj_blend <= 1'b0;
            sort_obj_mosaic <= 14'd0;

            layer_first_backdrop <= 1'b1;
            layer_first_obj <= 1'b0;
            layer_first_bg <= 4'd0;
            layer_first_color <= 15'd0;
            layer_second_backdrop <= 1'b1;
            layer_second_obj <= 1'b0;
            layer_second_bg <= 4'd0;
            layer_second_color <= 15'd0;
            layer_window_blend <= 1'b0;
            layer_obj_blend <= 1'b0;

            blend_first_backdrop <= 1'b1;
            blend_first_obj <= 1'b0;
            blend_first_bg <= 4'd0;
            blend_first_color <= 15'd0;
            blend_second_backdrop <= 1'b1;
            blend_second_obj <= 1'b0;
            blend_second_bg <= 4'd0;
            blend_second_color <= 15'd0;
            blend_window <= 1'b0;
            blend_obj <= 1'b0;

            for (reset_i = 0; reset_i < 4; reset_i = reset_i + 1) begin
                mosaic_bg_opaque[reset_i] <= 1'b0;
                mosaic_bg_color[reset_i] <= 15'd0;
            end
        end else if (enable) begin
            // Scanline and window timing.
            if (tick == 11'd0) begin
                fetch_x <= 8'd0;
                mosaic_obj_counter <= 4'd0;
                mosaic_bg_counter <= mosaic_bg_x;

                if (scanline == win0_y_start) begin
                    win0_active_y <= 1'b1;
                end
                if (scanline == win0_y_end) begin
                    win0_active_y <= 1'b0;
                end
                if (scanline == win1_y_start) begin
                    win1_active_y <= 1'b1;
                end
                if (scanline == win1_y_end) begin
                    win1_active_y <= 1'b0;
                end
            end
            if ((tick == 11'd40) && (scanline < 8'd160)) begin
                active <= 1'b1;
            end
            if (tick == 11'd1006) begin
                active <= 1'b0;
            end

            if ((tick >= 11'd40) && (tick[1:0] == 2'b00)) begin
                if (((tick - 11'd40) >> 2) == win0_x_start) begin
                    win0_active_x <= 1'b1;
                end
                if (((tick - 11'd40) >> 2) == win0_x_end) begin
                    win0_active_x <= 1'b0;
                end
                if (((tick - 11'd40) >> 2) == win1_x_start) begin
                    win1_active_x <= 1'b1;
                end
                if (((tick - 11'd40) >> 2) == win1_x_end) begin
                    win1_active_x <= 1'b0;
                end
            end

            // Priority sorting and mosaic latches.
            if (active) begin
                if (capture_bg_mosaic) begin
                    mosaic_bg_color[phase] <= raw_bg_color;
                    mosaic_bg_opaque[phase] <= raw_bg_opaque;
                end

                if (phase == PHASE_BOTTOM_CAPTURE) begin
                    layer_first_backdrop <= next_first_backdrop;
                    layer_first_obj <= next_first_obj;
                    layer_first_bg <= next_first_bg;
                    layer_first_color <= next_first_color;
                    layer_second_backdrop <= next_second_backdrop;
                    layer_second_obj <= next_second_obj;
                    layer_second_bg <= next_second_bg;
                    layer_second_color <= next_second_color;
                    layer_window_blend <= sort_window[5];
                    layer_obj_blend <= sort_obj_blend;

                    sort_window <= selected_window;
                    if (object_mosaic_update) begin
                        sort_obj_mosaic <= object_data;
                    end

                    mosaic_obj_counter <= mosaic_obj_counter + 4'd1;
                    if (mosaic_obj_counter == mosaic_obj_x) begin
                        mosaic_obj_counter <= 4'd0;
                    end
                    mosaic_bg_counter <= mosaic_bg_counter + 4'd1;
                    if (mosaic_bg_counter == mosaic_bg_x) begin
                        mosaic_bg_counter <= 4'd0;
                    end

                    object_visible = object_opaque
                        && selected_window[4] && display_enable_obj;
                    sort_obj_blend <= object_visible && object_blend;
                    sort_first_backdrop <= !object_visible;
                    sort_first_obj <= object_visible;
                    sort_first_bg <= 4'd0;
                    sort_first_color <= {7'd0, object_color};
                    sort_first_priority <= object_priority;
                    sort_second_backdrop <= 1'b1;
                    sort_second_obj <= 1'b0;
                    sort_second_bg <= 4'd0;
                    sort_second_color <= 15'd0;
                    sort_second_priority <= 2'd0;
                    fetch_x <= fetch_x + 8'd1;
                end else begin
                    sort_first_backdrop <= next_first_backdrop;
                    sort_first_obj <= next_first_obj;
                    sort_first_bg <= next_first_bg;
                    sort_first_color <= next_first_color;
                    sort_first_priority <= next_first_priority;
                    sort_second_backdrop <= next_second_backdrop;
                    sort_second_obj <= next_second_obj;
                    sort_second_bg <= next_second_bg;
                    sort_second_color <= next_second_color;
                    sort_second_priority <= next_second_priority;
                end

                // Palette return path and final blend-stage handoff.
                if (tick >= 11'd46) begin
                    if (phase == PHASE_TOP_CAPTURE) begin
                        if (layer_first_backdrop
                            || !(layer_first_bg[2] && is_bitmap_16bpp)) begin
                            layer_first_color <= palette_read_data[14:0];
                        end
                    end
                    if (phase == PHASE_BOTTOM_CAPTURE) begin
                        blend_first_backdrop <= layer_first_backdrop;
                        blend_first_obj <= layer_first_obj;
                        blend_first_bg <= layer_first_bg;
                        blend_first_color <= layer_first_color;
                        blend_second_backdrop <= layer_second_backdrop;
                        blend_second_obj <= layer_second_obj;
                        blend_second_bg <= layer_second_bg;
                        blend_second_color <= layer_second_color;
                        if (layer_second_backdrop
                            || !(layer_second_bg[2] && is_bitmap_16bpp)) begin
                            blend_second_color <= palette_read_data[14:0];
                        end
                        blend_window <= layer_window_blend;
                        blend_obj <= layer_obj_blend;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
