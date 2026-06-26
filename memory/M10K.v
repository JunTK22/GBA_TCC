module M10K #(
    parameter WIDTH      = 32,
    parameter DEPTH_POW2 = 10,
    // Set INIT_FILE to "UNUSED" for zero-initialised / uninitialised memories.
    parameter INIT_FILE  = "UNUSED"
)(
    input  wire [DEPTH_POW2-1:0]      addr,
    input  wire [(WIDTH/8)-1:0]       byteena,
    input  wire                       clk,
    input  wire [WIDTH-1:0]           data,
    input  wire                       wren,
    input  wire                       rden,
    output wire [WIDTH-1:0]           q
);

localparam DEPTH         = 1 << DEPTH_POW2;
// width_byteena_a must be >= 1; for WIDTH==8 this is the same as wren.
localparam BYTEENA_WIDTH = (WIDTH >= 8) ? (WIDTH/8) : 1;

altsyncram #(
      .operation_mode             ("SINGLE_PORT"),
      .ram_block_type             ("M10K"),
      .intended_device_family     ("Cyclone V"),
      .width_a                    (WIDTH),
      .width_byteena_a            (BYTEENA_WIDTH),
      .byte_size                  (8),
      .widthad_a                  (DEPTH_POW2),
      .numwords_a                 (DEPTH),
      .init_file                  (INIT_FILE),
      .outdata_reg_a              ("UNREGISTERED"),
      .outdata_aclr_a             ("NONE"),
      .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
      .clock_enable_input_a       ("BYPASS"),
      .clock_enable_output_a      ("BYPASS"),
      .power_up_uninitialized     ("FALSE"),
      .lpm_type                   ("altsyncram"),
      .lpm_hint                   ("ENABLE_RUNTIME_MOD=NO")
  ) mem_inst (
      .clock0    (clk),
      .address_a (addr),
      .byteena_a (byteena),
      .data_a    (data),
      .wren_a    (wren),
      .rden_a    (rden),
      .q_a       (q),
      // tie-offs:
      .aclr0(1'b0), .aclr1(1'b0), .clock1(1'b1),
      .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
      .addressstall_a(1'b0), .addressstall_b(1'b0),
      .address_b(1'b1), .data_b(1'b1), .byteena_b(1'b1),
      .wren_b(1'b0), .rden_b(1'b1),
      .q_b(), .eccstatus()
  );
endmodule