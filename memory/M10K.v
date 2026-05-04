module M10K #(
    parameter WIDTH = 32,
    parameter DEPTH_POW2 = 10,
    parameter INIT_FILE = "assembly_code/instrucoes.mif"
)(
    input  wire [DEPTH_POW2-1:0] addr,
    input  wire [3:0]            byteena,
    input  wire                  clk,
    input  wire [WIDTH-1:0]      data,
    input  wire                  wren,
    output wire [WIDTH-1:0]      q
);

localparam DEPTH = 1 << DEPTH_POW2;

altsyncram #(   
      .operation_mode             ("SINGLE_PORT"),                                                                                                                           
      .ram_block_type             ("M10K"),       
      .intended_device_family     ("Cyclone V"),
      .width_a                    (WIDTH),                                                                                                                                      
      .width_byteena_a            (4), 
      .byte_size                  (8),                                                                                                                                       
      .widthad_a                  (DEPTH_POW2),                                                                                                                              
      .numwords_a                 (DEPTH),     
      .init_file                  (INIT_FILE),         // module parameter                                                                                                   
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
      .q_a       (q),                                                                                                                                                    
      // tie-offs:       
      .aclr0(1'b0), .aclr1(1'b0), .clock1(1'b1),                                                                                                                             
      .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
      .addressstall_a(1'b0), .addressstall_b(1'b0),                                                                                                                          
      .address_b(1'b1), .data_b(1'b1), .byteena_b(1'b1),                                                                                                                     
      .wren_b(1'b0), .rden_a(1'b1), .rden_b(1'b1),                                                                                                                           
      .q_b(), .eccstatus()                                                                                                                                                   
  );
endmodule