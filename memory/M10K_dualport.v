// =============================================================================
//  M10K_dualport.v
//  Same-clock Intel/Altera `altsyncram` true-dual-port M10K wrapper.
//
//  Port A is byte-enabled read/write for the shared CPU/DMA bus. Port B is
//  read-only for fixed-latency PPU fetches. Both ports are synchronous to
//  `clk`; a mixed-port read during a port-A write to the same location returns
//  the old data on port B.
// =============================================================================

`timescale 1ns / 1ps

module M10K_dualport #(
    parameter WIDTH      = 32,
    parameter DEPTH_POW2 = 10,
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire [DEPTH_POW2-1:0] addr_a,
    input  wire [(WIDTH/8)-1:0]  byteena_a,
    input  wire                  clk,
    input  wire [WIDTH-1:0]      data_a,
    input  wire                  wren_a,
    input  wire                  rden_a,
    output wire [WIDTH-1:0]      q_a,

    input  wire [DEPTH_POW2-1:0] addr_b,
    input  wire                  rden_b,
    output wire [WIDTH-1:0]      q_b
);

    localparam DEPTH = 1 << DEPTH_POW2;
    localparam BYTEENA_WIDTH = (WIDTH >= 8) ? (WIDTH / 8) : 1;

    // The Intel simulation model declares these primitive inputs as resolved
    // nets. Local aliases prevent that detail from propagating through this
    // wrapper and back-driving its input ports in Icarus.
    wire mem_clk = clk;
    wire mem_wren_a = wren_a;
    wire mem_rden_a = rden_a;
    wire mem_rden_b = rden_b;
    wire [BYTEENA_WIDTH-1:0] mem_byteena_a = byteena_a;

    altsyncram #(
        .operation_mode                    ("BIDIR_DUAL_PORT"),
        .ram_block_type                    ("M10K"),
        .intended_device_family            ("Cyclone V"),
        .width_a                           (WIDTH),
        .width_byteena_a                   (BYTEENA_WIDTH),
        .widthad_a                         (DEPTH_POW2),
        .numwords_a                        (DEPTH),
        .width_b                           (WIDTH),
        .width_byteena_b                   (BYTEENA_WIDTH),
        .widthad_b                         (DEPTH_POW2),
        .numwords_b                        (DEPTH),
        .byte_size                         (8),
        .init_file                         (INIT_FILE),
        .address_reg_b                     ("CLOCK0"),
        .rdcontrol_reg_b                   ("CLOCK0"),
        .indata_reg_b                      ("CLOCK0"),
        .wrcontrol_wraddress_reg_b          ("CLOCK0"),
        .byteena_reg_b                     ("CLOCK0"),
        .outdata_reg_a                     ("UNREGISTERED"),
        .outdata_reg_b                     ("UNREGISTERED"),
        .outdata_aclr_a                    ("NONE"),
        .outdata_aclr_b                    ("NONE"),
        .read_during_write_mode_port_a      ("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b      ("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_mixed_ports ("OLD_DATA"),
        .clock_enable_input_a              ("BYPASS"),
        .clock_enable_output_a             ("BYPASS"),
        .clock_enable_input_b              ("BYPASS"),
        .clock_enable_output_b             ("BYPASS"),
        .power_up_uninitialized            ("FALSE"),
        .lpm_type                          ("altsyncram"),
        .lpm_hint                          ("ENABLE_RUNTIME_MOD=NO")
    ) mem_inst (
        .clock0        (mem_clk),
        .address_a     (addr_a),
        .byteena_a     (mem_byteena_a),
        .data_a        (data_a),
        .wren_a        (mem_wren_a),
        .rden_a        (mem_rden_a),
        .q_a           (q_a),
        .address_b     (addr_b),
        .byteena_b     ({BYTEENA_WIDTH{1'b1}}),
        .data_b        ({WIDTH{1'b0}}),
        .wren_b        (1'b0),
        .rden_b        (mem_rden_b),
        .q_b           (q_b),
        .aclr0         (1'b0),
        .aclr1         (1'b0),
        .clock1        (1'b1),
        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .eccstatus     ()
    );

endmodule
