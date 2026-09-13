`timescale 1ns/1ps
`default_nettype none

// =============================================================================
//  ppu.v
//  Renderer-level GBA PPU integration and scan-timing generator.
//
//  A frame contains 228 scanlines of 1232 `clock` cycles. Active-high `reset`
//  clears the timing state synchronously; deasserted `enable` freezes timing
//  and all three child pipelines. This module connects `bg_renderer`,
//  `obj_renderer`, and `compositor`; IO registers and physical memories remain
//  in the board top.
//
//  External address units:
//      BG/OBJ VRAM - byte addresses
//      OAM         - 32-bit word indices
//      palette     - 16-bit halfword indices
//
//  All memory return paths assume one synchronous read cycle. Early BG
//  prefetch uses the DISPCNT value entering the cycle-40 visible latch, while
//  its CPU/DMA contention qualifier remains on the current visible latch. OBJ
//  memory traffic uses the live enable bit and is unaffected by force blank.
//  Green Swap buffers final-pixel pairs only on lines that begin enabled;
//  their output valid stream starts four clocks later and flushes at tick 1010.
//  The 15-bit pixel stream is renderer output, not a complete VGA timing or
//  color-conversion interface.
// =============================================================================
module ppu (
    input              clock,
    input              reset,
    input              enable,

    input      [2:0]   display_mode,
    input              display_frame,
    input              display_force_blank,
    input              display_green_swap,
    input              display_enable_obj,
    input      [3:0]   display_enable_bg,
    input      [1:0]   display_window,
    input              display_obj_window,
    input              display_obj_mapping,
    input              display_hblank_free,

    input      [7:0]   bg_size,
    input      [3:0]   bg_affine_wrap,
    input      [19:0]  bg_screen_base,
    input      [3:0]   bg_bpp8,
    input      [3:0]   bg_mosaic,
    input      [7:0]   bg_char_base,
    input      [7:0]   bg_priority,
    input      [63:0]  bg_off_x,
    input      [63:0]  bg_off_y,
    input      [31:0]  bg_aff_pa,
    input      [31:0]  bg_aff_pb,
    input      [31:0]  bg_aff_pc,
    input      [31:0]  bg_aff_pd,
    input      [55:0]  bg_aff_x,
    input      [55:0]  bg_aff_y,
    input      [1:0]   write_aff_x,
    input      [1:0]   write_aff_y,

    input      [3:0]   mosaic_bg_x,
    input      [3:0]   mosaic_bg_y,
    input      [3:0]   mosaic_obj_x,
    input      [3:0]   mosaic_obj_y,

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

    output             bg_vram_read,
    output             bg_vram_contention,
    output     [16:0]  bg_vram_address,
    input      [15:0]  bg_vram_read_data,

    output             obj_vram_read,
    output     [14:0]  obj_vram_address,
    input      [15:0]  obj_vram_read_data,

    output             oam_read,
    output     [7:0]   oam_address,
    input      [31:0]  oam_read_data,

    output             palette_read,
    output     [8:0]   palette_address,
    input      [15:0]  palette_read_data,

    output             output_valid,
    output     [14:0]  output_pixel,
    output             output_hblank,
    output             output_vblank,

    // Exposed for the external DISPSTAT, IRQ, and DMA-trigger logic.
    output reg [10:0]  tick,
    output reg [7:0]   scanline
);

    // 1232 clocks per scanline and 228 scanlines per
    // frame.  A disabled PPU freezes both counters and all renderer state.
    always @(posedge clock) begin
        if (reset) begin
            tick <= 11'd0;
            scanline <= 8'd0;
        end else if (enable) begin
            if (tick < 11'd1231) begin
                tick <= tick + 11'd1;
            end else begin
                tick <= 11'd0;
                if (scanline < 8'd227) begin
                    scanline <= scanline + 8'd1;
                end else begin
                    scanline <= 8'd0;
                end
            end
        end
    end

    // BG visibility/access enable takes effect only after DISPCNT has crossed
    // the three cycle-40 scanline latches. Force blank takes effect immediately
    // when set and remains active until the cleared value crosses those latches.
    // OBJ memory fetches deliberately continue to use the live enable below.
    wire [5:0] dispcnt_current = {
        display_force_blank, display_enable_obj, display_enable_bg
    };
    reg [5:0] dispcnt_latch_0;
    reg [5:0] dispcnt_latch_1;
    reg [5:0] dispcnt_latch_2;

    always @(posedge clock) begin
        if (reset) begin
            dispcnt_latch_0 <= 6'd0;
            dispcnt_latch_1 <= 6'd0;
            dispcnt_latch_2 <= 6'd0;
        end else if (enable && (tick == 11'd39)) begin
            dispcnt_latch_0 <= dispcnt_latch_1;
            dispcnt_latch_1 <= dispcnt_latch_2;
            dispcnt_latch_2 <= dispcnt_current;
        end
    end

    wire [3:0] effective_enable_bg =
        display_enable_bg & dispcnt_latch_0[3:0];
    wire effective_enable_obj =
        display_enable_obj & dispcnt_latch_0[4];
    wire effective_force_blank =
        display_force_blank | dispcnt_latch_0[5];
    wire [3:0] display_contention_bg =
        effective_enable_bg & {4{!effective_force_blank}};
    wire [5:0] dispcnt_fetch_latch =
        (tick < 11'd40) ? dispcnt_latch_1 : dispcnt_latch_0;
    wire [3:0] display_access_bg = display_enable_bg
        & dispcnt_fetch_latch[3:0]
        & {4{!display_force_blank && !dispcnt_fetch_latch[5]}};

    // Ppu deliberately asserts the video hblank output one clock after
    // its internal DISPSTAT hblank boundary.  Its video vblank output remains
    // asserted on scanline 227 as well.
    assign output_hblank = tick > 11'd1006;
    assign output_vblank = scanline >= 8'd160;

    wire [15:0] bg_vram_halfword_address;
    wire [13:0] obj_vram_halfword_address;

    wire [3:0]  bg_pixels_valid;
    wire [3:0]  bg_pixels_ready;
    wire [3:0]  bg_pixels_opaque;
    wire [31:0] bg_pixels_color;

    wire [7:0]  object_index;
    wire        object_read;
    wire [13:0] object_data;

    wire        compositor_valid;
    wire [14:0] compositor_pixel;

    // Green Swap exchanges only the green fields of each adjacent final-pixel
    // pair. The compositor produces one pixel every four clocks, so lines that
    // begin with Green Swap enabled retain the first pixel until its partner is
    // available. The existing renderer presents that pixel ten clocks after
    // the hardware merge phase (which begins eight clocks before `tick == 0`).
    // Delay only the register qualifier so mid-line DMA writes are applied to
    // the pair that was actually at the merge stage, not a later pair. A line
    // starting disabled retains the legacy zero-latency stream: enabling it
    // mid-line would require a permanently delayed output or merge lookahead.
    reg         green_swap_line;
    reg         green_swap_expect_odd;
    reg [14:0]  green_swap_even_pixel;
    reg [14:0]  green_swap_right_pixel;
    reg         green_swap_right_ready;
    reg [9:0]   green_swap_history;

    wire green_swap_left_valid = compositor_valid
        && green_swap_line && green_swap_expect_odd;
    wire green_swap_right_output_valid = compositor_valid
        && green_swap_line && !green_swap_expect_odd
        && green_swap_right_ready;
    wire green_swap_flush_valid = enable && green_swap_line
        && green_swap_right_ready && (scanline < 8'd160)
        && (tick == 11'd1010);

    assign output_valid = green_swap_line
        ? (green_swap_left_valid || green_swap_right_output_valid
           || green_swap_flush_valid)
        : compositor_valid;
    assign output_pixel = !green_swap_line ? compositor_pixel
        : green_swap_left_valid
            ? (green_swap_history[9]
                ? {green_swap_even_pixel[14:10], compositor_pixel[9:5],
                   green_swap_even_pixel[4:0]}
                : green_swap_even_pixel)
            : green_swap_right_pixel;

    always @(posedge clock) begin
        if (reset) begin
            green_swap_line <= 1'b0;
            green_swap_expect_odd <= 1'b0;
            green_swap_even_pixel <= 15'd0;
            green_swap_right_pixel <= 15'd0;
            green_swap_right_ready <= 1'b0;
            green_swap_history <= 10'd0;
        end else if (enable) begin
            green_swap_history <= {green_swap_history[8:0],
                                   display_green_swap};
            if (tick == 11'd0) begin
                green_swap_line <= 1'b0;
                green_swap_expect_odd <= 1'b0;
                green_swap_right_ready <= 1'b0;
            end
            if (tick == 11'd40) begin
                green_swap_line <= display_green_swap;
            end
            if (compositor_valid && green_swap_line) begin
                if (!green_swap_expect_odd) begin
                    green_swap_even_pixel <= compositor_pixel;
                    green_swap_expect_odd <= 1'b1;
                end else begin
                    green_swap_right_pixel <= green_swap_history[9]
                        ? {compositor_pixel[14:10],
                           green_swap_even_pixel[9:5], compositor_pixel[4:0]}
                        : compositor_pixel;
                    green_swap_right_ready <= 1'b1;
                    green_swap_expect_odd <= 1'b0;
                end
            end
        end
    end

    // Renderer addresses are halfword indices; the external VRAM interface is
    // byte addressed.  Conversion belongs here, immediately upstream of VRAM.
    assign bg_vram_address = {bg_vram_halfword_address, 1'b0};
    assign obj_vram_address = {obj_vram_halfword_address, 1'b0};

    bg_renderer background_renderer (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .display_mode(display_mode),
        .display_frame(display_frame),
        .display_enable_bg(display_enable_bg),
        .display_effective_enable_bg(effective_enable_bg),
        .display_access_bg(display_access_bg),
        .display_contention_bg(display_contention_bg),
        .bg_size(bg_size),
        .bg_affine_wrap(bg_affine_wrap),
        .bg_screen_base(bg_screen_base),
        .bg_bpp8(bg_bpp8),
        .bg_mosaic(bg_mosaic),
        .bg_char_base(bg_char_base),
        .bg_off_x(bg_off_x),
        .bg_off_y(bg_off_y),
        .bg_aff_pa(bg_aff_pa),
        .bg_aff_pb(bg_aff_pb),
        .bg_aff_pc(bg_aff_pc),
        .bg_aff_pd(bg_aff_pd),
        .bg_aff_x(bg_aff_x),
        .bg_aff_y(bg_aff_y),
        .write_aff_x(write_aff_x),
        .write_aff_y(write_aff_y),
        .mosaic_y(mosaic_bg_y),
        .vram_read(bg_vram_read),
        .vram_contention(bg_vram_contention),
        .vram_address(bg_vram_halfword_address),
        .vram_read_data(bg_vram_read_data),
        .tick(tick),
        .scanline(scanline),
        .pixels_valid(bg_pixels_valid),
        .pixels_ready(bg_pixels_ready),
        .pixels_opaque(bg_pixels_opaque),
        .pixels_color(bg_pixels_color)
    );

    obj_renderer object_renderer (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .display_enable_obj(display_enable_obj),
        .display_obj_mapping(display_obj_mapping),
        .display_hblank_free(display_hblank_free),
        .mosaic_y(mosaic_obj_y),
        .vram_read(obj_vram_read),
        .vram_address(obj_vram_halfword_address),
        .vram_read_data(obj_vram_read_data),
        .oam_read(oam_read),
        .oam_address(oam_address),
        .oam_read_data(oam_read_data),
        .tick(tick),
        .scanline(scanline),
        .buffer_index(object_index),
        .buffer_read(object_read),
        .buffer_data(object_data)
    );

    compositor compositor (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .display_mode(display_mode),
        .display_force_blank(effective_force_blank),
        .display_enable_obj(effective_enable_obj),
        .display_enable_bg(effective_enable_bg),
        .display_window(display_window),
        .display_obj_window(display_obj_window),
        .bg_priority(bg_priority),
        .bg_mosaic(bg_mosaic),
        .win0_x_start(win0_x_start),
        .win0_x_end(win0_x_end),
        .win0_y_start(win0_y_start),
        .win0_y_end(win0_y_end),
        .win1_x_start(win1_x_start),
        .win1_x_end(win1_x_end),
        .win1_y_start(win1_y_start),
        .win1_y_end(win1_y_end),
        .win0_control(win0_control),
        .win1_control(win1_control),
        .win_out_control(win_out_control),
        .win_obj_control(win_obj_control),
        .blend_effect(blend_effect),
        .blend_top_bg(blend_top_bg),
        .blend_top_obj(blend_top_obj),
        .blend_top_backdrop(blend_top_backdrop),
        .blend_bottom_bg(blend_bottom_bg),
        .blend_bottom_obj(blend_bottom_obj),
        .blend_bottom_backdrop(blend_bottom_backdrop),
        .blend_alpha_a(blend_alpha_a),
        .blend_alpha_b(blend_alpha_b),
        .blend_fade(blend_fade),
        .mosaic_bg_x(mosaic_bg_x),
        .mosaic_obj_x(mosaic_obj_x),
        .tick(tick),
        .scanline(scanline),
        .palette_read(palette_read),
        .palette_address(palette_address),
        .palette_read_data(palette_read_data),
        .valid(compositor_valid),
        .pixel(compositor_pixel),
        .bg_valid(bg_pixels_valid),
        .bg_ready(bg_pixels_ready),
        .bg_opaque(bg_pixels_opaque),
        .bg_color(bg_pixels_color),
        .object_index(object_index),
        .object_read(object_read),
        .object_data(object_data)
    );

endmodule

`default_nettype wire
