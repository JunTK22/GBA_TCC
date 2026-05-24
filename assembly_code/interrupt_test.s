@ ==============================================================================
@ ARM7TDMI Exception & Interrupt Test Program
@ Targets the Verilog soft-core in arm7tdmi_core/, integrated under
@ arm7tdmi_project_sim.v (16 KB SRAM, INIT_FILE = this program's .mif).
@
@ Reference: ARM7TDMI Data Sheet, ARM DDI 0029E (Aug 1995)
@   - §2.7  Exceptions
@   - §3.6  Operating Modes
@   - §3.7  Banked Registers
@   - §3.8  Program Status Registers
@   - §3.9  Exception entry / exit
@
@ Vector Table (§2.7, Table 2-1):
@   0x00  Reset                  -> Supervisor, F=1 I=1
@   0x04  Undefined Instruction  -> Undefined,         I=1
@   0x08  Software Interrupt     -> Supervisor,        I=1
@   0x0C  Prefetch Abort         -> Abort,             I=1
@   0x10  Data Abort             -> Abort,             I=1
@   0x14  Reserved
@   0x18  IRQ                    -> IRQ,               I=1
@   0x1C  FIQ                    -> FIQ,         F=1   I=1
@
@ Test strategy:
@   R0 is an accumulator. Each handler XORs in a unique nibble marker so we
@   can read off which exceptions fired and in what order from R0 / R4..R7.
@
@   Expected final values:
@     R0 = 0x10 + 0x01 + 0x100 + 0x1000 + 0x10000 = 0x11111
@     R4 = 0x11        snapshot after SWI
@     R5 = 0x111       snapshot after Undef
@     R6 = 0x1111      snapshot after IRQ
@     R7 = 0x11111     snapshot after FIQ
@
@   The IRQ / FIQ pulses are produced by the testbench TCL (force nIRQ/nFIQ
@   low for a few cycles). The main code spins in a polling loop, exiting
@   when the handler bumps R0 to the expected value.
@ ==============================================================================

    .arch   armv4t
    .arm
    .section .text
    .global  _start

@ ==============================================================================
@ §1  EXCEPTION VECTOR TABLE  (must occupy the first 32 bytes)
@ ==============================================================================
_start:
    B   reset_handler        @ 0x00 Reset
    B   undef_handler        @ 0x04 Undefined Instruction
    B   swi_handler          @ 0x08 Software Interrupt
    B   pabt_handler         @ 0x0C Prefetch Abort
    B   dabt_handler         @ 0x10 Data Abort
    NOP                      @ 0x14 Reserved
    B   irq_handler          @ 0x18 IRQ
    B   fiq_handler          @ 0x1C FIQ

@ ==============================================================================
@ §2  RESET HANDLER -- initialise per-mode stack pointers, then enter main
@
@   CPSR_c immediates (CPSR[7:0]):
@     0xD1 = I=1 F=1 mode=10001 (FIQ)
@     0xD2 = I=1 F=1 mode=10010 (IRQ)
@     0xD7 = I=1 F=1 mode=10111 (Abort)
@     0xDB = I=1 F=1 mode=11011 (Undefined)
@     0xD3 = I=1 F=1 mode=10011 (Supervisor)
@     0x1F = I=0 F=0 mode=11111 (System)  -- main runs here
@
@   Stacks are placed at the top of the 16 KB SRAM (DEPTH_POW2 = 12):
@     0x3F00  USR / SYS
@     0x3E00  SVC
@     0x3D00  IRQ
@     0x3C00  FIQ
@     0x3B00  UND
@     0x3A00  ABT
@ ==============================================================================
reset_handler:
    MSR     CPSR_c, #0xD1
    MOV     SP,     #0x3C00      @ FIQ_SP
    MSR     CPSR_c, #0xD2
    MOV     SP,     #0x3D00      @ IRQ_SP
    MSR     CPSR_c, #0xD7
    MOV     SP,     #0x3A00      @ ABT_SP
    MSR     CPSR_c, #0xDB
    MOV     SP,     #0x3B00      @ UND_SP
    MSR     CPSR_c, #0xD3
    MOV     SP,     #0x3E00      @ SVC_SP
    MSR     CPSR_c, #0x1F        @ System mode, IRQ + FIQ enabled
    MOV     SP,     #0x3F00      @ SYS_SP

@ ==============================================================================
@ §3  MAIN TEST SEQUENCE
@ ==============================================================================
main:
    MOV     R0, #0x10            @ sentinel base value

@ ------------------------------------------------------------------ Test 1: SWI
    SWI     #0x42                @ handler does R0 += 1
    MOV     R4, R0               @ expect R4 == 0x11

@ ----------------------------------------------------- Test 2: Undefined instr
    .word   0xE7F000F0           @ permanently UNDEFINED encoding (ARM ARM)
    MOV     R5, R0               @ expect R5 == 0x111

@ ------------------------------------------------------------------ Test 3: IRQ
@   Spin until the IRQ handler bumps R0 from 0x111 to 0x1111. The testbench
@   pulses nIRQ low for a few cycles after this loop is reached.
    MOV     R10, #0x1100
    ORR     R10, R10, #0x11      @ R10 = 0x1111 (expected post-IRQ value)
irq_wait:
    CMP     R0, R10
    BNE     irq_wait
    MOV     R6, R0               @ expect R6 == 0x1111

@ ------------------------------------------------------------------ Test 4: FIQ
@   Same idea: spin until FIQ handler bumps R0 from 0x1111 to 0x11111.
    MOV     R11, #0x11000
    ORR     R11, R11, #0x100
    ORR     R11, R11, #0x11      @ R11 = 0x11111
fiq_wait:
    CMP     R0, R11
    BNE     fiq_wait
    MOV     R7, R0               @ expect R7 == 0x11111

@ ------------------------------------------------------------------------- Halt
end_test:
    B       end_test             @ inspect R0..R11 in waveform / SignalTap

@ ==============================================================================
@ §4  EXCEPTION HANDLERS
@
@   Conventions per ARM DDI 0029E §3.9:
@     SWI / Undef : LR already points to next sequential instruction
@                   -> return with MOVS PC, LR
@     IRQ / FIQ   : LR = (interrupted_pc + 4), one ahead of resume point
@                   -> return with SUBS PC, LR, #4
@     Prefetch Ab : LR = (aborted_pc + 4)  -> SUBS PC, LR, #4
@     Data Abort  : LR = (aborting_pc + 8) -> SUBS PC, LR, #8
@
@   The MOVS / SUBS forms with PC as destination atomically copy SPSR back to
@   CPSR, restoring the pre-exception mode and I/F bits.
@ ==============================================================================
swi_handler:
    ADD     R0, R0, #0x1
    MOVS    PC, LR

undef_handler:
    ADD     R0, R0, #0x100
    MOVS    PC, LR

pabt_handler:
    ADD     R0, R0, #0x10000000  @ visible marker if ever taken
    SUBS    PC, LR, #4

dabt_handler:
    ADD     R0, R0, #0x20000000  @ visible marker if ever taken
    SUBS    PC, LR, #8

irq_handler:
    ADD     R0, R0, #0x1000
    SUBS    PC, LR, #4

fiq_handler:
    ADD     R0, R0, #0x10000
    SUBS    PC, LR, #4

    .end
