@ ==============================================================================
@ ARM7TDMI Thumb Instruction Set Test Suite
@ ARM DDI 0029E, §5 - 19 Thumb instruction formats
@
@ Exercises every Thumb format supported by the custom ARM7TDMI core
@ (decoder.v parameters Mv_Shift_Reg .. L_Branch_Link, plus Interrupt_T).
@
@ Flow:
@   - boot in ARM mode (CPU resets with T=0)
@   - set SP, then BX into the Thumb block
@   - run all Thumb tests
@   - halt in Thumb mode (B .)
@ ==============================================================================

    .arch   armv4t

@ ==============================================================================
@ DATA  -  buffers and constants for load/store tests
@ ==============================================================================
    .section .data
    .balign 4

word_pool:
    .word   0xDEADBEEF, 0x12345678, 0xCAFEBABE, 0x0BADF00D
hword_pool:
    .hword  0x7FFF, 0x8001, 0xABCD, 0x0001
    .balign 4
byte_pool:
    .byte   0x7F, 0x80, 0xFF, 0x01, 0x00, 0xAA, 0x55, 0xFE
    .balign 4
scratch:
    .space  64                  @ store-test workspace

@ ==============================================================================
@ BSS  -  stack
@ ==============================================================================
    .section .bss
    .balign 4
    .space  256
stack_top:

@ ==============================================================================
@ CODE  -  ARM boot
@ ==============================================================================
    .section .text
    .arm
    .global _start

_start:
    LDR   R13, =stack_top       @ init SP (R13)
    LDR   R0, =thumb_entry + 1  @ LSB=1 -> Thumb target
    BX    R0                    @ switch to Thumb state

    .ltorg

@ ==============================================================================
@ THUMB CODE
@ ==============================================================================
    .thumb
    .thumb_func
thumb_entry:

@ ==============================================================================
@ §1  Format 1: Move Shifted Register  (LSL/LSR/ASR Rd, Rs, #imm5)
@ Thumb-1 (pre-UAL) syntax: no `S' suffix — these always update flags.
@ ==============================================================================
sec_t_mv_shift:
    MOV   R0, #0xF0             @ Format 3 used as seed
    LSL   R1, R0, #0            @ LSL #0 -> no shift; C unchanged
    LSL   R1, R0, #1
    LSL   R1, R0, #31           @ shift bit 0 into MSB
    LSR   R1, R0, #1
    LSR   R1, R0, #32           @ encoded as #0 -> LSR #32, result=0
    ASR   R1, R0, #1
    ASR   R1, R0, #32           @ sign-fill result

@ ==============================================================================
@ §2  Format 2: Add/Subtract  (3-bit reg or 3-bit immediate)
@ ==============================================================================
sec_t_add_sub:
    MOV   R0, #10
    MOV   R1, #3
    ADD   R2, R0, R1            @ ADD Rd, Rs, Rn
    SUB   R2, R0, R1            @ SUB Rd, Rs, Rn
    ADD   R2, R0, #0            @ ADD Rd, Rs, #0
    ADD   R2, R0, #7            @ ADD Rd, Rs, #imm3 (max)
    SUB   R2, R0, #1
    SUB   R2, R0, #7

@ ==============================================================================
@ §3  Format 3: MOV/CMP/ADD/SUB immediate  (8-bit imm; always updates flags)
@ ==============================================================================
sec_t_imm_op:
    MOV   R0, #0                @ Z=1
    MOV   R0, #0xFF             @ max imm8
    MOV   R1, #0x55
    CMP   R0, #0xFF             @ Z=1
    CMP   R0, #0x00
    ADD   R0, R0, #1            @ Rd = Rd + imm8
    ADD   R0, R0, #0xFF
    SUB   R0, R0, #1
    SUB   R0, R0, #0xFF

@ ==============================================================================
@ §4  Format 4: ALU operations  (16 ops, all on low regs, all set flags)
@ ==============================================================================
sec_t_alu_op:
    MOV   R0, #0xF0
    MOV   R1, #0x0F
    MOV   R2, #4
    AND   R0, R1                @ R0 &= R1
    MOV   R0, #0xF0
    EOR   R0, R1                @ R0 ^= R1
    MOV   R0, #0x01
    LSL   R0, R2                @ Rd <<= Rs[7:0]
    MOV   R0, #0x80
    LSR   R0, R2                @ Rd >>= Rs (logical)
    MOV   R0, #0x80
    ASR   R0, R2                @ Rd >>= Rs (arithmetic)
    MOV   R0, #1
    MOV   R1, #0
    ADD   R0, R0, #0            @ clear C
    ADC   R0, R1                @ Rd += Rs + C
    SBC   R0, R1                @ Rd -= Rs - NOT C
    MOV   R0, #0x01
    MOV   R1, #1
    ROR   R0, R1                @ Rd = ROR(Rd, Rs)
    MOV   R0, #0xF0
    MOV   R1, #0x0F
    TST   R0, R1                @ flags only
    NEG   R0, R1                @ Rd = -Rs (RSB Rd,Rs,#0)
    MOV   R0, #10
    MOV   R1, #10
    CMP   R0, R1                @ Z=1
    MOV   R1, #5
    CMN   R0, R1                @ flags from Rd + Rs
    ORR   R0, R1                @ Rd |= Rs
    MOV   R0, #6
    MOV   R1, #7
    MUL   R0, R1                @ Rd = Rd * Rs
    MOV   R0, #0xFF
    MOV   R1, #0x0F
    BIC   R0, R1                @ Rd &= ~Rs
    MVN   R0, R1                @ Rd = ~Rs

@ ==============================================================================
@ §5  Format 5: Hi register ops / BX  (no S; flags only on CMP)
@ ==============================================================================
sec_t_hi_reg:
    MOV   R0, #0x11
    MOV   R8,  R0               @ MOV Hd, Rs
    MOV   R1,  R8               @ MOV Rd, Hs
    MOV   R9,  R8               @ MOV Hd, Hs
    ADD   R8,  R0               @ ADD Hd, Rs  (R8 += R0)
    ADD   R1,  R8               @ ADD Rd, Hs
    ADD   R9,  R8               @ ADD Hd, Hs
    CMP   R1,  R8               @ CMP Rd, Hs  (sets flags)
    CMP   R8,  R0               @ CMP Hd, Rs
    CMP   R8,  R9               @ CMP Hd, Hs

    @ BX Rs / BX Hs - round-trip through ARM and back to Thumb
    LDR   R0, =arm_pivot        @ ARM target (LSB=0)
    BX    R0                    @ BX Rs -> exits Thumb

    .ltorg

    .arm
arm_pivot:
    LDR   R0, =thumb_resume + 1 @ Thumb target (LSB=1)
    BX    R0                    @ back to Thumb via low reg
    .ltorg

    .thumb
    .thumb_func
thumb_resume:
    LDR   R0, =thumb_after_bx_hi + 1
    MOV   R8, R0
    BX    R8                    @ BX Hs

    .ltorg
    .thumb_func
thumb_after_bx_hi:

@ ==============================================================================
@ §6  Format 6: PC-relative Load  (LDR Rd, [PC, #imm8*4])
@ ==============================================================================
sec_t_pc_rel:
    LDR   R0, =word_pool        @ assembler emits Format 6
    LDR   R1, =0xCAFEBABE
    LDR   R2, =0x12345678
    B     sec_t_ls_reg          @ skip the literal pool below
    @ keep literals reachable
    .ltorg

@ ==============================================================================
@ §7  Format 7: Load/Store with register offset
@ ==============================================================================
sec_t_ls_reg:
    LDR   R0, =scratch          @ base
    MOV   R1, #0
    MOV   R2, #0xA5             @ payload
    STR   R2, [R0, R1]          @ STR Rd, [Rb, Ro]
    LDR   R3, [R0, R1]          @ LDR
    STRB  R2, [R0, R1]          @ STRB
    LDRB  R3, [R0, R1]          @ LDRB
    MOV   R1, #4
    STR   R2, [R0, R1]

@ ==============================================================================
@ §8  Format 8: Load/Store Sign-Extended Byte/Halfword (reg offset)
@ ==============================================================================
sec_t_ls_signex:
    LDR   R0, =scratch
    MOV   R1, #8
    MOV   R2, #0x80             @ MSB set for sign-extension tests
    STRH  R2, [R0, R1]          @ STRH
    LDRH  R3, [R0, R1]          @ LDRH  (zero-ext)
    LDRSH R3, [R0, R1]          @ LDSH  (sign-ext)
    STRB  R2, [R0, R1]
    LDRSB R3, [R0, R1]          @ LDSB  (sign-ext)

@ ==============================================================================
@ §9  Format 9: Load/Store with immediate offset (word / byte)
@ ==============================================================================
sec_t_ls_imm:
    LDR   R0, =scratch
    MOV   R2, #0x5A
    STR   R2, [R0, #0]          @ STR Rd, [Rb, #imm5*4]
    STR   R2, [R0, #4]
    STR   R2, [R0, #124]        @ max offset (31*4)
    LDR   R3, [R0, #0]
    LDR   R3, [R0, #4]
    STRB  R2, [R0, #0]          @ STRB Rd, [Rb, #imm5]
    STRB  R2, [R0, #1]
    STRB  R2, [R0, #31]
    LDRB  R3, [R0, #1]

@ ==============================================================================
@ §10  Format 10: Load/Store Halfword (immediate offset)
@ ==============================================================================
sec_t_ls_hw:
    LDR   R0, =scratch
    MOV   R2, #0xC3
    STRH  R2, [R0, #0]          @ STRH Rd, [Rb, #imm5*2]
    STRH  R2, [R0, #2]
    STRH  R2, [R0, #62]         @ max offset (31*2)
    LDRH  R3, [R0, #0]
    LDRH  R3, [R0, #2]

@ ==============================================================================
@ §11  Format 11: SP-relative Load/Store
@ ==============================================================================
sec_t_sp_rel:
    MOV   R0, #0xA5
    STR   R0, [SP, #0]          @ STR Rd, [SP, #imm8*4]
    STR   R0, [SP, #4]
    LDR   R1, [SP, #0]
    LDR   R1, [SP, #4]

@ ==============================================================================
@ §12  Format 12: Load Address  (ADD Rd, PC/SP, #imm8*4)
@ ==============================================================================
sec_t_load_addr:
    ADD   R0, PC, #0            @ ADD Rd, PC, #imm8*4
    ADD   R0, PC, #4
    ADD   R0, PC, #1020         @ max (255*4)
    ADD   R1, SP, #0            @ ADD Rd, SP, #imm8*4
    ADD   R1, SP, #16

@ ==============================================================================
@ §13  Format 13: Add offset to SP  (ADD/SUB SP, #imm7*4)
@ ==============================================================================
sec_t_add_sp:
    ADD   SP, SP, #4            @ ADD SP, #+imm7*4
    ADD   SP, SP, #508          @ max (127*4)
    SUB   SP, SP, #4            @ ADD SP, #-imm7*4
    SUB   SP, SP, #508

@ ==============================================================================
@ §14  Format 14: Push/Pop registers  (with optional LR/PC)
@ ==============================================================================
sec_t_push_pop:
    MOV   R0, #0x10
    MOV   R1, #0x20
    MOV   R2, #0x30
    MOV   R3, #0x40
    PUSH  {R0}                  @ single reg
    PUSH  {R0-R3}               @ multiple
    PUSH  {R0, R2}              @ sparse list
    PUSH  {R0-R3, LR}           @ with LR (R bit)
    POP   {R4-R7}               @ pops R0-R3 worth of values into R4-R7
    POP   {R4, R5}
    POP   {R4-R7}
    POP   {R4}

@ ==============================================================================
@ §15  Format 15: Multiple Load/Store  (STMIA / LDMIA, Rb!)
@ ==============================================================================
sec_t_multi_ls:
    LDR   R0, =scratch
    MOV   R1, #0x11
    MOV   R2, #0x22
    MOV   R3, #0x33
    MOV   R4, #0x44
    STMIA R0!, {R1-R4}          @ store and update base
    LDR   R0, =scratch
    LDMIA R0!, {R5-R7}          @ partial list, base writeback
    LDR   R0, =scratch
    STMIA R0!, {R1, R3}         @ sparse list
    LDR   R0, =scratch
    LDMIA R0!, {R5}             @ single reg

@ ==============================================================================
@ §16  Format 16: Conditional Branch  (B<cond> label, ±256-byte range)
@ ==============================================================================
sec_t_cond_branch:
    MOV   R0, #5
    MOV   R1, #5
    CMP   R0, R1                @ Z=1, C=1
    BEQ   1f
    B     sec_t_cond_branch     @ would loop on bug
1:  BNE   2f                    @ taken? no -> fall through (Z=1)
    BCS   2f                    @ taken (C=1)
2:  MOV   R0, #10
    MOV   R1, #5
    CMP   R0, R1                @ Z=0, C=1, N=0, V=0
    BHI   3f                    @ C=1 && Z=0 -> taken
    B     sec_t_cond_branch
3:  BGE   4f                    @ N==V -> taken
    B     sec_t_cond_branch
4:  BGT   5f                    @ Z=0 && N==V -> taken
    B     sec_t_cond_branch
5:  MOV   R0, #0
    SUB   R0, R0, #1            @ result negative, C=0
    BMI   6f                    @ N=1
    B     sec_t_cond_branch
6:  BCC   7f                    @ C=0 -> taken
    B     sec_t_cond_branch
7:  BLT   8f                    @ N!=V or actually here N=1,V=0 -> taken
    B     sec_t_cond_branch
8:  BLE   9f                    @ Z=1 || N!=V -> taken
    B     sec_t_cond_branch
9:  @ remaining condition codes - just emit them, take or not depends on state
    MOV   R0, #1
    ADD   R0, R0, #0
    BPL   10f                   @ N=0
    B     sec_t_cond_branch
10: BVC   11f                   @ V=0 normally
    B     sec_t_cond_branch
11: @ BVS / BLS: emit but make conditions for fall-through
    BVS   12f                   @ V=0 -> not taken, fall through
12: MOV   R0, #10
    CMP   R0, R0
    BLS   13f                   @ C=1 || Z=1 -> Z=1 taken
    B     sec_t_cond_branch
13:

@ ==============================================================================
@ §17  Format 17: Software Interrupt  (SWI #imm8)
@ NOTE: SWI vector at 0x00000008 must restore PC via MOVS PC, LR
@ (same caveat as the ARM-mode test).
@ ==============================================================================
sec_t_swi:
    SWI   #0
    SWI   #1
    SWI   #0xFF                 @ max 8-bit immediate

@ ==============================================================================
@ §18  Format 18: Unconditional Branch  (B label, 11-bit signed offset)
@ ==============================================================================
sec_t_uncon_branch:
    B     1f
    B     sec_t_uncon_branch    @ skipped
1:  B     2f
2:

@ ==============================================================================
@ §19  Format 19: Long Branch with Link  (BL label, 22-bit signed range)
@ ==============================================================================
sec_t_bl:
    BL    thumb_subroutine      @ call (encoded as 2 x 16-bit halves)
    BL    thumb_subroutine

@ ==============================================================================
@ HALT  (Thumb infinite loop)
@ ==============================================================================
test_done:
    B     test_done

@ ==============================================================================
@ SUBROUTINE for BL test  -  returns via BX LR (BX Hs form)
@ ==============================================================================
    .thumb_func
thumb_subroutine:
    MOV   R0, #0xAB
    BX    LR

    .ltorg
