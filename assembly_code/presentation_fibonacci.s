@ ==============================================================================
@ presentation_fibonacci.s -- Fibonacci IRQ/FIQ stack demo
@
@ Demo intent:
@   * Main code continuously advances the Fibonacci sequence.
@   * IRQ saves the current sequence state on a shared descending stack.
@   * FIQ restores the latest saved sequence state from that stack.
@
@ Visible registers for waveform / SignalTap:
@   R0 = F(n)
@   R1 = F(n+1)
@   R2 = n
@   R4 = number of IRQ snapshots saved
@   R5 = number of FIQ snapshots restored
@   R6 = mirror of the shared snapshot stack pointer
@   R7 = number of saved snapshots currently on the stack
@
@ Notes:
@   * Vectors start at 0x00000000 in the GBA BIOS region. Runtime stacks use
@     GBA IWRAM (0x03000000-0x03007FFF).
@   * The shared Fibonacci snapshot stack starts at 0x03008000, one word past
@     the end of IWRAM. The first full-descending push lands at 0x03007FF4.
@   * IRQ and FIQ have banked architectural SP registers. To make IRQ save and
@     FIQ restore the same stack, both handlers briefly switch to System mode
@     with IRQ/FIQ masked and use the System SP as the shared snapshot stack.
@   * Main briefly masks IRQ/FIQ while committing the two-register Fibonacci
@     update. Therefore every accepted interrupt sees a coherent (R0,R1,R2)
@     sequence state.
@ ==============================================================================

    .arch   armv4t
    .arm
    .section .text
    .global  _start

@ ==============================================================================
@ Exception vector table
@ ==============================================================================
_start:
    B   reset_handler        @ 0x00 Reset
    B   trap                 @ 0x04 Undefined
    B   trap                 @ 0x08 Software Interrupt
    B   trap                 @ 0x0C Prefetch Abort
    B   trap                 @ 0x10 Data Abort
    NOP                      @ 0x14 Reserved
    B   irq_handler          @ 0x18 IRQ
    B   fiq_handler          @ 0x1C FIQ

trap:
    B   trap

@ ==============================================================================
@ Reset: initialize banked stacks, then enter System mode with IRQ/FIQ enabled.
@ ==============================================================================
reset_handler:
    MOV     R3, #0x03000000      @ GBA IWRAM base

    MSR     CPSR, #0xD1          @ FIQ mode, IRQ+FIQ masked
    ADD     SP, R3, #0x5C00
    MSR     CPSR, #0xD2          @ IRQ mode, IRQ+FIQ masked
    ADD     SP, R3, #0x6000
    MSR     CPSR, #0xD7          @ Abort mode, IRQ+FIQ masked
    ADD     SP, R3, #0x5000
    MSR     CPSR, #0xDB          @ Undefined mode, IRQ+FIQ masked
    ADD     SP, R3, #0x5400
    MSR     CPSR, #0xD3          @ Supervisor mode, IRQ+FIQ masked
    ADD     SP, R3, #0x5800

    MSR     CPSR, #0x1F          @ System mode, IRQ+FIQ enabled
    ADD     SP, R3, #0x8000      @ shared Fibonacci snapshot stack

@ ==============================================================================
@ Main Fibonacci loop
@ ==============================================================================
main:
    MOV     R0, #0               @ F(0)
    MOV     R1, #1               @ F(1)
    MOV     R2, #0               @ n
    MOV     R4, #0               @ IRQ save count
    MOV     R5, #0               @ FIQ restore count
    MOV     R6, SP               @ mirror shared snapshot SP for debug
    MOV     R7, #0               @ saved snapshot depth

fib_loop:
    MOV     R8, #0x2          @ slow the sequence for presentation
delay_loop:
    SUBS    R8, R8, #1
    BNE     delay_loop

    MSR     CPSR, #0xDF          @ System mode, mask IRQ+FIQ during commit
    ADD     R12, R0, R1          @ next = current + next
    MOV     R0, R1               @ current = old next
    MOV     R1, R12              @ next = computed next
    ADD     R2, R2, #1           @ n++
    MSR     CPSR, #0x1F          @ System mode, IRQ+FIQ enabled

    B       fib_loop

@ ==============================================================================
@ IRQ: save current Fibonacci state on the shared System-mode stack.
@
@ IRQ entry masks IRQ but leaves FIQ enabled on ARM. Mask FIQ explicitly while
@ the shared stack pointer/depth are being updated, then return with SUBS so SPSR
@ restores the pre-IRQ CPSR.
@ ==============================================================================
irq_handler:
    MSR     CPSR, #0xD2          @ IRQ mode, IRQ+FIQ masked
    STMFD   SP!, {LR}            @ preserve IRQ LR while changing modes
    MSR     CPSR, #0xDF          @ System mode, IRQ+FIQ masked
    STMFD   SP!, {R0-R2}         @ push F(n), F(n+1), n
    MOV     R6, SP               @ mirror shared snapshot SP for debug
    MSR     CPSR, #0xD2          @ back to IRQ mode
    ADD     R4, R4, #1
    ADD     R7, R7, #1
    LDMFD   SP!, {LR}
    SUBS    PC, LR, #4

@ ==============================================================================
@ FIQ: restore the latest saved Fibonacci state, if one exists.
@ ==============================================================================
fiq_handler:
    STMFD   SP!, {LR}            @ preserve FIQ LR while changing modes
    CMP     R7, #0
    BEQ     fiq_empty
    MSR     CPSR, #0xDF          @ System mode, IRQ+FIQ masked
    LDMFD   SP!, {R0-R2}         @ pop F(n), F(n+1), n
    MOV     R6, SP               @ mirror shared snapshot SP for debug
    MSR     CPSR, #0xD1          @ back to FIQ mode
    ADD     R5, R5, #1
    SUB     R7, R7, #1

fiq_empty:
    LDMFD   SP!, {LR}
    SUBS    PC, LR, #4

    .end
