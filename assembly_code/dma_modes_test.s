@ ==============================================================================
@ dma_modes_test.s - DMA control-mode diagnostic for gba_rev0
@
@ This is a standalone hardware test. It covers DMA control modes, local-memory
@ transfers, and SDRAM-backed EWRAM/PAK_ROM transfers.
@
@ Manual timing phases:
@   * Phase 8: pulse the VBlank input after R0 shows 0x80.
@   * Phase 9: pulse the HBlank input after R0 shows 0x90.
@   * Phase A: pulse VBlank after R0 shows 0xA0. Current RTL maps Special to
@              VBlank; channel-specific sound/video special requests are absent.
@   * Phase B: pulse VBlank after R0 shows 0xB0, release it, then pulse it
@              again after R0 shows 0xB8.
@
@ Failure reporting:
@   R7  = phase
@   R0  = 0xPC: P = phase, C = check within phase
@   R8  = observed value
@   R9  = expected value
@   R10 = checked address
@
@ DMA IRQ is covered by dma_irq_memory_test.s. DMA3 Game Pak DRQ has no request
@ input in the current RTL and is not tested here.
@ ==============================================================================

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

    .macro IWRAM_PTR reg, offset
        MOV     \reg, #0x03000000
        ADD     \reg, \reg, #\offset
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

@ Wait for a manual timing event. The wait status is 0xP0 (or 0xP8 for the
@ second repeat event), where P is the current R7 phase.
    .macro WAIT_WORD addr_reg, b3, b2, b1, b0, wait_code
.Lwait\@:
        LDR     R2, [\addr_reg]
        LOADW   R1, \b3, \b2, \b1, \b0
        CMP     R2, R1
        BEQ     .Lwait_done\@
        MOV     R0, R7, LSL #4
        ORR     R0, R0, #\wait_code
        B       .Lwait\@
.Lwait_done\@:
    .endm

@ Program one DMA channel and start it. cnt_hi is split into bytes because an
@ ARMv4T data-processing immediate cannot encode every DMA control word.
    .macro DMA_START dma_offset, src_offset, src_delta, dst_offset, dst_delta, count, cnt_hi_b3, cnt_hi_b2
        MOV     R4, #0x04000000
        ORR     R4, R4, #\dma_offset

        IWRAM_PTR R5, \src_offset
        ADD     R5, R5, #\src_delta
        STR     R5, [R4]          @ DMAxSAD

        IWRAM_PTR R5, \dst_offset
        ADD     R5, R5, #\dst_delta
        STR     R5, [R4, #4]      @ DMAxDAD

        LOADW   R1, \cnt_hi_b3, \cnt_hi_b2, 0x00, \count
        STR     R1, [R4, #8]      @ DMAxCNT, starts the transfer
    .endm

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
    B       trap
    B       trap

trap:
    MOV     R7, #0x0F
    MOV     R0, #0xEE
    B       trap

reset_handler:
    MSR     CPSR, #0xDF          @ System mode, IRQ/FIQ masked.
    MOV     R0, #0
    MOV     R7, #0
    MOV     R8, #0
    MOV     R9, #0
    MOV     R10, #0

@ ==============================================================================
@ PHASE 1 - DMA0: immediate, 16-bit, source/destination increment
@ ==============================================================================
phase_16_inc:
    MOV     R7, #1
    IWRAM_PTR R4, 0x400
    LOADW   R1, 0xA0, 0x02, 0xA0, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xA0, 0x04, 0xA0, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x420
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xB0, 0x400, 0, 0x420, 0, 4, 0x80, 0x00

    IWRAM_PTR R5, 0x420
    LDR     R2, [R5]
    LOADW   R1, 0xA0, 0x02, 0xA0, 0x01
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xA0, 0x04, 0xA0, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 2 - DMA1: immediate, 16-bit, source/destination decrement
@ ==============================================================================
phase_16_dec:
    MOV     R7, #2
    IWRAM_PTR R4, 0x440
    LOADW   R1, 0xB0, 0x02, 0xB0, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xB0, 0x04, 0xB0, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x460
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xBC, 0x440, 6, 0x460, 6, 4, 0x80, 0xA0

    IWRAM_PTR R5, 0x460
    LDR     R2, [R5]
    LOADW   R1, 0xB0, 0x02, 0xB0, 0x01
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xB0, 0x04, 0xB0, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 3 - DMA2: immediate, 16-bit, fixed source / incrementing destination
@ ==============================================================================
phase_src_fixed:
    MOV     R7, #3
    IWRAM_PTR R4, 0x480
    LOADW   R1, 0x00, 0x00, 0xC0, 0xA5
    STR     R1, [R4]
    IWRAM_PTR R4, 0x4A0
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xC8, 0x480, 0, 0x4A0, 0, 4, 0x81, 0x00

    IWRAM_PTR R5, 0x4A0
    LDR     R2, [R5]
    LOADW   R1, 0xC0, 0xA5, 0xC0, 0xA5
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xC0, 0xA5, 0xC0, 0xA5
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 4 - DMA3: immediate, 16-bit, incrementing source / fixed destination
@ ==============================================================================
phase_dst_fixed:
    MOV     R7, #4
    IWRAM_PTR R4, 0x4C0
    LOADW   R1, 0xD0, 0x02, 0xD0, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xD0, 0x04, 0xD0, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x4E0
    MOV     R1, #0
    STR     R1, [R4]

    DMA_START 0xD4, 0x4C0, 0, 0x4E0, 0, 4, 0x80, 0x40

    IWRAM_PTR R5, 0x4E0
    LDR     R2, [R5]
    LOADW   R1, 0x00, 0x00, 0xD0, 0x04
    CHECK_EQ 0x01, R5

@ ==============================================================================
@ PHASE 5 - DMA0: immediate, 32-bit transfer
@ ==============================================================================
phase_32_inc:
    MOV     R7, #5
    IWRAM_PTR R4, 0x500
    LOADW   R1, 0xE1, 0xE2, 0xE3, 0xE4
    STR     R1, [R4]
    LOADW   R1, 0xE5, 0xE6, 0xE7, 0xE8
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x520
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xB0, 0x500, 0, 0x520, 0, 2, 0x84, 0x00

    IWRAM_PTR R5, 0x520
    LDR     R2, [R5]
    LOADW   R1, 0xE1, 0xE2, 0xE3, 0xE4
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xE5, 0xE6, 0xE7, 0xE8
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 6 - DMA1: source increment/reload encoding (one-shot = increment)
@ ==============================================================================
phase_src_reload:
    MOV     R7, #6
    IWRAM_PTR R4, 0x540
    LOADW   R1, 0xF0, 0x02, 0xF0, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xF0, 0x04, 0xF0, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x560
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xBC, 0x540, 0, 0x560, 0, 4, 0x81, 0x80

    IWRAM_PTR R5, 0x560
    LDR     R2, [R5]
    LOADW   R1, 0xF0, 0x02, 0xF0, 0x01
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xF0, 0x04, 0xF0, 0x03
    CHECK_EQ 0x02, R5
    B       cross_memory_local

@ ==============================================================================
@ PHASE 7 - DMA2: destination increment/reload encoding
@ The first transfer must increment the destination exactly like normal mode.
@ ==============================================================================
phase_dst_reload:
    MOV     R7, #7
    IWRAM_PTR R4, 0x580
    LOADW   R1, 0xA7, 0x02, 0xA7, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xA7, 0x04, 0xA7, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x5A0
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xC8, 0x580, 0, 0x5A0, 0, 4, 0x80, 0x60

    IWRAM_PTR R5, 0x5A0
    LDR     R2, [R5]
    LOADW   R1, 0xA7, 0x02, 0xA7, 0x01
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xA7, 0x04, 0xA7, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 8 - DMA1: VBlank start timing, one-shot
@ ==============================================================================
phase_vblank:
    MOV     R7, #8
    IWRAM_PTR R4, 0x5C0
    LOADW   R1, 0x8A, 0x02, 0x8A, 0x01
    STR     R1, [R4]
    LOADW   R1, 0x8A, 0x04, 0x8A, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x5E0
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xBC, 0x5C0, 0, 0x5E0, 0, 4, 0x90, 0x00

    IWRAM_PTR R5, 0x5E0
    WAIT_WORD R5, 0x8A, 0x02, 0x8A, 0x01, 0x00
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0x8A, 0x04, 0x8A, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE 9 - DMA2: HBlank start timing, one-shot
@ ==============================================================================
phase_hblank:
    MOV     R7, #9
    IWRAM_PTR R4, 0x600
    LOADW   R1, 0x9A, 0x02, 0x9A, 0x01
    STR     R1, [R4]
    LOADW   R1, 0x9A, 0x04, 0x9A, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x620
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xC8, 0x600, 0, 0x620, 0, 4, 0xA0, 0x00

    IWRAM_PTR R5, 0x620
    WAIT_WORD R5, 0x9A, 0x02, 0x9A, 0x01, 0x00
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0x9A, 0x04, 0x9A, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE A - DMA3: Special start timing (currently VBlank-gated in RTL)
@ ==============================================================================
phase_special:
    MOV     R7, #0x0A
    IWRAM_PTR R4, 0x640
    LOADW   R1, 0xAA, 0x02, 0xAA, 0x01
    STR     R1, [R4]
    LOADW   R1, 0xAA, 0x04, 0xAA, 0x03
    STR     R1, [R4, #4]
    IWRAM_PTR R4, 0x660
    MOV     R1, #0
    STR     R1, [R4]
    STR     R1, [R4, #4]

    DMA_START 0xD4, 0x640, 0, 0x660, 0, 4, 0xB0, 0x00

    IWRAM_PTR R5, 0x660
    WAIT_WORD R5, 0xAA, 0x02, 0xAA, 0x01, 0x00
    CHECK_EQ 0x01, R5
    LDR     R2, [R5, #4]
    LOADW   R1, 0xAA, 0x04, 0xAA, 0x03
    CHECK_EQ 0x02, R5

@ ==============================================================================
@ PHASE B - DMA1: VBlank repeat plus destination increment/reload
@ Pulse VBlank twice. The source is changed after the first completed transfer;
@ the second transfer must overwrite the same reloaded destination buffer.
@ ==============================================================================
phase_repeat_reload:
    MOV     R7, #0x0B
    IWRAM_PTR R4, 0x680
    LOADH   R1, 0xB1A1
    STRH    R1, [R4]
    IWRAM_PTR R4, 0x6A0
    MOV     R1, #0
    STR     R1, [R4]

    DMA_START 0xBC, 0x680, 0, 0x6A0, 0, 2, 0x93, 0x60

    IWRAM_PTR R5, 0x6A0
    WAIT_WORD R5, 0xB1, 0xA1, 0xB1, 0xA1, 0x00
    CHECK_EQ 0x01, R5

    IWRAM_PTR R4, 0x680
    LOADH   R1, 0xB2B2
    STRH    R1, [R4]

    WAIT_WORD R5, 0xB2, 0xB2, 0xB2, 0xB2, 0x08
    CHECK_EQ 0x02, R5
    B       all_pass

@ ==============================================================================
@ PHASE C - local-memory transfers
@ IWRAM -> Palette -> VRAM -> OAM uses 16-bit DMA. OAM -> IWRAM then verifies
@ the 32-bit local-memory path. Cart RAM is excluded because DMA has no byte
@ transfer mode and cart_ram is byte-only.
@ ==============================================================================
cross_memory_local:
    MOV     R7, #0x0C

@ IWRAM -> Palette (DMA0, 16-bit)
    PTR     R5, 0x03000000, 0x700
    LOADW   R1, 0x10, 0x02, 0x10, 0x01
    STR     R1, [R5]
    LOADW   R1, 0x10, 0x04, 0x10, 0x03
    STR     R1, [R5, #4]
    PTR     R6, 0x05000000, 0x200
    MOV     R1, #0
    STRH    R1, [R6]
    STRH    R1, [R6, #2]
    STRH    R1, [R6, #4]
    STRH    R1, [R6, #6]
    DMA_START_REG 0xB0, R5, R6, 4, 0x80, 0x00

    LDRH    R2, [R6]
    LOADH   R1, 0x1001
    CHECK_EQ 0x01, R6
    LDRH    R2, [R6, #6]
    LOADH   R1, 0x1004
    CHECK_EQ 0x02, R6

@ Palette -> VRAM (DMA1, 16-bit)
    PTR     R5, 0x05000000, 0x200
    PTR     R6, 0x06000000, 0x200
    MOV     R1, #0
    STRH    R1, [R6]
    STRH    R1, [R6, #2]
    STRH    R1, [R6, #4]
    STRH    R1, [R6, #6]
    DMA_START_REG 0xBC, R5, R6, 4, 0x80, 0x00

    LDRH    R2, [R6]
    LOADH   R1, 0x1001
    CHECK_EQ 0x03, R6
    LDRH    R2, [R6, #6]
    LOADH   R1, 0x1004
    CHECK_EQ 0x04, R6

@ VRAM -> OAM (DMA2, 16-bit)
    PTR     R5, 0x06000000, 0x200
    PTR     R6, 0x07000000, 0x200
    MOV     R1, #0
    STRH    R1, [R6]
    STRH    R1, [R6, #2]
    STRH    R1, [R6, #4]
    STRH    R1, [R6, #6]
    DMA_START_REG 0xC8, R5, R6, 4, 0x80, 0x00

    LDRH    R2, [R6]
    LOADH   R1, 0x1001
    CHECK_EQ 0x05, R6
    LDRH    R2, [R6, #6]
    LOADH   R1, 0x1004
    CHECK_EQ 0x06, R6

@ OAM -> IWRAM (DMA3, 32-bit)
    PTR     R5, 0x07000000, 0x200
    PTR     R6, 0x03000000, 0x720
    MOV     R1, #0
    STR     R1, [R6]
    STR     R1, [R6, #4]
    DMA_START_REG 0xD4, R5, R6, 2, 0x84, 0x00

    LDR     R2, [R6]
    LOADW   R1, 0x10, 0x02, 0x10, 0x01
    CHECK_EQ 0x07, R6
    LDR     R2, [R6, #4]
    LOADW   R1, 0x10, 0x04, 0x10, 0x03
    CHECK_EQ 0x08, R6

@ ==============================================================================
@ PHASE D - SDRAM-backed EWRAM and PAK_ROM transfers
@ ==============================================================================
cross_memory_sdram:
    MOV     R7, #0x0D

@ EWRAM -> IWRAM (DMA0, 16-bit)
    PTR     R5, 0x02000000, 0x1000
    LOADH   R1, 0x2101
    STRH    R1, [R5]
    LOADH   R1, 0x2102
    STRH    R1, [R5, #2]
    LOADH   R1, 0x2103
    STRH    R1, [R5, #4]
    LOADH   R1, 0x2104
    STRH    R1, [R5, #6]
    PTR     R6, 0x03000000, 0x740
    MOV     R1, #0
    STR     R1, [R6]
    STR     R1, [R6, #4]
    DMA_START_REG 0xB0, R5, R6, 4, 0x80, 0x00

    LDR     R2, [R6]
    LOADW   R1, 0x21, 0x02, 0x21, 0x01
    CHECK_EQ 0x01, R6
    LDR     R2, [R6, #4]
    LOADW   R1, 0x21, 0x04, 0x21, 0x03
    CHECK_EQ 0x02, R6

@ PAK_ROM -> IWRAM (DMA1, 16-bit)
    PTR     R5, 0x08000000, 0x1000
    LOADH   R1, 0x2801
    STRH    R1, [R5]
    LOADH   R1, 0x2802
    STRH    R1, [R5, #2]
    LOADH   R1, 0x2803
    STRH    R1, [R5, #4]
    LOADH   R1, 0x2804
    STRH    R1, [R5, #6]
    PTR     R6, 0x03000000, 0x760
    MOV     R1, #0
    STR     R1, [R6]
    STR     R1, [R6, #4]
    DMA_START_REG 0xBC, R5, R6, 4, 0x80, 0x00

    LDR     R2, [R6]
    LOADW   R1, 0x28, 0x02, 0x28, 0x01
    CHECK_EQ 0x03, R6
    LDR     R2, [R6, #4]
    LOADW   R1, 0x28, 0x04, 0x28, 0x03
    CHECK_EQ 0x04, R6
    B       phase_dst_reload

all_pass:
    MOV     R7, #0x0F
    MOV     R0, #0xAD
    B       all_pass

fail:
    B       fail

    .end
