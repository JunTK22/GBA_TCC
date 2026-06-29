vsim -i -l msim_transcript work.gba_rev0 -t ns -L altera_mf -L altera_lnsim -voptargs=+acc -debugdb
log -r /*
add wave -position insertpoint  \
sim:/gba_rev0/CLOCK_50
add wave -position insertpoint  \
sim:/gba_rev0/HEX0 \
sim:/gba_rev0/HEX1 \
sim:/gba_rev0/HEX2 \
sim:/gba_rev0/HEX3 \
sim:/gba_rev0/HEX4 \
sim:/gba_rev0/HEX5
add wave -position insertpoint  \
sim:/gba_rev0/clock \
sim:/gba_rev0/nrst \
sim:/gba_rev0/nRW \
sim:/gba_rev0/nWAIT \
sim:/gba_rev0/r \
sim:/gba_rev0/data_bus \
sim:/gba_rev0/addr_bus \
sim:/gba_rev0/dout
add wave -position insertpoint  \
sim:/gba_rev0/arm7tdmi_top/Bus_A \
sim:/gba_rev0/arm7tdmi_top/Bus_B \
sim:/gba_rev0/arm7tdmi_top/Alu_bus
add wave -position insertpoint  \
sim:/gba_rev0/sram/mem
add wave -position insertpoint  \
sim:/gba_rev0/arm7tdmi_top/decoder/cycle_count
add wave -position insertpoint  \
sim:/gba_rev0/arm7tdmi_top/reg_bank/cpsr_rdata \
sim:/gba_rev0/arm7tdmi_top/decoder/instruct_reg \
sim:/gba_rev0/arm7tdmi_top/decoder/instruct_dec \
sim:/gba_rev0/MAS

force SW[1]  1 0 ns
force SW[1]  0 30 ns

force KEY[1]  1 0 ns
force KEY[2]  1 0 ns
force KEY[3]  1 0 ns

force CLOCK_50 0 0 ns, 1 5 ns -r 10 ns

run 20000 ns