// =============================================================================
//  gba_timers.v
//  Four GBA 16-bit incrementing timers (TM0-TM3).
//
//  The bus address is byte addressed. Timer registers are sampled on the
//  inverse CPU clock, alongside io_registers. A reload write changes only the
//  reload latch; the counter is loaded from it on a 0->1 start transition or
//  after overflow. A single 32-bit reload/control write uses the new reload
//  value for the start transition, as documented by GBATEK.
//
//  Channels implement 1/64/256/1024 prescalers, TM1-TM3 count-up chaining,
//  reload-on-overflow, and per-channel IRQ pulses. Bus writes commit one
//  inverse-clock edge after acceptance. Start loads first and begins counting
//  after one further edge; stop includes the final tick at its commit edge.
// =============================================================================

`timescale 1ns / 1ps

module gba_timers (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [11:0] addr,
    input  wire [31:0] wdata,
    input  wire        we,
    input  wire [1:0]  size,

    output wire [15:0] tm0_count_o,
    output wire [15:0] tm0_control_o,
    output wire [15:0] tm1_count_o,
    output wire [15:0] tm1_control_o,
    output wire [15:0] tm2_count_o,
    output wire [15:0] tm2_control_o,
    output wire [15:0] tm3_count_o,
    output wire [15:0] tm3_control_o,
    output reg  [3:0]  irq_o
);

    reg [15:0] reload_value [0:3];
    reg [15:0] counter_value [0:3];
    reg [7:0]  control_value [0:3];
    reg [9:0]  prescale_count [0:3];
    reg [3:0]  start_load_wait;
    reg [3:0]  start_overflow;
    reg        timer_write_q;
    reg [1:0]  timer_index_q;
    reg [3:0]  byteena_q;
    reg [31:0] wdata_shifted_q;
    reg [15:0] reload_effective [0:3];
    reg [7:0]  control_effective [0:3];
    reg [7:0]  tick_control [0:3];
    reg [3:0]  start_rise;
    reg [3:0]  stop_fall;
    reg [3:0]  timer_tick;
    reg [3:0]  timer_overflow;

    wire [1:0] byte_lane = addr[1:0];
    wire       misaligned = ((size == 2'b01) && addr[0]) ||
                            ((size == 2'b10) && |addr[1:0]);
    wire       timer_write = we && !misaligned &&
                             (addr[11:4] == 8'h10);
    wire [1:0] timer_index = addr[3:2];

    reg [3:0] byteena;
    always @(*) begin
        case (size)
            2'b00: byteena = 4'b0001 << byte_lane;
            2'b01: byteena = addr[1] ? 4'b1100 : 4'b0011;
            2'b10: byteena = 4'b1111;
            default: byteena = 4'b0000;
        endcase
    end

    reg [31:0] wdata_shifted;
    always @(*) begin
        case (size)
            2'b00: wdata_shifted = {4{wdata[7:0]}};
            2'b01: wdata_shifted = addr[1] ? {wdata[15:0], 16'd0}
                                           : {16'd0, wdata[15:0]};
            2'b10: wdata_shifted = wdata;
            default: wdata_shifted = 32'd0;
        endcase
    end

    function automatic [9:0] prescale_terminal;
        input [1:0] selection;
        begin
            case (selection)
                2'b00: prescale_terminal = 10'd0;
                2'b01: prescale_terminal = 10'd63;
                2'b10: prescale_terminal = 10'd255;
                default: prescale_terminal = 10'd1023;
            endcase
        end
    endfunction

    integer c;
    always @(*) begin
        for (c = 0; c < 4; c = c + 1) begin
            reload_effective[c] = reload_value[c];
            control_effective[c] = control_value[c];
            if (timer_write_q && (timer_index_q == c)) begin
                if (byteena_q[0])
                    reload_effective[c][7:0] = wdata_shifted_q[7:0];
                if (byteena_q[1])
                    reload_effective[c][15:8] = wdata_shifted_q[15:8];
                if (byteena_q[2])
                    control_effective[c] = wdata_shifted_q[23:16] & 8'hc7;
            end
        end

        // Timer 0 has no count-up mode.
        control_effective[0][2] = 1'b0;

        for (c = 0; c < 4; c = c + 1) begin
            start_rise[c] = !control_value[c][7] &&
                            control_effective[c][7];
            stop_fall[c] = control_value[c][7] &&
                           !control_effective[c][7];
            // A stop commit accounts for the final elapsed timer edge under
            // the old control before disabling the channel.
            tick_control[c] = stop_fall[c] ? control_value[c]
                                            : control_effective[c];
            timer_tick[c] = 1'b0;
            timer_overflow[c] = 1'b0;
        end

        timer_tick[0] = tick_control[0][7] && !start_rise[0] &&
                        !start_load_wait[0] &&
                        (prescale_count[0] ==
                         prescale_terminal(tick_control[0][1:0]));
        timer_overflow[0] = (timer_tick[0] &&
                            (counter_value[0] == 16'hffff)) ||
                           (start_load_wait[0] && start_overflow[0]);

        for (c = 1; c < 4; c = c + 1) begin
            if (tick_control[c][7] && !start_rise[c] &&
                !start_load_wait[c]) begin
                if (tick_control[c][2])
                    timer_tick[c] = timer_overflow[c - 1];
                else
                    timer_tick[c] = prescale_count[c] ==
                                    prescale_terminal(
                                        tick_control[c][1:0]);
            end
            timer_overflow[c] = (timer_tick[c] &&
                                (counter_value[c] == 16'hffff)) ||
                               (start_load_wait[c] && start_overflow[c]);
        end
    end

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_load_wait <= 4'b0000;
            start_overflow <= 4'b0000;
            irq_o <= 4'b0000;
            timer_write_q <= 1'b0;
            timer_index_q <= 2'b00;
            byteena_q <= 4'b0000;
            wdata_shifted_q <= 32'd0;
            for (i = 0; i < 4; i = i + 1) begin
                reload_value[i] <= 16'd0;
                counter_value[i] <= 16'd0;
                control_value[i] <= 8'd0;
                prescale_count[i] <= 10'd0;
            end
        end else begin
            // IF samples a registered overflow request on the following edge.
            irq_o <= timer_overflow & {tick_control[3][6],
                                       tick_control[2][6],
                                       tick_control[1][6],
                                       tick_control[0][6]};
            // Timer register writes take effect one inverse-clock edge after
            // the bus accepts them. A combined reload/control word therefore
            // presents the new reload to the start transition on one edge.
            timer_write_q <= timer_write;
            if (timer_write) begin
                timer_index_q <= timer_index;
                byteena_q <= byteena;
                wdata_shifted_q <= wdata_shifted;
            end

            for (i = 0; i < 4; i = i + 1) begin
                reload_value[i] <= reload_effective[i];
                control_value[i] <= control_effective[i];

                if (start_rise[i]) begin
                    // The old counter can overflow during the enable-to-load
                    // window. Retain that carry before loading the new count.
                    start_overflow[i] <= !control_effective[i][2] &&
                        (prescale_count[i] ==
                         prescale_terminal(control_effective[i][1:0])) &&
                        (counter_value[i] == 16'hffff);
                    counter_value[i] <= reload_effective[i];
                    prescale_count[i] <= 10'd0;
                    // Enabling first loads the reload value; counting begins
                    // after one additional timer edge.
                    start_load_wait[i] <= 1'b1;
                end else if (!control_effective[i][7]) begin
                    // A 1->0 stop transition includes the tick at the delayed
                    // control-commit edge, then freezes the resulting count.
                    if (stop_fall[i] && timer_tick[i])
                        counter_value[i] <= timer_overflow[i]
                                          ? reload_value[i]
                                          : counter_value[i] + 1'b1;
                    prescale_count[i] <= 10'd0;
                    start_load_wait[i] <= 1'b0;
                end else if (start_load_wait[i]) begin
                    prescale_count[i] <= 10'd0;
                    start_load_wait[i] <= 1'b0;
                end else if (timer_tick[i]) begin
                    // A reload write does not consume the running timer tick.
                    // If a delayed reload update and overflow share an edge,
                    // overflow still consumes the previously active reload.
                    counter_value[i] <= timer_overflow[i]
                                      ? reload_value[i]
                                      : counter_value[i] + 1'b1;
                    prescale_count[i] <= 10'd0;
                end else if (!control_effective[i][2]) begin
                    prescale_count[i] <= prescale_count[i] + 1'b1;
                end
            end
        end
    end

    assign tm0_count_o = counter_value[0];
    assign tm1_count_o = counter_value[1];
    assign tm2_count_o = counter_value[2];
    assign tm3_count_o = counter_value[3];
    assign tm0_control_o = {8'd0, control_value[0]};
    assign tm1_control_o = {8'd0, control_value[1]};
    assign tm2_control_o = {8'd0, control_value[2]};
    assign tm3_control_o = {8'd0, control_value[3]};

endmodule
