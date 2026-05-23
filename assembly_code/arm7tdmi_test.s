@ ==============================================================================
@ ARM7TDMI Complete Instruction Set Test Suite
@ University of Wisconsin-Madison ECE 353/315 - ARM7TDMI ISA Reference
@
@ GAS (GNU Assembler) version - compatible with arm-none-eabi-gcc
@
@ SYNTAX CHANGES FROM armasm TO GAS:
@   ; comment             ->  @ comment
@   AREA ..., DATA        ->  .data / .bss
@   AREA ..., CODE        ->  .text
@   DCD  val              ->  .word  val
@   DCW  val              ->  .hword val
@   DCB  val              ->  .byte  val
@   SPACE n               ->  .space n
@   ALIGN                 ->  .balign 4
@   ARM                   ->  .arm
@   ENTRY + main          ->  .global _start  +  _start:
@   END                   ->  (removed - not needed in GAS)
@   ADRL Rd, lbl          ->  LDR Rd, =lbl   (GAS has no ADRL pseudo)
@   Labels                ->  must have trailing colon in GAS
@   Literal pools         ->  .ltorg placed after unconditional branches
@   CMPS                  ->  CMP  (CMPS is not a valid ARM mnemonic)
@   OR Rd, Rn, #imm       ->  ORR Rd, Rn, #imm  (typo in ISA reference)
@
@ FPGA INTEGRATION NOTES:
@   • The SWI vector at 0x00000008 must jump to a handler that returns
@     via: MOVS PC, LR  (i.e. MOV PC, R14_svc with S bit set).
@   • R13 (SP) is initialised to stack_top at entry (256-byte FD stack).
@   • Adjust the linker -Ttext address to match your FPGA memory map.
@ ==============================================================================

    .arch   armv4t
    .arm

@ ==============================================================================
@ §0  DATA SECTION  (initialized data)
@ ==============================================================================
    .section .data
    .balign 4

word_A:
    .word   0xDEADBEEF
word_B:
    .word   0x12345678
hword_data:
    .hword  0xABCD, 0x8001, 0x7FFF, 0x0001
    .balign 4
byte_data:
    .byte   0xFF, 0x80, 0x7F, 0x01, 0x00, 0xAA, 0x55, 0xFE
    .balign 4
array4:
    .word   0x11111111, 0x22222222, 0x33333333, 0x44444444
result_area:
    .space  128                 @ scratch workspace for store tests

@ ==============================================================================
@ §0  BSS SECTION  (stack - zero initialised)
@ ==============================================================================
    .section .bss
    .balign 4
    .space  256
stack_top:                      @ SP initialised here; stack grows downward (FD)

@ ==============================================================================
@ §0  CODE SECTION
@ ==============================================================================
    .section .text
    .arm
    .global _start

@ ==============================================================================
@ ENTRY POINT
@ ==============================================================================
_start:
    LDR   R13, =stack_top       @ initialise stack pointer (R13 / SP)

@ ==============================================================================
@ §1  MOV / MVN  -  all 11 shifter operand forms
@ ==============================================================================
sec_MOV_MVN:

    @ Form 1: immediate
    MOV   R0, #0
    MOV   R0, #1
    MOV   R0, #0xFF
    MOV   R0, #0xFF00
    MOV   R0, #0x00FF0000
    MOV   R0, #0xF0000000

    @ Form 2: register (Rm, no shift)
    MOV   R1, #0xAB
    MOV   R0, R1

    @ Forms 3-11: register with shift  (seed registers)
    LDR   R1, =0x80000001
    MOV   R2, #4

    @ Form 3: Rm, LSL #imm  (shift amount 0-31)
    MOV   R0, R1, LSL #1
    MOV   R0, R1, LSL #31
    MOVS  R0, R1, LSL #1        @ C <- last bit shifted out; N/Z updated

    @ Form 4: Rm, LSL Rs
    MOV   R0, R1, LSL R2
    MOVS  R0, R1, LSL R2

    @ Form 5: Rm, LSR #imm  (shift amount 1-32)
    MOV   R0, R1, LSR #1
    MOV   R0, R1, LSR #32       @ result = 0
    MOVS  R0, R1, LSR #1

    @ Form 6: Rm, LSR Rs
    MOV   R0, R1, LSR R2
    MOVS  R0, R1, LSR R2

    @ Form 7: Rm, ASR #imm  (shift amount 1-32; sign-fills from left)
    MOV   R0, R1, ASR #1
    MOV   R0, R1, ASR #32
    MOVS  R0, R1, ASR #1

    @ Form 8: Rm, ASR Rs
    MOV   R0, R1, ASR R2
    MOVS  R0, R1, ASR R2

    @ Form 9: Rm, ROR #imm  (rotation amount 1-31)
    MOV   R0, R1, ROR #1
    MOV   R0, R1, ROR #16
    MOVS  R0, R1, ROR #8

    @ Form 10: Rm, ROR Rs
    MOV   R0, R1, ROR R2
    MOVS  R0, R1, ROR R2

    @ Form 11: Rm, RRX  (rotate right 1 bit through carry)
    MOV   R0, R1, RRX
    MOVS  R0, R1, RRX

    @ MVN - complement of shifter_operand  (mirrors all MOV forms above)
    MVN   R0, #0                @ R0 = 0xFFFFFFFF
    MVN   R0, #1                @ R0 = 0xFFFFFFFE
    MVN   R0, #0xFF
    MOV   R1, #0x0F
    MVN   R0, R1                @ Form 2
    MVN   R0, R1, LSL #4        @ Form 3
    MVN   R0, R1, LSL R2        @ Form 4
    MVN   R0, R1, LSR #1        @ Form 5
    MVN   R0, R1, LSR R2        @ Form 6
    MVN   R0, R1, ASR #1        @ Form 7
    MVN   R0, R1, ASR R2        @ Form 8
    MVN   R0, R1, ROR #4        @ Form 9
    MVN   R0, R1, ROR R2        @ Form 10
    MVN   R0, R1, RRX           @ Form 11
    MVNS  R0, #0                @ N=1, Z=0  (S-suffix flag test)
    MOV   R1, #0
    MVNS  R0, R1                @ MVN(0) = 0xFFFFFFFF -> N=1
    MVN   R1, #0                @ R1 = 0xFFFFFFFF
    MVNS  R0, R1                @ MVN(0xFFFFFFFF) = 0 -> Z=1

@ ==============================================================================
@ §2  ADD / ADC
@ ==============================================================================
sec_ADD_ADC:

    @ ADD immediate - sample immediate encodings
    MOV   R0, #5
    ADD   R1, R0, #3
    ADD   R1, R0, #0
    ADD   R1, R0, #0xFF
    ADD   R1, R0, #0xFF00

    @ ADD register (Form 2) and all ten shift forms (Forms 3-11)
    MOV   R2, #10
    ADD   R1, R0, R2            @ Form 2
    MOV   R2, #3
    MOV   R3, #2
    ADD   R1, R0, R2, LSL #2    @ Form 3
    ADD   R1, R0, R2, LSL R3    @ Form 4
    ADD   R1, R0, R2, LSR #1    @ Form 5
    ADD   R1, R0, R2, LSR R3    @ Form 6
    ADD   R1, R0, R2, ASR #1    @ Form 7
    ADD   R1, R0, R2, ASR R3    @ Form 8
    ADD   R1, R0, R2, ROR #4    @ Form 9
    ADD   R1, R0, R2, ROR R3    @ Form 10
    ADD   R1, R0, R2, RRX       @ Form 11

    @ ADDS - flag tests
    ADDS  R1, R0, #1            @ normal; N/Z/C/V updated
    MVN   R0, #0                @ R0 = 0xFFFFFFFF
    ADDS  R1, R0, #1            @ wraps: C=1, Z=1, N=0

    @ ADC - 64-bit addition example: R1:R0 + R3:R2 -> R5:R4
    LDR   R0, =0xFFFFFFFF
    MOV   R1, #1
    MOV   R2, #1
    MOV   R3, #0
    ADDS  R4, R0, R2            @ low words; sets C
    ADC   R5, R1, R3            @ high words plus carry

    @ ADC register / shifter forms
    MOV   R0, #10
    ADDS  R0, R0, #0            @ keep C=1 (no borrow)
    ADC   R1, R0, #3            @ Form 1
    MOV   R2, #4
    MOV   R3, #1
    ADC   R1, R0, R2            @ Form 2
    ADC   R1, R0, R2, LSL #1    @ Form 3
    ADC   R1, R0, R2, LSL R3    @ Form 4
    ADC   R1, R0, R2, LSR #1    @ Form 5
    ADC   R1, R0, R2, LSR R3    @ Form 6
    ADC   R1, R0, R2, ASR #1    @ Form 7
    ADC   R1, R0, R2, ASR R3    @ Form 8
    ADC   R1, R0, R2, ROR #4    @ Form 9
    ADC   R1, R0, R2, ROR R3    @ Form 10
    ADC   R1, R0, R2, RRX       @ Form 11
    ADCS  R1, R0, #1            @ S-suffix

@ ==============================================================================
@ §3  SUB / SBC
@ ==============================================================================
sec_SUB_SBC:

    @ SUB immediate
    MOV   R0, #10
    SUB   R1, R0, #3
    SUB   R1, R0, #0
    SUB   R1, R0, #0xFF

    @ SUB register and all shift forms
    MOV   R2, #4
    MOV   R3, #1
    SUB   R1, R0, R2
    SUB   R1, R0, R2, LSL #1
    SUB   R1, R0, R2, LSL R3
    SUB   R1, R0, R2, LSR #1
    SUB   R1, R0, R2, LSR R3
    SUB   R1, R0, R2, ASR #1
    SUB   R1, R0, R2, ASR R3
    SUB   R1, R0, R2, ROR #2
    SUB   R1, R0, R2, ROR R3
    SUB   R1, R0, R2, RRX

    @ SUBS - flag tests (C is complement of borrow)
    MOV   R0, #5
    SUBS  R1, R0, #5            @ Z=1
    SUBS  R1, R0, #6            @ N=1, C=0 (borrow required)
    SUBS  R1, R0, #4            @ N=0, C=1 (no borrow)

    @ SBC - 64-bit subtraction: R1:R0 - R3:R2 -> R5:R4
    MOV   R0, #0
    MOV   R1, #2
    MOV   R2, #1
    MOV   R3, #0
    SUBS  R4, R0, R2            @ low words; sets C
    SBC   R5, R1, R3            @ high words minus borrow

    @ SBC register / shifter forms
    MOV   R0, #20
    SUBS  R0, R0, #0            @ no borrow -> C=1
    SBC   R1, R0, #3
    MOV   R2, #4
    MOV   R3, #1
    SBC   R1, R0, R2
    SBC   R1, R0, R2, LSL #1
    SBC   R1, R0, R2, LSL R3
    SBC   R1, R0, R2, LSR #1
    SBC   R1, R0, R2, LSR R3
    SBC   R1, R0, R2, ASR #1
    SBC   R1, R0, R2, ASR R3
    SBC   R1, R0, R2, ROR #2
    SBC   R1, R0, R2, ROR R3
    SBC   R1, R0, R2, RRX
    SBCS  R1, R0, #1

@ ==============================================================================
@ §4  RSB / RSC
@ ==============================================================================
sec_RSB_RSC:

    @ RSB: Rd = shifter_operand - Rn
    MOV   R0, #3
    RSB   R1, R0, #10           @ R1 = 10 - 3 = 7
    RSB   R1, R0, #0            @ negate R0: R1 = -3

    MOV   R2, #10
    MOV   R3, #1
    RSB   R1, R0, R2
    RSB   R1, R0, R2, LSL #1    @ R1 = (R2<<1) - R0  [multiply trick]
    RSB   R1, R0, R2, LSL R3
    RSB   R1, R0, R2, LSR #1
    RSB   R1, R0, R2, LSR R3
    RSB   R1, R0, R2, ASR #1
    RSB   R1, R0, R2, ASR R3
    RSB   R1, R0, R2, ROR #4
    RSB   R1, R0, R2, ROR R3
    RSB   R1, R0, R2, RRX

    @ RSBS flag tests
    MOV   R0, #5
    RSBS  R1, R0, #0            @ negate: N=1, C=0
    RSBS  R1, R0, #5            @ result=0 -> Z=1

    @ RSC 64-bit negate: -(R1:R0) -> R3:R2
    MOV   R0, #5
    MOV   R1, #0
    RSBS  R2, R0, #0            @ negate LSW, update C
    RSC   R3, R1, #0            @ negate MSW minus borrow

    @ RSC register / shifter forms
    MOV   R0, #3
    MOV   R2, #10
    MOV   R3, #1
    SUBS  R0, R0, #0            @ set C=1 (no borrow)
    RSC   R1, R0, R2
    RSC   R1, R0, R2, LSL #1
    RSC   R1, R0, R2, LSL R3
    RSC   R1, R0, R2, LSR #1
    RSC   R1, R0, R2, LSR R3
    RSC   R1, R0, R2, ASR #1
    RSC   R1, R0, R2, ASR R3
    RSC   R1, R0, R2, ROR #4
    RSC   R1, R0, R2, ROR R3
    RSC   R1, R0, R2, RRX
    RSCS  R1, R0, #1

@ ==============================================================================
@ §5  AND / ORR / EOR / BIC
@ ==============================================================================
sec_LOGIC:

    @ AND - all shifter forms
    MOV   R0, #0xFF
    MOV   R2, #0xAA
    MOV   R3, #4
    AND   R1, R0, #0x0F
    AND   R1, R0, #0xF0
    AND   R1, R0, R2
    AND   R1, R0, R2, LSL #1
    AND   R1, R0, R2, LSL R3
    AND   R1, R0, R2, LSR #1
    AND   R1, R0, R2, LSR R3
    AND   R1, R0, R2, ASR #1
    AND   R1, R0, R2, ASR R3
    AND   R1, R0, R2, ROR #4
    AND   R1, R0, R2, ROR R3
    AND   R1, R0, R2, RRX
    ANDS  R1, R0, #0x0F         @ N=0, Z=0
    ANDS  R1, R0, #0x00         @ Z=1

    @ ORR - all shifter forms
    MOV   R0, #0x0F
    ORR   R1, R0, #0xF0
    ORR   R1, R0, #0
    ORR   R1, R0, R2
    ORR   R1, R0, R2, LSL #1
    ORR   R1, R0, R2, LSL R3
    ORR   R1, R0, R2, LSR #1
    ORR   R1, R0, R2, LSR R3
    ORR   R1, R0, R2, ASR #1
    ORR   R1, R0, R2, ASR R3
    ORR   R1, R0, R2, ROR #4
    ORR   R1, R0, R2, ROR R3
    ORR   R1, R0, R2, RRX
    ORRS  R1, R0, #0xFF         @ N=0, Z=0

    @ EOR - all shifter forms
    MOV   R0, #0xFF
    EOR   R1, R0, #0xFF         @ R1 = 0
    EOR   R1, R0, #0x0F
    EOR   R1, R0, R2
    EOR   R1, R0, R2, LSL #1
    EOR   R1, R0, R2, LSL R3
    EOR   R1, R0, R2, LSR #1
    EOR   R1, R0, R2, LSR R3
    EOR   R1, R0, R2, ASR #1
    EOR   R1, R0, R2, ASR R3
    EOR   R1, R0, R2, ROR #4
    EOR   R1, R0, R2, ROR R3
    EOR   R1, R0, R2, RRX
    EORS  R1, R0, #0xFF         @ Z=1 (0xFF ^ 0xFF = 0)
    EORS  R1, R0, #0x00         @ no change, N=1 if R0 sign bit set

    @ BIC - all shifter forms
    MOV   R0, #0xFF
    BIC   R1, R0, #0x0F         @ clear lower nibble
    BIC   R1, R0, #0xF0
    BIC   R1, R0, R2
    BIC   R1, R0, R2, LSL #1
    BIC   R1, R0, R2, LSL R3
    BIC   R1, R0, R2, LSR #1
    BIC   R1, R0, R2, LSR R3
    BIC   R1, R0, R2, ASR #1
    BIC   R1, R0, R2, ASR R3
    BIC   R1, R0, R2, ROR #4
    BIC   R1, R0, R2, ROR R3
    BIC   R1, R0, R2, RRX
    BICS  R1, R0, #0xFF         @ Z=1 (clear all set bits)
    BICS  R1, R0, #0x00         @ unchanged; N/Z/C reflect result

@ ==============================================================================
@ §6  CMP / CMN / TST / TEQ
@ ==============================================================================
sec_FLAGS:

    @ CMP (Rn - shifter_operand; result discarded)
    MOV   R0, #10
    MOV   R1, #5
    MOV   R2, #2
    CMP   R0, #10               @ Z=1
    CMP   R0, #9                @ N=0, Z=0, C=1
    CMP   R0, #11               @ N=1, C=0 (borrow)
    CMP   R0, R1
    CMP   R0, R1, LSL #1
    CMP   R0, R1, LSL R2
    CMP   R0, R1, LSR #1
    CMP   R0, R1, LSR R2
    CMP   R0, R1, ASR #1
    CMP   R0, R1, ASR R2
    CMP   R0, R1, ROR #2
    CMP   R0, R1, ROR R2
    CMP   R0, R1, RRX

    @ CMN (Rn + shifter_operand; compare with negative)
    MOV   R0, #10
    CMN   R0, #10               @ 10+10=20; N=0, Z=0
    CMN   R0, #0                @ 10+0=10
    MVN   R1, #9                @ R1 = -10
    CMN   R0, R1                @ 10+(-10)=0 -> Z=1
    MOV   R1, #5
    CMN   R0, R1, LSL #1
    CMN   R0, R1, LSL R2
    CMN   R0, R1, LSR #1
    CMN   R0, R1, LSR R2
    CMN   R0, R1, ASR #1
    CMN   R0, R1, ASR R2
    CMN   R0, R1, ROR #2
    CMN   R0, R1, ROR R2
    CMN   R0, R1, RRX

    @ TST (Rn AND shifter_operand; result discarded)
    MOV   R0, #0xFF
    MOV   R1, #0x0F
    MOV   R2, #4
    TST   R0, #0x80             @ test bit 7
    TST   R0, #0x00             @ Z=1
    TST   R0, R1
    TST   R0, R1, LSL #4
    TST   R0, R1, LSL R2
    TST   R0, R1, LSR #1
    TST   R0, R1, LSR R2
    TST   R0, R1, ASR #1
    TST   R0, R1, ASR R2
    TST   R0, R1, ROR #4
    TST   R0, R1, ROR R2
    TST   R0, R1, RRX

    @ TEQ (Rn XOR shifter_operand; tests equality without affecting V)
    MOV   R0, #0xAB
    MOV   R1, #0xAB
    MOV   R2, #1
    TEQ   R0, #0xAB             @ Z=1
    TEQ   R0, #0x00             @ Z=0
    TEQ   R0, R1                @ Z=1
    TEQ   R0, R1, LSL #1
    TEQ   R0, R1, LSL R2
    TEQ   R0, R1, LSR #1
    TEQ   R0, R1, LSR R2
    TEQ   R0, R1, ASR #1
    TEQ   R0, R1, ASR R2
    TEQ   R0, R1, ROR #4
    TEQ   R0, R1, ROR R2
    TEQ   R0, R1, RRX

@ ==============================================================================
@ §7  MUL / MLA
@ ==============================================================================
sec_MUL_MLA:

    @ MUL: basic
    MOV   R1, #6
    MOV   R2, #7
    MUL   R0, R1, R2            @ R0 = 42
    MULS  R0, R1, R2            @ R0 = 42, N=0, Z=0

    @ MUL: negative operand (2's-complement)
    MVN   R1, #5                @ R1 = -6
    MOV   R2, #7
    MUL   R0, R1, R2
    MULS  R0, R1, R2

    @ MUL: zero operand -> Z=1
    MOV   R1, #0
    MVN   R2, #0                @ R2 = 0xFFFFFFFF
    MUL   R0, R1, R2
    MULS  R0, R1, R2

    @ MUL: large values (only lower 32 bits stored)
    LDR   R1, =0x0001FFFF
    LDR   R2, =0x00010001
    MUL   R0, R1, R2

    @ MLA: Rd = Rn + (Rs * Rm)
    MOV   R1, #3
    MOV   R2, #4
    MOV   R3, #10
    MLA   R0, R1, R2, R3        @ R0 = 10 + 3*4 = 22
    MLAS  R0, R1, R2, R3        @ same + flags

    @ MLA: accumulate into zero
    MOV   R3, #0
    MLA   R0, R1, R2, R3        @ R0 = 0 + 3*4 = 12

    @ MLA: negative product + positive accumulator
    MVN   R1, #2                @ R1 = -3
    MOV   R2, #4
    MOV   R3, #100
    MLA   R0, R1, R2, R3        @ R0 = 100 + (-3*4) = 88

@ ==============================================================================
@ §8  SMULL / SMLAL  (signed 64-bit multiply)
@ ==============================================================================
sec_SMULL_SMLAL:

    @ SMULL: positive x positive
    LDR   R2, =0x00010000
    LDR   R3, =0x00010000
    SMULL R0, R1, R2, R3        @ R1:R0 = 0x0000_0001_0000_0000

    @ SMULL: negative x positive  (-1 * 5 = -5)
    MVN   R2, #0                @ R2 = -1 (0xFFFFFFFF)
    MOV   R3, #5
    SMULL R0, R1, R2, R3        @ R1:R0 = 0xFFFF_FFFF_FFFF_FFFB
    SMULLS R0, R1, R2, R3       @ same + flags

    @ SMULL: most-negative x most-positive
    LDR   R2, =0x80000000
    LDR   R3, =0x7FFFFFFF
    SMULL R0, R1, R2, R3

    @ SMLAL: Rd_MSW:Rd_LSW += Rs * Rm  (signed)
    MOV   R0, #0x100            @ accumulator LSW
    MOV   R1, #0                @ accumulator MSW
    LDR   R2, =0x00001000
    LDR   R3, =0x00001000
    SMLAL R0, R1, R2, R3
    SMLALS R0, R1, R2, R3       @ same + flags

    @ SMLAL: carry into MSW from saturated LSW
    LDR   R0, =0xFFFFFFFF
    MOV   R1, #5
    MVN   R2, #0                @ R2 = -1
    MOV   R3, #1
    SMLAL R0, R1, R2, R3        @ R1:R0 += -1

@ ==============================================================================
@ §9  UMULL / UMLAL  (unsigned 64-bit multiply)
@ ==============================================================================
sec_UMULL_UMLAL:

    @ UMULL: small values  (0xFFFF * 0xFFFF = 0xFFFE_0001)
    MOV   R2, #0xFF
    MOV   R3, #0xFF
    UMULL R0, R1, R2, R3
    UMULLS R0, R1, R2, R3

    @ UMULL: product overflows 32 bits
    LDR   R2, =0xFFFFFFFF
    MOV   R3, #2
    UMULL R0, R1, R2, R3        @ R1:R0 = 0x0000_0001_FFFF_FFFE

    @ UMULL: zero operand -> Z=1
    MOV   R2, #0
    LDR   R3, =0xFFFFFFFF
    UMULL R0, R1, R2, R3
    UMULLS R0, R1, R2, R3       @ Z=1

    @ UMLAL: basic accumulation
    MOV   R0, #0x500
    MOV   R1, #0
    LDR   R2, =0x00001000
    LDR   R3, =0x00001000
    UMLAL R0, R1, R2, R3
    UMLALS R0, R1, R2, R3

    @ UMLAL: carry from LSW into MSW
    LDR   R0, =0xFFFFFFF0
    MOV   R1, #0
    MOV   R2, #0x100
    MOV   R3, #0x1
    UMLAL R0, R1, R2, R3

@ ==============================================================================
@ §10  B / BL
@ ==============================================================================
sec_BRANCH:

    @ Unconditional forward branch
    B     b_fwd1
    MOV   R0, R0           @ never reached
b_fwd1:
    NOP

    @ Forward/backward branch chain
    B     b_fwd2
b_back1:
    B     b_done_chain
b_fwd2:
    B     b_back1
b_done_chain:
    NOP

    @ BL: subroutine call; LR <- return address
    BL    sub_simple
    NOP                          @ execution resumes here after BX LR

    @ BL: subroutine with full stack frame
    BL    sub_stack_frame
    NOP

    B     after_subs             @ jump over subroutine bodies

@ ---- Subroutine bodies --------------------------------------------------------

sub_simple:
    @ Minimal subroutine: return via BX LR
    MOV   R0, #0xBB
    BX    LR

sub_stack_frame:
    @ Full frame: push callee-saved regs + LR, then pop into PC on return
    STMFD R13!, {R0-R3, LR}
    MOV   R0, #1
    MOV   R1, #2
    MOV   R2, #3
    ADD   R3, R0, R1
    ADD   R3, R3, R2
    LDMFD R13!, {R0-R3, PC}     @ restore registers and return

after_subs:
    NOP
    B     sec_BX                 @ skip literal pool below
    .ltorg                       @ *** LITERAL POOL 1 (after subroutine island)

@ ==============================================================================
@ §11  BX  (branch and exchange)
@ ==============================================================================
sec_BX:

    @ BX to ARM label (Rm[0]=0; processor stays in ARM mode)
    ADR   R0, bx_arm_target
    BX    R0
bx_arm_target:
    NOP

    @ BX LR as the preferred return instruction
    BL    sub_bx_lr_test
    NOP

    B     after_bx

sub_bx_lr_test:
    MOV   R4, #0xCC
    BX    LR

after_bx:
    NOP
    .ltorg                       @ *** LITERAL POOL 2 (after BX section)

@ ==============================================================================
@ §12  LDR  -  all 9 register addressing modes
@ ==============================================================================
sec_LDR:
    LDR   R0, =word_A           @ R0 = address of word_A
    MOV   R2, #4
    MOV   R3, #1

    @ Mode 1: [Rn, #+/-imm12]  (base unchanged)
    LDR   R1, [R0, #0]
    LDR   R1, [R0, #4]
    LDR   R1, [R0, #-4]

    @ Mode 2: [Rn, +/-Rm]  (base unchanged)
    LDR   R1, [R0, R2]
    LDR   R1, [R0, -R2]

    @ Mode 3: [Rn, +/-Rm, shift #imm]  (base unchanged)
    LDR   R1, [R0, R3, LSL #2]
    LDR   R1, [R0, R3, LSR #1]
    LDR   R1, [R0, R3, ASR #1]
    LDR   R1, [R0, R3, ROR #1]
    LDR   R1, [R0, R3, RRX]

    @ Mode 4: [Rn, #+/-imm12]!  (pre-indexed; Rn <- memory_address)
    LDR   R0, =word_A
    LDR   R1, [R0, #4]!
    LDR   R0, =word_A
    LDR   R1, [R0, #-4]!

    @ Mode 5: [Rn, +/-Rm]!
    LDR   R0, =word_A
    LDR   R1, [R0, R2]!
    LDR   R0, =word_A
    LDR   R1, [R0, -R2]!

    @ Mode 6: [Rn, +/-Rm, shift]!
    LDR   R0, =word_A
    LDR   R1, [R0, R3, LSL #2]!
    LDR   R0, =word_A
    LDR   R1, [R0, R3, LSR #1]!
    LDR   R0, =word_A
    LDR   R1, [R0, R3, ASR #2]!

    @ Mode 7: [Rn], #+/-imm12  (post-indexed; memory_address=Rn; Rn updated after)
    LDR   R0, =word_A
    LDR   R1, [R0], #4
    LDR   R0, =word_A
    LDR   R1, [R0], #-4

    @ Mode 8: [Rn], +/-Rm
    LDR   R0, =word_A
    LDR   R1, [R0], R2
    LDR   R0, =word_A
    LDR   R1, [R0], -R2

    @ Mode 9: [Rn], +/-Rm, shift
    LDR   R0, =word_A
    LDR   R1, [R0], R3, LSL #2
    LDR   R0, =word_A
    LDR   R1, [R0], R3, LSR #1
    LDR   R0, =word_A
    LDR   R1, [R0], R3, ASR #1

@ ==============================================================================
@ §13  LDRB  -  all 9 addressing modes
@ ==============================================================================
sec_LDRB:
    LDR   R0, =byte_data
    MOV   R2, #2
    MOV   R3, #1

    @ Modes 1-3: offset only (base unchanged)
    LDRB  R1, [R0]
    LDRB  R1, [R0, #1]
    LDRB  R1, [R0, #-1]
    LDRB  R1, [R0, R2]
    LDRB  R1, [R0, -R2]
    LDRB  R1, [R0, R3, LSL #1]
    LDRB  R1, [R0, R3, LSR #1]
    LDRB  R1, [R0, R3, ASR #1]
    LDRB  R1, [R0, R3, ROR #1]
    LDRB  R1, [R0, R3, RRX]

    @ Modes 4-6: pre-indexed
    LDR   R0, =byte_data
    LDRB  R1, [R0, #1]!
    LDR   R0, =byte_data
    LDRB  R1, [R0, -R2]!
    LDR   R0, =byte_data
    LDRB  R1, [R0, R3, LSL #1]!

    @ Modes 7-9: post-indexed
    LDR   R0, =byte_data
    LDRB  R1, [R0], #1
    LDR   R0, =byte_data
    LDRB  R1, [R0], #-1
    LDR   R0, =byte_data
    LDRB  R1, [R0], R2
    LDR   R0, =byte_data
    LDRB  R1, [R0], -R2
    LDR   R0, =byte_data
    LDRB  R1, [R0], R3, LSL #1
    LDR   R0, =byte_data
    LDRB  R1, [R0], R3, LSR #1
    LDR   R0, =byte_data
    LDRB  R1, [R0], R3, ASR #1

@ ==============================================================================
@ §14  LDRH / STRH  -  all 6 miscellaneous addressing modes
@ ==============================================================================
sec_LDRH_STRH:

    @ ---- LDRH ---- (zero-extends halfword to 32 bits)
    LDR   R0, =hword_data
    MOV   R2, #2

    @ Misc mode 1: [Rn, #+/-imm8]  (base unchanged)
    LDRH  R1, [R0]
    LDRH  R1, [R0, #2]
    LDRH  R1, [R0, #-2]

    @ Misc mode 2: [Rn, +/-Rm]  (base unchanged)
    LDRH  R1, [R0, R2]
    LDRH  R1, [R0, -R2]

    @ Misc mode 3: [Rn, #+/-imm8]!  (pre-indexed)
    LDR   R0, =hword_data
    LDRH  R1, [R0, #2]!
    LDR   R0, =hword_data
    LDRH  R1, [R0, #-2]!

    @ Misc mode 4: [Rn, +/-Rm]!
    LDR   R0, =hword_data
    LDRH  R1, [R0, R2]!
    LDR   R0, =hword_data
    LDRH  R1, [R0, -R2]!

    @ Misc mode 5: [Rn], #+/-imm8  (post-indexed)
    LDR   R0, =hword_data
    LDRH  R1, [R0], #2
    LDR   R0, =hword_data
    LDRH  R1, [R0], #-2

    @ Misc mode 6: [Rn], +/-Rm
    LDR   R0, =hword_data
    LDRH  R1, [R0], R2
    LDR   R0, =hword_data
    LDRH  R1, [R0], -R2

    @ ---- STRH ---- (stores least-significant halfword)
    LDR   R0, =result_area
    LDR   R1, =0x1234

    @ Misc mode 1
    STRH  R1, [R0]
    STRH  R1, [R0, #2]
    STRH  R1, [R0, #-2]

    @ Misc mode 2
    STRH  R1, [R0, R2]
    STRH  R1, [R0, -R2]

    @ Misc mode 3
    LDR   R0, =result_area
    STRH  R1, [R0, #2]!
    LDR   R0, =result_area
    STRH  R1, [R0, #-2]!

    @ Misc mode 4
    LDR   R0, =result_area
    STRH  R1, [R0, R2]!
    LDR   R0, =result_area
    STRH  R1, [R0, -R2]!

    @ Misc mode 5
    LDR   R0, =result_area
    STRH  R1, [R0], #2
    LDR   R0, =result_area
    STRH  R1, [R0], #-2

    @ Misc mode 6
    LDR   R0, =result_area
    STRH  R1, [R0], R2
    LDR   R0, =result_area
    STRH  R1, [R0], -R2

@ ==============================================================================
@ §15  LDRSB  -  all 6 miscellaneous addressing modes
@ ==============================================================================
sec_LDRSB:

    LDR   R0, =byte_data
    MOV   R2, #1

    @ Misc modes 1-2 (base unchanged)
    LDRSB R1, [R0]
    LDRSB R1, [R0, #1]
    LDRSB R1, [R0, #-1]
    LDRSB R1, [R0, R2]
    LDRSB R1, [R0, -R2]

    @ Misc modes 3-4 (pre-indexed)
    LDR   R0, =byte_data
    LDRSB R1, [R0, #1]!
    LDR   R0, =byte_data
    LDRSB R1, [R0, #-1]!
    LDR   R0, =byte_data
    LDRSB R1, [R0, R2]!
    LDR   R0, =byte_data
    LDRSB R1, [R0, -R2]!

    @ Misc modes 5-6 (post-indexed)
    LDR   R0, =byte_data
    LDRSB R1, [R0], #1
    LDR   R0, =byte_data
    LDRSB R1, [R0], #-1
    LDR   R0, =byte_data
    LDRSB R1, [R0], R2
    LDR   R0, =byte_data
    LDRSB R1, [R0], -R2

@ ==============================================================================
@ §16  LDRSH  -  all 6 miscellaneous addressing modes
@ ==============================================================================
sec_LDRSH:

    LDR   R0, =hword_data
    MOV   R2, #2

    @ Misc modes 1-2 (base unchanged)
    LDRSH R1, [R0]
    LDRSH R1, [R0, #2]
    LDRSH R1, [R0, #-2]
    LDRSH R1, [R0, R2]
    LDRSH R1, [R0, -R2]

    @ Misc modes 3-4 (pre-indexed)
    LDR   R0, =hword_data
    LDRSH R1, [R0, #2]!
    LDR   R0, =hword_data
    LDRSH R1, [R0, #-2]!
    LDR   R0, =hword_data
    LDRSH R1, [R0, R2]!
    LDR   R0, =hword_data
    LDRSH R1, [R0, -R2]!

    @ Misc modes 5-6 (post-indexed)
    LDR   R0, =hword_data
    LDRSH R1, [R0], #2
    LDR   R0, =hword_data
    LDRSH R1, [R0], #-2
    LDR   R0, =hword_data
    LDRSH R1, [R0], R2
    LDR   R0, =hword_data
    LDRSH R1, [R0], -R2

@ ==============================================================================
@ §17  STR  -  all 9 addressing modes
@ ==============================================================================
sec_STR:
    LDR   R1, =0xCAFEBABE
    LDR   R0, =result_area
    MOV   R2, #4
    MOV   R3, #1

    @ Modes 1-3: offset only
    STR   R1, [R0, #0]
    STR   R1, [R0, #4]
    STR   R1, [R0, #-4]
    STR   R1, [R0, R2]
    STR   R1, [R0, -R2]
    STR   R1, [R0, R3, LSL #2]
    STR   R1, [R0, R3, LSR #1]
    STR   R1, [R0, R3, ASR #1]
    STR   R1, [R0, R3, ROR #1]
    STR   R1, [R0, R3, RRX]

    @ Modes 4-6: pre-indexed
    LDR   R0, =result_area
    STR   R1, [R0, #4]!
    LDR   R0, =result_area
    STR   R1, [R0, R2]!
    LDR   R0, =result_area
    STR   R1, [R0, R3, LSL #2]!

    @ Modes 7-9: post-indexed
    LDR   R0, =result_area
    STR   R1, [R0], #4
    LDR   R0, =result_area
    STR   R1, [R0], -R2
    LDR   R0, =result_area
    STR   R1, [R0], R3, LSL #2
    LDR   R0, =result_area
    STR   R1, [R0], R3, LSR #1
    LDR   R0, =result_area
    STR   R1, [R0], R3, ASR #1

@ ==============================================================================
@ §18  STRB  -  all 9 addressing modes
@ ==============================================================================
sec_STRB:
    LDR   R0, =result_area
    MOV   R1, #0xAB
    MOV   R2, #2
    MOV   R3, #1

    @ Modes 1-3: offset only
    STRB  R1, [R0]
    STRB  R1, [R0, #1]
    STRB  R1, [R0, #-1]
    STRB  R1, [R0, R2]
    STRB  R1, [R0, -R2]
    STRB  R1, [R0, R3, LSL #1]
    STRB  R1, [R0, R3, LSR #1]
    STRB  R1, [R0, R3, ASR #1]
    STRB  R1, [R0, R3, ROR #1]
    STRB  R1, [R0, R3, RRX]

    @ Modes 4-6: pre-indexed
    LDR   R0, =result_area
    STRB  R1, [R0, #1]!
    LDR   R0, =result_area
    STRB  R1, [R0, R2]!
    LDR   R0, =result_area
    STRB  R1, [R0, R3, LSL #1]!

    @ Modes 7-9: post-indexed
    LDR   R0, =result_area
    STRB  R1, [R0], #1
    LDR   R0, =result_area
    STRB  R1, [R0], -R2
    LDR   R0, =result_area
    STRB  R1, [R0], R3, LSL #1
    LDR   R0, =result_area
    STRB  R1, [R0], R3, LSR #1
    LDR   R0, =result_area
    STRB  R1, [R0], R3, ASR #1
    B     sec_LDM                @ skip literal pool below
    .ltorg                       @ *** LITERAL POOL 3 (after §18)

@ ==============================================================================
@ §19  LDM  -  all four addressing modes + four stack name aliases
@ ==============================================================================
sec_LDM:

    LDR   R8, =array4

    @ LDMIA: Increment After (post-increment)
    LDMIA R8, {R0-R3}           @ R8 unchanged
    LDR   R8, =array4
    LDMIA R8!, {R0-R3}          @ R8 += 16

    @ LDMIB: Increment Before (pre-increment)
    LDR   R8, =array4
    LDMIB R8, {R0-R3}
    LDR   R8, =array4
    LDMIB R8!, {R0-R3}

    @ LDMDA: Decrement After (post-decrement; start at last element)
    LDR   R8, =array4
    ADD   R8, R8, #12
    LDMDA R8, {R0-R3}
    LDR   R8, =array4
    ADD   R8, R8, #12
    LDMDA R8!, {R0-R3}

    @ LDMDB: Decrement Before (pre-decrement; start one past last)
    LDR   R8, =array4
    ADD   R8, R8, #16
    LDMDB R8, {R0-R3}
    LDR   R8, =array4
    ADD   R8, R8, #16
    LDMDB R8!, {R0-R3}

    @ Stack aliases for LDM (pop)  -  prime result_area with known values first
    LDR   R9, =result_area
    MOV   R0, #0x10
    MOV   R1, #0x20
    MOV   R2, #0x30
    MOV   R3, #0x40
    STMIA R9, {R0-R3}

    LDR   R9, =result_area
    LDMFD R9!, {R0-R3}          @ Full  Descending pop  = LDMIA

    LDR   R9, =result_area
    ADD   R9, R9, #16
    LDMFA R9!, {R0-R3}          @ Full  Ascending  pop  = LDMDA

    LDR   R9, =result_area
    LDMED R9!, {R0-R3}          @ Empty Descending  pop = LDMIB

    LDR   R9, =result_area
    ADD   R9, R9, #16
    LDMEA R9!, {R0-R3}          @ Empty Ascending   pop = LDMDB

@ ==============================================================================
@ §20  STM  -  all four addressing modes + four stack name aliases
@ ==============================================================================
sec_STM:
    MOV   R0, #0xAA
    MOV   R1, #0xBB
    MOV   R2, #0xCC
    MOV   R3, #0xDD

    @ STMIA: Increment After (post-increment)
    LDR   R9, =result_area
    STMIA R9, {R0-R3}           @ R9 unchanged
    LDR   R9, =result_area
    STMIA R9!, {R0-R3}          @ R9 += 16

    @ STMIB: Increment Before (pre-increment)
    LDR   R9, =result_area
    STMIB R9, {R0-R3}
    LDR   R9, =result_area
    STMIB R9!, {R0-R3}

    @ STMDA: Decrement After (post-decrement)
    LDR   R9, =result_area
    ADD   R9, R9, #12
    STMDA R9, {R0-R3}
    LDR   R9, =result_area
    ADD   R9, R9, #12
    STMDA R9!, {R0-R3}

    @ STMDB: Decrement Before (pre-decrement)
    LDR   R9, =result_area
    ADD   R9, R9, #16
    STMDB R9, {R0-R3}
    LDR   R9, =result_area
    ADD   R9, R9, #16
    STMDB R9!, {R0-R3}

    @ Stack aliases for STM (push)
    LDR   R9, =result_area
    ADD   R9, R9, #64           @ ensure room above

    STMFD R9!, {R0-R3}          @ Full  Descending push = STMDB
    STMFA R9!, {R0-R3}          @ Full  Ascending  push = STMIB
    STMED R9!, {R0-R3}          @ Empty Descending  push = STMIA
    STMEA R9!, {R0-R3}          @ Empty Ascending   push = STMDA

@ ==============================================================================
@ §21  PUSH / POP  (Full Descending stack pseudo-instructions)
@ ==============================================================================
sec_PUSH_POP:

    @ PUSH = STMDB R13!  /  POP = LDMIA R13!
    MOV   R4, #0x10
    MOV   R5, #0x20
    MOV   R6, #0x30
    MOV   R7, #0x40
    PUSH  {R4-R7}
    MOV   R4, #0
    MOV   R5, #0
    MOV   R6, #0
    MOV   R7, #0
    POP   {R4-R7}               @ R4-R7 should be restored to 0x10/20/30/40

    @ PUSH/POP with return via PC in register list
    BL    sub_push_pop_ret
    B     after_push_pop

sub_push_pop_ret:
    PUSH  {R4-R7, LR}           @ save work regs + return address
    MOV   R4, #0xAA
    MOV   R5, #0xBB
    MOV   R6, #0xCC
    MOV   R7, #0xDD
    POP   {R4-R7, PC}           @ restore and return

after_push_pop:
    NOP
    B     sec_MRS_MSR            @ skip literal pool below
    .ltorg                       @ *** LITERAL POOL 4 (after §21)

@ ==============================================================================
@ §22  MRS / MSR
@ ==============================================================================
sec_MRS_MSR:

    @ MRS: read CPSR into general-purpose register
    MRS   R0, CPSR

    @ MSR via register: write flags field only
    ORR   R1, R0, #0xF0000000   @ set N, Z, C, V
    MSR   CPSR_f, R1
    BIC   R1, R0, #0xF0000000   @ clear N, Z, C, V
    MSR   CPSR_f, R1
    MSR   CPSR_f, R0             @ restore original flags

    @ MSR via immediate: individual flag bits
    MSR   CPSR_f, #0xF0000000   @ set N, Z, C, V
    MSR   CPSR_f, #0x80000000   @ N only
    MSR   CPSR_f, #0x40000000   @ Z only
    MSR   CPSR_f, #0x20000000   @ C only
    MSR   CPSR_f, #0x10000000   @ V only
    MSR   CPSR_f, #0x00000000   @ clear all

    @ Round-trip read/modify/write
    MRS   R1, CPSR
    ORR   R2, R1, #0x60000000   @ set Z and C
    MSR   CPSR_f, R2
    MRS   R3, CPSR              @ verify
    MSR   CPSR_f, R1             @ restore

@ ==============================================================================
@ §23  SWP / SWPB
@ ==============================================================================
sec_SWP_SWPB:

    @ SWP word: R3 <- mem[R1], mem[R1] <- R2  (atomic exchange)
    LDR   R1, =result_area
    LDR   R0, =0xAABBCCDD
    STR   R0, [R1]              @ seed memory
    LDR   R2, =0x11223344
    SWP   R3, R2, [R1]          @ expected: R3=0xAABBCCDD, mem=0x11223344

    @ SWP same-register idiom (test-and-set semaphore)
    LDR   R1, =result_area
    MOV   R0, #0x00
    STR   R0, [R1]
    MOV   R0, #0x01
    SWP   R0, R0, [R1]          @ R0 <- old value (0), mem <- 1

    @ SWPB byte: R3 <- byte[R1], byte[R1] <- R2[7:0]
    LDR   R1, =result_area
    MOV   R0, #0xFF
    STRB  R0, [R1]
    MOV   R2, #0xAA
    SWPB  R3, R2, [R1]          @ expected: R3=0xFF, mem=0xAA

    @ SWPB atomic byte semaphore
    LDR   R1, =result_area
    ADD   R1, R1, #4
    MOV   R0, #0
    STRB  R0, [R1]              @ semaphore = 0 (free)
    MOV   R0, #1
    SWPB  R0, R0, [R1]          @ R0 <- old semaphore; write 1

@ ==============================================================================
@ §24  SWI
@ NOTE: FPGA SWI vector at 0x00000008 must restore PC via MOVS PC, LR.
@ The 24-bit immediate is ignored by the processor but readable by the handler
@ via LR_svc - 4 (bits [23:0]).
@ ==============================================================================
sec_SWI:
    SWI   #0
    SWI   #1
    SWI   #0xFF
    SWI   #0x1000
    SWI   #0x00FFFFFF           @ maximum 24-bit immediate

@ ==============================================================================
@ §25  PSEUDO-INSTRUCTIONS
@ ==============================================================================
sec_PSEUDO:

    @ ADR: single ADD/SUB relative to PC (position-independent)
    @ ADR   R0, word_A
    @ ADR   R1, byte_data
    @ ADR   R2, array4

    @ ADRL replacement: GAS has no ADRL; use LDR= (literal pool load)
    LDR   R0, =result_area      @ was: ADRL R0, result_area
    LDR   R1, =word_B           @ was: ADRL R1, word_B

    @ LDR =expr: 32-bit constant literal pool loads
    LDR   R0, =0x00000000
    LDR   R0, =0x00000001
    LDR   R0, =0x000000FF
    LDR   R0, =0x0000FF00
    LDR   R0, =0x00FF0000
    LDR   R0, =0xFF000000
    LDR   R0, =0x12345678
    LDR   R0, =0xDEADBEEF
    LDR   R0, =0xFFFFFFFF
    LDR   R0, =0x80000000
    LDR   R0, =word_A           @ address of data label
    LDR   R0, =result_area

    @ ASR pseudo: MOV Rd, Rm, ASR ... 
    LDR   R0, =0x80000000
    MOV   R2, #3
    ASR   R1, R0, #1            @ immediate shift
    ASR   R1, R0, #8
    ASR   R1, R0, #31
    ASR   R1, R0, R2            @ register shift
    ASR   R1, R1, #4            @ Rd=Rm form

    @ LSL pseudo
    MOV   R0, #1
    MOV   R2, #4
    LSL   R1, R0, #0
    LSL   R1, R0, #1
    LSL   R1, R0, #31
    LSL   R1, R0, R2
    LSL   R1, R1, #2            @ Rd=Rm form

    @ LSR pseudo
    LDR   R0, =0xFFFFFFFF
    MOV   R2, #8
    LSR   R1, R0, #1
    LSR   R1, R0, #8
    LSR   R1, R0, #32           @ result = 0
    LSR   R1, R0, R2
    LSR   R1, R1, #1            @ Rd=Rm form

    @ ROR pseudo
    LDR   R0, =0xABCD1234
    MOV   R2, #8
    ROR   R1, R0, #1
    ROR   R1, R0, #8
    ROR   R1, R0, #16
    ROR   R1, R0, R2
    ROR   R1, R1, #4            @ Rd=Rm form

    @ RRX pseudo: rotate right 1 bit through carry flag
    LDR   R0, =0x80000001
    RRX   R1, R0
    RRX   R0, R0                @ Rd=Rm form

    @ NOP
    NOP
    NOP
    NOP
    B     sec_SHIFTER_MATRIX     @ skip literal pool below
    .ltorg                       @ *** LITERAL POOL 5 (after §25)

@ ==============================================================================
@ §26  EXHAUSTIVE SHIFTER-FORM COVERAGE
@      Every data-processing opcode x all 11 shifter operand forms
@ ==============================================================================
sec_SHIFTER_MATRIX:

    LDR   R0, =0x0F0F0F0F
    LDR   R1, =0xAAAAAAAA
    MOV   R2, #4

@ ---- Form 1: immediate -------------------------------------------------------
    ADD   R3, R0, #0x0F
    ADC   R3, R0, #0x0F
    SUB   R3, R0, #0x0F
    SBC   R3, R0, #0x0F
    RSB   R3, R0, #0x0F
    RSC   R3, R0, #0x0F
    AND   R3, R0, #0x0F
    ORR   R3, R0, #0x0F
    EOR   R3, R0, #0x0F
    BIC   R3, R0, #0x0F
    MOV   R3, #0x0F
    MVN   R3, #0x0F
    CMP   R0, #0x0F
    CMN   R0, #0x0F
    TST   R0, #0x0F
    TEQ   R0, #0x0F

@ ---- Form 2: register --------------------------------------------------------
    ADD   R3, R0, R1
    ADC   R3, R0, R1
    SUB   R3, R0, R1
    SBC   R3, R0, R1
    RSB   R3, R0, R1
    RSC   R3, R0, R1
    AND   R3, R0, R1
    ORR   R3, R0, R1
    EOR   R3, R0, R1
    BIC   R3, R0, R1
    MOV   R3, R1
    MVN   R3, R1
    CMP   R0, R1
    CMN   R0, R1
    TST   R0, R1
    TEQ   R0, R1

@ ---- Form 3: Rm, LSL #imm ----------------------------------------------------
    ADD   R3, R0, R1, LSL #4
    ADC   R3, R0, R1, LSL #4
    SUB   R3, R0, R1, LSL #4
    SBC   R3, R0, R1, LSL #4
    RSB   R3, R0, R1, LSL #4
    RSC   R3, R0, R1, LSL #4
    AND   R3, R0, R1, LSL #4
    ORR   R3, R0, R1, LSL #4
    EOR   R3, R0, R1, LSL #4
    BIC   R3, R0, R1, LSL #4
    MOV   R3, R1, LSL #4
    MVN   R3, R1, LSL #4
    CMP   R0, R1, LSL #4
    CMN   R0, R1, LSL #4
    TST   R0, R1, LSL #4
    TEQ   R0, R1, LSL #4

@ ---- Form 4: Rm, LSL Rs ------------------------------------------------------
    ADD   R3, R0, R1, LSL R2
    ADC   R3, R0, R1, LSL R2
    SUB   R3, R0, R1, LSL R2
    SBC   R3, R0, R1, LSL R2
    RSB   R3, R0, R1, LSL R2
    RSC   R3, R0, R1, LSL R2
    AND   R3, R0, R1, LSL R2
    ORR   R3, R0, R1, LSL R2
    EOR   R3, R0, R1, LSL R2
    BIC   R3, R0, R1, LSL R2
    MOV   R3, R1, LSL R2
    MVN   R3, R1, LSL R2
    CMP   R0, R1, LSL R2
    CMN   R0, R1, LSL R2
    TST   R0, R1, LSL R2
    TEQ   R0, R1, LSL R2

@ ---- Form 5: Rm, LSR #imm ----------------------------------------------------
    ADD   R3, R0, R1, LSR #4
    ADC   R3, R0, R1, LSR #4
    SUB   R3, R0, R1, LSR #4
    SBC   R3, R0, R1, LSR #4
    RSB   R3, R0, R1, LSR #4
    RSC   R3, R0, R1, LSR #4
    AND   R3, R0, R1, LSR #4
    ORR   R3, R0, R1, LSR #4
    EOR   R3, R0, R1, LSR #4
    BIC   R3, R0, R1, LSR #4
    MOV   R3, R1, LSR #4
    MVN   R3, R1, LSR #4
    CMP   R0, R1, LSR #4
    CMN   R0, R1, LSR #4
    TST   R0, R1, LSR #4
    TEQ   R0, R1, LSR #4

@ ---- Form 6: Rm, LSR Rs ------------------------------------------------------
    ADD   R3, R0, R1, LSR R2
    ADC   R3, R0, R1, LSR R2
    SUB   R3, R0, R1, LSR R2
    SBC   R3, R0, R1, LSR R2
    RSB   R3, R0, R1, LSR R2
    RSC   R3, R0, R1, LSR R2
    AND   R3, R0, R1, LSR R2
    ORR   R3, R0, R1, LSR R2
    EOR   R3, R0, R1, LSR R2
    BIC   R3, R0, R1, LSR R2
    MOV   R3, R1, LSR R2
    MVN   R3, R1, LSR R2
    CMP   R0, R1, LSR R2
    CMN   R0, R1, LSR R2
    TST   R0, R1, LSR R2
    TEQ   R0, R1, LSR R2

@ ---- Form 7: Rm, ASR #imm ----------------------------------------------------
    ADD   R3, R0, R1, ASR #4
    ADC   R3, R0, R1, ASR #4
    SUB   R3, R0, R1, ASR #4
    SBC   R3, R0, R1, ASR #4
    RSB   R3, R0, R1, ASR #4
    RSC   R3, R0, R1, ASR #4
    AND   R3, R0, R1, ASR #4
    ORR   R3, R0, R1, ASR #4
    EOR   R3, R0, R1, ASR #4
    BIC   R3, R0, R1, ASR #4
    MOV   R3, R1, ASR #4
    MVN   R3, R1, ASR #4
    CMP   R0, R1, ASR #4
    CMN   R0, R1, ASR #4
    TST   R0, R1, ASR #4
    TEQ   R0, R1, ASR #4

@ ---- Form 8: Rm, ASR Rs ------------------------------------------------------
    ADD   R3, R0, R1, ASR R2
    ADC   R3, R0, R1, ASR R2
    SUB   R3, R0, R1, ASR R2
    SBC   R3, R0, R1, ASR R2
    RSB   R3, R0, R1, ASR R2
    RSC   R3, R0, R1, ASR R2
    AND   R3, R0, R1, ASR R2
    ORR   R3, R0, R1, ASR R2
    EOR   R3, R0, R1, ASR R2
    BIC   R3, R0, R1, ASR R2
    MOV   R3, R1, ASR R2
    MVN   R3, R1, ASR R2
    CMP   R0, R1, ASR R2
    CMN   R0, R1, ASR R2
    TST   R0, R1, ASR R2
    TEQ   R0, R1, ASR R2

@ ---- Form 9: Rm, ROR #imm ----------------------------------------------------
    ADD   R3, R0, R1, ROR #8
    ADC   R3, R0, R1, ROR #8
    SUB   R3, R0, R1, ROR #8
    SBC   R3, R0, R1, ROR #8
    RSB   R3, R0, R1, ROR #8
    RSC   R3, R0, R1, ROR #8
    AND   R3, R0, R1, ROR #8
    ORR   R3, R0, R1, ROR #8
    EOR   R3, R0, R1, ROR #8
    BIC   R3, R0, R1, ROR #8
    MOV   R3, R1, ROR #8
    MVN   R3, R1, ROR #8
    CMP   R0, R1, ROR #8
    CMN   R0, R1, ROR #8
    TST   R0, R1, ROR #8
    TEQ   R0, R1, ROR #8

@ ---- Form 10: Rm, ROR Rs -----------------------------------------------------
    ADD   R3, R0, R1, ROR R2
    ADC   R3, R0, R1, ROR R2
    SUB   R3, R0, R1, ROR R2
    SBC   R3, R0, R1, ROR R2
    RSB   R3, R0, R1, ROR R2
    RSC   R3, R0, R1, ROR R2
    AND   R3, R0, R1, ROR R2
    ORR   R3, R0, R1, ROR R2
    EOR   R3, R0, R1, ROR R2
    BIC   R3, R0, R1, ROR R2
    MOV   R3, R1, ROR R2
    MVN   R3, R1, ROR R2
    CMP   R0, R1, ROR R2
    CMN   R0, R1, ROR R2
    TST   R0, R1, ROR R2
    TEQ   R0, R1, ROR R2

@ ---- Form 11: Rm, RRX --------------------------------------------------------
    ADD   R3, R0, R1, RRX
    ADC   R3, R0, R1, RRX
    SUB   R3, R0, R1, RRX
    SBC   R3, R0, R1, RRX
    RSB   R3, R0, R1, RRX
    RSC   R3, R0, R1, RRX
    AND   R3, R0, R1, RRX
    ORR   R3, R0, R1, RRX
    EOR   R3, R0, R1, RRX
    BIC   R3, R0, R1, RRX
    MOV   R3, R1, RRX
    MVN   R3, R1, RRX
    CMP   R0, R1, RRX
    CMN   R0, R1, RRX
    TST   R0, R1, RRX
    TEQ   R0, R1, RRX

@ ==============================================================================
@ HALT  -  spin here forever (test complete)
@ ==============================================================================
test_done:
    B     test_done

    .ltorg                       @ *** FINAL LITERAL POOL (§26 + LDR= constants)

@ end of file - no END directive needed in GAS