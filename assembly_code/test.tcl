vsim -i -l msim_transcript work.arm7tdmi_project_sim -t ns -voptargs=+acc
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/CLOCK_50
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/HEX0 \
sim:/arm7tdmi_project_sim/HEX1 \
sim:/arm7tdmi_project_sim/HEX2 \
sim:/arm7tdmi_project_sim/HEX3 \
sim:/arm7tdmi_project_sim/HEX4 \
sim:/arm7tdmi_project_sim/HEX5
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/clock \
sim:/arm7tdmi_project_sim/nrst \
sim:/arm7tdmi_project_sim/tap_en \
sim:/arm7tdmi_project_sim/nRW \
sim:/arm7tdmi_project_sim/r \
sim:/arm7tdmi_project_sim/din \
sim:/arm7tdmi_project_sim/addr \
sim:/arm7tdmi_project_sim/dout
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/arm7tdmi_top/Bus_A \
sim:/arm7tdmi_project_sim/arm7tdmi_top/Bus_B \
sim:/arm7tdmi_project_sim/arm7tdmi_top/Alu_bus
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/sram/mem
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/cycle_count
add wave -position insertpoint  \
sim:/arm7tdmi_project_sim/arm7tdmi_top/reg_bank/cpsr_rdata \
sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/instruct_reg \
sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/instruct_dec \
sim:/arm7tdmi_project_sim/MAS

force SW[1]  1 0 ns
force SW[1]  0 3 ns
force CLOCK_50 0 0 ns, 1 5 ns -r 10 ns