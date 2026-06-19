@ ==============================================================================
@ dma_irq_memory_test.s - DMA IRQ diagnostic for gba_rev0
@
@ This test exercises only the DMA3 completion interrupt path through IF, IE,
@ IME, the ARM IRQ exception vector, and the IRQ return sequence.
@
@ Failure reporting:
@   R7  = phase
@   R0  = 0xPC: P = phase, C = check inside that phase
@   R8  = observed value
@   R9  = expected value
@   R10 = address checked
@ ============================================================================

    .arch   armv4t
    .arm
    .section .text
    .global _start

    .macro LOADH reg, value
        MOV     \reg, #((\value) & 0x00FF)
        ORR     \reg, \reg, #((\value) & 0xFF00)
    .endm

    .macro LOADW reg, b3, b2, b1, b0
        MOV     \reg, #\b0
        ORR     \reg, \reg, #(\b1 << 8)
        ORR     \reg, \reg, #(\b2 << 16)
        ORR     \reg, \reg, #(\b3 << 24)
    .endm

    .macro PTR reg, base, offset
        MOV     \reg, #\base
        ADD     \reg, \reg, #\offset
    .endm

    .macro CHECK_EQ code, addr_reg
        MOV     R8, R2
        MOV     R9, R1
        MOV     R10, \addr_reg
        CMP     R2, R1
        BNE     .Lcheck_fail\@
        B       .Lcheck_done\@
.Lcheck_fail\@:
        MOV     R0, R7, LSL #4
        ORR     R0, R0, #\code
        B       fail
.Lcheck_done\@:
    .endm

@ Program a DMA channel using source/destination addresses already in registers.
    .macro DMA_START_REG dma_offset, src_reg, dst_reg, count, cnt_hi_b3, cnt_hi_b2
        MOV     R4, #0x04000000
        ORR     R4, R4, #\dma_offset
        STR     \src_reg, [R4]       @ DMAxSAD
        STR     \dst_reg, [R4, #4]   @ DMAxDAD
        LOADW   R1, \cnt_hi_b3, \cnt_hi_b2, 0x00, \count
        STR     R1, [R4, #8]         @ DMAxCNT
    .endm

_start:
    B       reset_handler
    B       trap
    B       trap
    B       trap
    B       trap
    NOP
    B       irq_handler
    B       trap

trap:
    MOV     R7, #0x0F
    MOV     R0, #0xEE
    B       trap

@ DMA3 interrupt handler. IF.DMA3 is write-one-to-clear at 0x04000202.
irq_handler:
    MOV     R6, #0xD000
    ORR     R6, R6, #0x0D          @ completion marker: 0xD00D
    MOV     R0, #0x04000000
    ADD     R0, R0, #0x200
    MOV     R1, #0x800             @ DMA3 interrupt bit
    STRH    R1, [R0, #2]           @ IF
    SUBS    PC, LR, #4

reset_handler:
    MSR     CPSR, #0xDF            @ System mode, IRQ/FIQ masked.
    MOV     R0, #0
    MOV     R7, #0
    MOV     R8, #0
    MOV     R9, #0
    MOV     R10, #0

@ ==============================================================================
@ PHASE 1 - DMA3 IRQ through IF/IE/IME
@ The handler marks R6, clears IF.DMA3, and returns with SUBS PC, LR, #4.
@ ==============================================================================
phase_dma_irq:
    MOV     R7, #1
    MOV     R6, #0

@ Enable the DMA3 source in IE and the global IME gate; clear stale IF.DMA3.
    PTR     R4, 0x04000000, 0x200
    MOV     R1, #0x800
    STRH    R1, [R4]             @ IE.DMA3 = 1
    STRH    R1, [R4, #2]         @ clear IF.DMA3
    MOV     R1, #1
    STRH    R1, [R4, #8]         @ IME = 1

    PTR     R5, 0x03000000, 0x780
    LOADW   R1, 0xD3, 0xD2, 0xD1, 0xD0
    STR     R1, [R5]
    LOADW   R1, 0xD7, 0xD6, 0xD5, 0xD4
    STR     R1, [R5, #4]
    PTR     R6, 0x03000000, 0x7A0
    MOV     R1, #0
    STR     R1, [R6]
    STR     R1, [R6, #4]

    MSR     CPSR, #0x5F          @ System mode, IRQ enabled, FIQ masked.
    DMA_START_REG 0xD4, R5, R6, 2, 0xC4, 0x00

irq_wait:
    LOADH   R1, 0xD00D
    CMP     R6, R1
    BEQ     irq_seen
    MOV     R0, #0x30
    B       irq_wait

irq_seen:
    MSR     CPSR, #0xDF          @ mask IRQ/FIQ after the one-shot test
    MOV     R2, R6
    LOADH   R1, 0xD00D
    CHECK_EQ 0x01, R6

    PTR     R5, 0x03000000, 0x7A0
    LDR     R2, [R5]
    LOADW   R1, 0xD3, 0xD2, 0xD1, 0xD0
    CHECK_EQ 0x02, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xD7, 0xD6, 0xD5, 0xD4
    CHECK_EQ 0x03, R5

    PTR     R5, 0x04000000, 0x200
    LDRH    R2, [R5, #2]         @ handler must have cleared IF.DMA3
    MOV     R1, #0
    CHECK_EQ 0x04, R5

all_pass:
    MOV     R7, #0x0F
    MOV     R0, #0xAD
    B       all_pass

fail:
    B       fail

    .end
