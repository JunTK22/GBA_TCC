vsim -i -l msim_transcript work.gba_rev0_sim -t ns -L altera_mf -voptargs=+acc -debugdb
log -r /*
add wave -position insertpoint  \
sim:/gba_rev0_sim/CLOCK_50
add wave -position insertpoint  \
sim:/gba_rev0_sim/HEX0 \
sim:/gba_rev0_sim/HEX1 \
sim:/gba_rev0_sim/HEX2 \
sim:/gba_rev0_sim/HEX3 \
sim:/gba_rev0_sim/HEX4 \
sim:/gba_rev0_sim/HEX5
add wave -position insertpoint  \
sim:/gba_rev0_sim/clock \
sim:/gba_rev0_sim/nrst \
sim:/gba_rev0_sim/nRW \
sim:/gba_rev0_sim/nWAIT \
sim:/gba_rev0_sim/r \
sim:/gba_rev0_sim/data_bus \
sim:/gba_rev0_sim/addr_bus \
sim:/gba_rev0_sim/dout
add wave -position insertpoint  \
sim:/gba_rev0_sim/arm7tdmi_top/Bus_A \
sim:/gba_rev0_sim/arm7tdmi_top/Bus_B \
sim:/gba_rev0_sim/arm7tdmi_top/Alu_bus
add wave -position insertpoint  \
sim:/gba_rev0_sim/sram/mem
add wave -position insertpoint  \
sim:/gba_rev0_sim/arm7tdmi_top/decoder/cycle_count
add wave -position insertpoint  \
sim:/gba_rev0_sim/arm7tdmi_top/reg_bank/cpsr_rdata \
sim:/gba_rev0_sim/arm7tdmi_top/decoder/instruct_reg \
sim:/gba_rev0_sim/arm7tdmi_top/decoder/instruct_dec \
sim:/gba_rev0_sim/MAS

force SW[1]  1 0 ns
force SW[1]  0 30 ns

force KEY[1]  1 0 ns
force KEY[2]  1 0 ns
force KEY[3]  1 0 ns

force CLOCK_50 0 0 ns, 1 5 ns -r 10 ns

run 20000 ns