@ ==============================================================================
@ thumb_memory_test.s - Thumb-mode load/store diagnostic for gba_rev0
@
@ Companion to memory_system_test.s (which covers ARM-mode load/store). This one
@ boots in ARM, BX-es into Thumb, and self-checks every Thumb load/store format
@ against IWRAM (0x03000000, clean 32-bit native port) so a failure isolates to
@ the Thumb decoder rather than to a narrow-port memory. One final phase touches
@ SDRAM-backed EWRAM as a cross-region sanity check.
@
@ Thumb load/store formats covered (ARM DDI 0029E, §5):
@   Format 6  PC-relative load  -> exercised implicitly by every `LDR Rd,=const`
@   Format 7  reg offset, word/byte           (phase 3)
@   Format 8  reg offset, halfword + SIGNED    (phase 4)  <- LDRSB/LDRSH live ONLY here
@   Format 9  imm offset, word/byte            (phase 1)
@   Format 10 imm offset, halfword             (phase 2)
@   Format 11 SP-relative load/store           (phase 5)
@   Format 14 PUSH / POP                       (phase 5)
@   Format 15 STMIA / LDMIA with writeback     (phase 6)
@
@ Failure reporting (all low regs, visible in sim / SignalTap):
@   R7 = phase number          R2 = observed value
@   R0 = 0xPC fail code        R1 = expected value
@        (P = phase, C = check)
@ R7 is reserved as the phase number, so no register list (PUSH/POP/LDM/STM)
@ includes R7. R6 holds the IWRAM base 0x03000000 for the whole run.
@ ==============================================================================

    .arch   armv4t

@ Compare observed (R2) against expected (R1); on mismatch latch R0 = phase<<4 |
@ code and halt. On match, fall through (R1/R2 untouched, so a word round-trip can
@ reuse the stored value in R1 as its own expected and spend just one literal).
    .macro TCHECK code
        CMP     R2, R1
        BEQ     .Lok\@
        MOV     R0, R7
        LSL     R0, R0, #4
        ADD     R0, R0, #\code
        B       fail
.Lok\@:
    .endm

@ ==============================================================================
@ ARM boot - set the Thumb stack (cannot LDR SP in Thumb) then switch state.
@ ==============================================================================
    .section .text
    .arm
    .global _start

_start:
    B       reset_handler
    B       trap
    B       trap
    B       trap
    B       trap
    NOP
    B       trap
    B       trap

trap:
    MOV     R7, #0x0F
    MOV     R0, #0xEE
    B       trap

reset_handler:
    LDR     SP, =0x03007F00         @ stack inside IWRAM (PUSH grows down)
    LDR     R0, =thumb_entry + 1    @ LSB=1 -> Thumb target
    BX      R0
    .ltorg

@ ==============================================================================
@ THUMB CODE
@ ==============================================================================
    .thumb
    .thumb_func
thumb_entry:
    MOV     R7, #0
    LDR     R6, =0x03000000         @ IWRAM base, held for the whole test

@ ==============================================================================
@ PHASE 1 - Format 9: word / byte load+store, immediate offset (IWRAM)
@ ==============================================================================
phase_imm_wb:
    MOV     R7, #1

    LDR     R1, =0x89ABCDEF         @ non-zero high half so a dropped byte shows
    STR     R1, [R6, #0]
    LDR     R2, [R6, #0]
    TCHECK  0x01
    STR     R1, [R6, #124]          @ max imm5*4 offset
    LDR     R2, [R6, #124]
    TCHECK  0x02

    MOV     R1, #0xA5
    STRB    R1, [R6, #5]
    LDRB    R2, [R6, #5]            @ LDRB zero-extends -> 0x000000A5
    TCHECK  0x03
    STRB    R1, [R6, #31]           @ max imm5 offset
    LDRB    R2, [R6, #31]
    TCHECK  0x04

@ ==============================================================================
@ PHASE 2 - Format 10: halfword load+store, immediate offset (IWRAM)
@ ==============================================================================
phase_imm_h:
    MOV     R7, #2

    LDR     R1, =0xBEEF             @ = 0x0000BEEF
    STRH    R1, [R6, #8]
    LDRH    R2, [R6, #8]            @ LDRH zero-extends
    TCHECK  0x01
    STRH    R1, [R6, #62]           @ max imm5*2 offset
    LDRH    R2, [R6, #62]
    TCHECK  0x02

    MOV     R1, #0                  @ byte lanes assemble into one halfword
    STRH    R1, [R6, #8]
    MOV     R1, #0x34
    STRB    R1, [R6, #8]            @ low lane
    MOV     R1, #0x12
    STRB    R1, [R6, #9]            @ high lane
    LDRH    R2, [R6, #8]
    LDR     R1, =0x1234
    TCHECK  0x03

    B       1f                      @ guarded literal pool (phases 1-2)
    .ltorg
1:

@ ==============================================================================
@ PHASE 3 - Format 7: word / byte load+store, register offset (IWRAM)
@ ==============================================================================
phase_reg_wb:
    MOV     R7, #3

    MOV     R3, #16                 @ offset in a register
    LDR     R1, =0x0BADF00D
    STR     R1, [R6, R3]
    LDR     R2, [R6, R3]
    TCHECK  0x01

    MOV     R1, #0x5A
    STRB    R1, [R6, R3]            @ overwrites byte 0 of the word above
    LDRB    R2, [R6, R3]
    TCHECK  0x02

@ ==============================================================================
@ PHASE 4 - Format 8: halfword + SIGNED load/store, register offset (IWRAM)
@ Thumb's only signed loads (LDRSB/LDRSH) are this format.
@ ==============================================================================
phase_reg_signed:
    MOV     R7, #4

    MOV     R3, #20
    LDR     R1, =0xBEEF
    STRH    R1, [R6, R3]
    LDRH    R2, [R6, R3]            @ zero-extend
    TCHECK  0x01

    LDR     R1, =0x80F0             @ bit 15 set -> negative halfword
    STRH    R1, [R6, R3]
    LDRSH   R2, [R6, R3]            @ sign-extend
    LDR     R1, =0xFFFF80F0
    TCHECK  0x02

    MOV     R0, #0x80               @ bit 7 set -> negative byte
    STRB    R0, [R6, R3]
    LDRSB   R2, [R6, R3]            @ sign-extend
    MOV     R1, #0x7F
    MVN     R1, R1                  @ 0xFFFFFF80
    TCHECK  0x03

    MOV     R0, #0x7F               @ positive byte must stay positive
    STRB    R0, [R6, R3]
    LDRSB   R2, [R6, R3]
    MOV     R1, #0x7F
    TCHECK  0x04

    B       1f                      @ guarded literal pool (phases 3-4)
    .ltorg
1:

@ ==============================================================================
@ PHASE 5 - Format 11 (SP-relative) + Format 14 (PUSH/POP)
@ Lists stay within R0-R5: R6 is the base, R7 is the phase number.
@ ==============================================================================
phase_sp_stack:
    MOV     R7, #5

    LDR     R1, =0x5A5A5A5A
    STR     R1, [SP, #0]            @ Format 11, positive offset from SP
    LDR     R2, [SP, #0]
    TCHECK  0x01
    STR     R1, [SP, #8]
    LDR     R2, [SP, #8]
    TCHECK  0x02

    MOV     R0, #0x11
    MOV     R1, #0x22
    MOV     R2, #0x33
    PUSH    {R0-R2}                 @ pre-decrement, R0 at lowest address
    MOV     R0, #0
    MOV     R1, #0
    MOV     R2, #0
    POP     {R3-R5}                 @ R3<-0x11, R4<-0x22, R5<-0x33; SP balanced

    MOV     R2, R3
    MOV     R1, #0x11
    TCHECK  0x03
    MOV     R2, R4
    MOV     R1, #0x22
    TCHECK  0x04
    MOV     R2, R5
    MOV     R1, #0x33
    TCHECK  0x05

@ ==============================================================================
@ PHASE 6 - Format 15: STMIA / LDMIA with base writeback (IWRAM)
@ Separate scratch window at IWRAM+0x100; lists stay within R1-R4.
@ ==============================================================================
phase_multi:
    MOV     R7, #6

    LDR     R5, =0x03000100         @ STM/LDM scratch base
    MOV     R0, R5                  @ working base (gets the writeback)
    MOV     R1, #0xA1
    MOV     R2, #0xB2
    MOV     R3, #0xC3
    MOV     R4, #0xD4
    STMIA   R0!, {R1-R4}            @ store 4 words, R0 += 16
    ADD     R5, #16                 @ expected writeback
    MOV     R2, R0
    MOV     R1, R5
    TCHECK  0x01

    LDR     R0, =0x03000100         @ read each stored word back
    LDR     R2, [R0, #0]
    MOV     R1, #0xA1
    TCHECK  0x02
    LDR     R2, [R0, #4]
    MOV     R1, #0xB2
    TCHECK  0x03
    LDR     R2, [R0, #8]
    MOV     R1, #0xC3
    TCHECK  0x04
    LDR     R2, [R0, #12]
    MOV     R1, #0xD4
    TCHECK  0x05

    LDR     R0, =0x03000100
    LDMIA   R0!, {R1-R4}            @ R1=A1,R2=B2,R3=C3,R4=D4; R0 += 16
    MOV     R5, R2                  @ save loaded R2 before it is clobbered
    MOV     R2, R1
    MOV     R1, #0xA1
    TCHECK  0x06
    MOV     R2, R5
    MOV     R1, #0xB2
    TCHECK  0x07
    MOV     R2, R3
    MOV     R1, #0xC3
    TCHECK  0x08
    MOV     R2, R4
    MOV     R1, #0xD4
    TCHECK  0x09

    B       1f                      @ guarded literal pool (phases 5-6)
    .ltorg
1:

@ ==============================================================================
@ PHASE 7 - cross-region sanity: SDRAM-backed EWRAM (0x02000000)
@ One full-word round-trip (SDRAM two-beat, non-zero high half) and one signed
@ byte load (SDRAM sign-extend path). Narrow-port (PAL/VRAM/cart) widths are the
@ ARM test's job, so they are not retested here.
@ ==============================================================================
phase_ewram:
    MOV     R7, #7

    LDR     R0, =0x02000000
    LDR     R1, =0x89ABCDEF
    STR     R1, [R0, #0]
    LDR     R2, [R0, #0]
    TCHECK  0x01

    MOV     R1, #0x80
    STRB    R1, [R0, #4]
    MOV     R3, #4
    LDRSB   R2, [R0, R3]            @ Format 8 signed byte from EWRAM
    MOV     R1, #0x7F
    MVN     R1, R1                  @ 0xFFFFFF80
    TCHECK  0x02

@ ==============================================================================
@ HALT
@ ==============================================================================
all_pass:
    MOV     R7, #0x0B
    MOV     R0, #0xBD
    B       all_pass

fail:
    B       fail

    .ltorg
    .end
