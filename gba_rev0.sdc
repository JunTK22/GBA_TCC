#**************************************************************
# This .sdc file is created by Terasic Tool.
# Users are recommended to modify this file to match users logic.
#**************************************************************

#**************************************************************
# Create Clock
#**************************************************************
create_clock -period 20.000ns [get_ports CLOCK2_50]
create_clock -period 20.000ns [get_ports CLOCK3_50]
create_clock -period 20.000ns [get_ports CLOCK4_50]
create_clock -period 20.000ns [get_ports CLOCK_50]

#create_clock -period "100 MHz" -name clk_dram [get_ports DRAM_CLK]
# AUDIO : 48kHz 384fs 32-bit data
create_clock -period "18.432 MHz" -name clk_audxck [get_ports AUD_XCK]
create_clock -period "1.536 MHz" -name clk_audbck [get_ports AUD_BCLK]
# VGA : 640x480@60Hz
#create_clock -period "25.18 MHz" -name clk_vga [get_ports VGA_CLK]
# VGA : 800x600@60Hz
#create_clock -period "40.0 MHz" -name clk_vga [get_ports VGA_CLK]
# VGA : 1024x768@60Hz
#create_clock -period "65.0 MHz" -name clk_vga [get_ports VGA_CLK]
# VGA : 1280x1024@60Hz
create_clock -period "108.0 MHz" -name clk_vga [get_ports VGA_CLK]

# for enhancing USB BlasterII to be reliable, 25MHz
create_clock -name {altera_reserved_tck} -period 40 {altera_reserved_tck}
set_input_delay -clock altera_reserved_tck -clock_fall 3 [get_ports altera_reserved_tdi]
set_input_delay -clock altera_reserved_tck -clock_fall 3 [get_ports altera_reserved_tms]
set_output_delay -clock altera_reserved_tck 3 [get_ports altera_reserved_tdo]

#**************************************************************
# Create Generated Clock
#**************************************************************
derive_pll_clocks

create_generated_clock -name test_clk \
      -source {pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} \
      -divide_by 1 \
      [get_registers test_clk]

#create_generated_clock -name clock_n \
#      -source test_clk \
#      -invert \
#      [get_nets clock_n]

##create_generated_clock -name clk_dram \
##      -source {Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} \
##      [get_ports DRAM_CLK]

set_clock_groups -asynchronous \
      -group {pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk test_clk}

# ------------------------------------------------------------------
# Async inputs / async resets — no real timing relationship.
# ------------------------------------------------------------------
set_false_path -from [get_pins {pll|pll_inst|altera_pll_i|general[0].gpll~FRACTIONAL_PLL|lock}] -to [all_registers]
set_false_path -from [get_ports {SW[*]}]       -to [all_registers]
set_false_path -from [get_ports {KEY[*]}]      -to [all_registers]
set_false_path -from [get_registers {dma:dma0|data_o[*]}]      -to [get_registers {arm7tdmi_top:arm7tdmi_top|*}]
set_false_path -from [get_registers {arm7tdmi_top:arm7tdmi_top|*}]      -to [get_registers {dma:dma0|data_o[*]}]

#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************
derive_clock_uncertainty



#**************************************************************
# Set Input Delay
#**************************************************************
# Board Delay (Data) + Propagation Delay - Board Delay (Clock)
set_input_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.048 [get_ports DRAM_DQ*]
set_input_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.057 [get_ports DRAM_DQ*]




#**************************************************************
# Set Output Delay
#**************************************************************
# max : Board Delay (Data) - Board Delay (Clock) + tsu (External Device)
# min : Board Delay (Data) - Board Delay (Clock) - th (External Device)
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.452  [get_ports DRAM_DQ*]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.857 [get_ports DRAM_DQ*]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.531 [get_ports DRAM_ADDR*]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.805 [get_ports DRAM_ADDR*]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.533  [get_ports DRAM_*DQM]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.805 [get_ports DRAM_*DQM]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.510  [get_ports DRAM_BA*]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.800 [get_ports DRAM_BA*]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.520  [get_ports DRAM_RAS_N]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.780 [get_ports DRAM_RAS_N]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.5000  [get_ports DRAM_CAS_N]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.800 [get_ports DRAM_CAS_N]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.545 [get_ports DRAM_WE_N]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.755 [get_ports DRAM_WE_N]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.496  [get_ports DRAM_CKE]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.804 [get_ports DRAM_CKE]
set_output_delay -max -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk 1.508  [get_ports DRAM_CS_N]
set_output_delay -min -clock Sdram_Control|sdram_pll0_inst|sdram_pll0_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk -0.792 [get_ports DRAM_CS_N]

set_output_delay -max -clock clk_vga 0.220 [get_ports VGA_R*]
set_output_delay -min -clock clk_vga -1.506 [get_ports VGA_R*]
set_output_delay -max -clock clk_vga 0.212 [get_ports VGA_G*]
set_output_delay -min -clock clk_vga -1.519 [get_ports VGA_G*]
set_output_delay -max -clock clk_vga 0.264 [get_ports VGA_B*]
set_output_delay -min -clock clk_vga -1.519 [get_ports VGA_B*]
set_output_delay -max -clock clk_vga 0.215 [get_ports VGA_BLANK]
set_output_delay -min -clock clk_vga -1.485 [get_ports VGA_BLANK]




#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************



#**************************************************************
# Set Load
#**************************************************************



