###############################################################################
# ARM7TDMI Exception & Interrupt testbench script
#
# Target  : arm7tdmi_project_sim (SoC wrapper with SRAM loaded from .mif)
# Program : interrupt_test.s   ->   interrupt_test.hex   ->   interrupt_test.mif
#
# Before running:
#   1. Assemble interrupt_test.s with arm-none-eabi-as/ld to produce
#      interrupt_test.hex (raw 32-bit words, no addresses).
#   2. Edit assembly_code/hex_to_mif.py so the input matches "interrupt_test"
#      and run  `python3 hex_to_mif.py` to generate interrupt_test.mif.
#   3. In arm7tdmi_project_sim.v change
#         parameter INIT_FILE = "arm7tdmi_thumb_test.mif";
#      to
#         parameter INIT_FILE = "interrupt_test.mif";
#   4. From simulation/questa/, launch ModelSim/Questa and  `do ../../assembly_code/interrupt_test.tcl`.
#
# What this script drives:
#   * 50 MHz CLOCK_50 (20 ns period) -- arm7tdmi_project_sim wires it straight
#     to the CPU clock (no PLL/divider, unlike the on-board build).
#   * SW[1] = 1 holds reset (nrst = ~SW[1]); release after a few clocks.
#   * SW[0] = SW[9] = 0 (no PLL reset / SignalTap gating, both inert in sim).
#   * nIRQ, nFIQ, ABORT default high. Forced low at pre-computed times to
#     exercise the IRQ / FIQ exception paths after SWI + Undef tests finish.
#
# Override mechanism:
#   arm7tdmi_project_sim.v ties .nIRQ/.nFIQ/.ABORT to 1'b1. We use
#   `force -freeze` on the *internal* arm7tdmi_top input ports; in ModelSim
#   that overrides the literal driver.
###############################################################################

vsim -i -l msim_transcript work.arm7tdmi_project_sim -t ns -voptargs=+acc -debugdb
log -r /*

###############################################################################
# 1.  WAVE CONFIGURATION
###############################################################################
add wave -divider "Clock / Reset"
add wave -radix bin     sim:/arm7tdmi_project_sim/CLOCK_50
add wave -radix bin     sim:/arm7tdmi_project_sim/clock
add wave -radix bin     sim:/arm7tdmi_project_sim/nrst

add wave -divider "Memory Bus"
add wave -radix hex     sim:/arm7tdmi_project_sim/addr
add wave -radix hex     sim:/arm7tdmi_project_sim/din
add wave -radix hex     sim:/arm7tdmi_project_sim/dout
add wave -radix bin     sim:/arm7tdmi_project_sim/nRW
add wave -radix bin     sim:/arm7tdmi_project_sim/MAS

add wave -divider "Interrupt / Abort Inputs"
add wave -radix bin     sim:/arm7tdmi_project_sim/arm7tdmi_top/nIRQ
add wave -radix bin     sim:/arm7tdmi_project_sim/arm7tdmi_top/nFIQ
add wave -radix bin     sim:/arm7tdmi_project_sim/arm7tdmi_top/ABORT

add wave -divider "Exception Logic (decoder.v)"
add wave -radix unsigned sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/exception_type
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/exception_req
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/exception_entry
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/swi_pending
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/undef_pending
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/pre_abort_pending
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/data_abort_pending
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/irq_pending
add wave -radix bin      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/fiq_pending

add wave -divider "Mode / PSR (reg_bank.v)"
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/reg_bank/cpsr_reg
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/reg_bank/spsr_reg
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/cpsr_mode

add wave -divider "Pipeline Snapshot"
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/instruct_reg
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/instruct_dec
add wave -radix unsigned sim:/arm7tdmi_project_sim/arm7tdmi_top/Inst_decoded
add wave -radix hex      sim:/arm7tdmi_project_sim/arm7tdmi_top/decoder/cycle_count

add wave -divider "Architectural Registers"
add wave -radix hex      sim:/arm7tdmi_project_sim/r

add wave -divider "SRAM Image"
add wave -radix hex      sim:/arm7tdmi_project_sim/sram/mem

###############################################################################
# 2.  CLOCK + RESET
###############################################################################
force sim:/arm7tdmi_project_sim/CLOCK_50 0 0 ns, 1 10 ns -r 20 ns

force sim:/arm7tdmi_project_sim/SW[1]  1   0 ns          ;# reset asserted
force sim:/arm7tdmi_project_sim/SW[1]  0  60 ns          ;# release reset after 3 clk
force sim:/arm7tdmi_project_sim/SW[0]  0   0 ns
force sim:/arm7tdmi_project_sim/SW[9]  0   0 ns

###############################################################################
# 3.  EXCEPTION INPUT DEFAULTS  (de-asserted = HIGH)
###############################################################################
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nIRQ  1  0 ns
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nFIQ  1  0 ns
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/ABORT 1  0 ns

###############################################################################
# 4.  IRQ PULSE
#
# By ~3 us the reset handler has set up the per-mode SPs and main has finished
# the SWI and Undef tests; the CPU is now spinning in `irq_wait`. We pulse
# nIRQ low for ~10 clk so the falling edge is sampled and irq_pending fires.
# If exc_I_set is correctly driven, CPSR.I = 1 on entry and re-entrance is
# blocked even though nIRQ is still low for a few more clocks.
###############################################################################
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nIRQ 0 3000 ns
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nIRQ 1 3200 ns

###############################################################################
# 5.  FIQ PULSE
#
# A few microseconds after the IRQ pulse, the CPU should be in `fiq_wait`.
# Pulse nFIQ low for ~10 clk to trigger the FIQ exception. Note that
# FIQ has higher priority than IRQ in exception_type_w, and on entry both
# F and I should be set in CPSR (datasheet §3.9 Table 2-1).
###############################################################################
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nFIQ 0 6000 ns
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/nFIQ 1 6200 ns

###############################################################################
# 6.  (OPTIONAL) PREFETCH ABORT PULSE
#
# ABORT being level-sensitive during instruction fetch maps to a Prefetch
# Abort; during a load/store it becomes a Data Abort. Uncomment to exercise
# the prefetch path -- the program currently halts in `end_test` (B self),
# so we have a steady fetch stream to abort.
###############################################################################
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/ABORT 0 9000 ns
force -freeze sim:/arm7tdmi_project_sim/arm7tdmi_top/ABORT 1 9100 ns

###############################################################################
# 7.  RUN
#
# Expected register snapshots at the end of the run (read off the wave):
#   R0  = 0x00011111   (sentinel + every handler marker)
#   R4  = 0x00000011   (post-SWI)
#   R5  = 0x00000111   (post-Undef)
#   R6  = 0x00001111   (post-IRQ)
#   R7  = 0x00011111   (post-FIQ)
#   PC  = end_test     (looping)
#   CPSR mode = 0x1F   (System), I=0, F=0
###############################################################################
run 12000 ns
wave zoom full
