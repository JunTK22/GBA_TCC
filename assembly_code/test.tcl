vsim -i -l msim_transcript work.arm7tdmi_project -t ns -voptargs=+acc
add wave -position insertpoint  \
sim:/arm7tdmi_project/CLOCK_50
add wave -position insertpoint  \
sim:/arm7tdmi_project/HEX0 \
sim:/arm7tdmi_project/HEX1 \
sim:/arm7tdmi_project/HEX2 \
sim:/arm7tdmi_project/HEX3 \
sim:/arm7tdmi_project/HEX4 \
sim:/arm7tdmi_project/HEX5
add wave -position insertpoint  \
sim:/arm7tdmi_project/clock \
sim:/arm7tdmi_project/nrst \
sim:/arm7tdmi_project/tap_en \
sim:/arm7tdmi_project/nRW \
sim:/arm7tdmi_project/r \
sim:/arm7tdmi_project/din \
sim:/arm7tdmi_project/addr \
sim:/arm7tdmi_project/dout
add wave -position insertpoint  \
sim:/arm7tdmi_project/arm7tdmi_top/Bus_A \
sim:/arm7tdmi_project/arm7tdmi_top/Bus_B \
sim:/arm7tdmi_project/arm7tdmi_top/Alu_bus
add wave -position insertpoint  \
sim:/arm7tdmi_project/sram/mem
add wave -position insertpoint  \
sim:/arm7tdmi_project/arm7tdmi_top/decoder/cycle_count
add wave -position insertpoint  \
sim:/arm7tdmi_project/arm7tdmi_top/reg_bank/cpsr_rdata \
sim:/arm7tdmi_project/arm7tdmi_top/decoder/instruct_reg \
sim:/arm7tdmi_project/arm7tdmi_top/decoder/instruct_dec 

force SW[1]  1 0 ns
force SW[1]  0 3 ns
force CLOCK_50 0 0 ns, 1 5 ns -r 10 ns