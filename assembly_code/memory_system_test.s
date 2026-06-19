@ ==============================================================================
@ memory_system_test.s - GBA memory-system diagnostic for gba_rev0
@
@ Source of expected map behavior: code/docs/CowBiteSpec/CowBiteSpec.htm, section
@ "Memory". The GBA memory map targeted by this RTL is:
@   BIOS  0x00000000, EWRAM 0x02000000, IWRAM 0x03000000,
@   IO    0x04000000, PAL   0x05000000, VRAM  0x06000000,
@   OAM   0x07000000, ROM   0x08000000/0A000000/0C000000,
@   SRAM  0x0E000000/0F000000.
@
@ Current RTL note:
@   gba_rev0.v currently backs EWRAM and PAK_ROM with the SDRAM controller.
@   The baseline phases therefore use halfword accesses for those regions.
@   The final strict phase intentionally checks GBA-style byte lanes and
@   split transfers on 16-bit/8-bit external regions; failures there point to
@   missing bus-splitting or byte-enable behavior.
@
@ Failure reporting:
@   R7  = phase number
@   R0  = 0xPC failure code: P = phase, C = check inside that phase
@   R8  = observed value
@   R9  = expected value
@   R10 = address being checked
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

@ Start an immediate, 16-bit DMA transfer between IWRAM buffers. The CPU is
@ stalled by nWAIT until the DMA engine clears its enable bit.
    .macro START_DMA_IWRAM dma_offset, src_offset, dst_offset
        MOV     R4, #0x04000000
        ORR     R4, R4, #\dma_offset

        MOV     R5, #0x03000000
        ADD     R5, R5, #\src_offset
        STR     R5, [R4]          @ DMAxSAD

        MOV     R5, #0x03000000
        ADD     R5, R5, #\dst_offset
        STR     R5, [R4, #4]      @ DMAxDAD

        MOV     R1, #0x80000000
        ORR     R1, R1, #4        @ enable, immediate, 16-bit, four units
        STR     R1, [R4, #8]      @ DMAxCNT: starts this channel
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
@ PHASE 1 - region decode isolation
@ Writes distinct sentinels to every implemented region, then reads them back
@ after all writes have completed. This catches wrong write enables and read mux
@ selection errors.
@ ==============================================================================
phase_decode:
    MOV     R7, #1

    MOV     R4, #0x02000000      @ EWRAM, SDRAM-backed in current top.
    LOADH   R1, 0xE201
    STRH    R1, [R4, #0x20]

    MOV     R4, #0x03000000      @ IWRAM, 32-bit port.
    LOADW   R1, 0x03, 0x12, 0x34, 0x56
    STR     R1, [R4, #0x20]

    MOV     R4, #0x04000000      @ IO, generic writable BG0CNT register.
    LOADH   R1, 0x4018
    STRH    R1, [R4, #0x08]

    MOV     R4, #0x05000000      @ Palette RAM, 16-bit port.
    LOADH   R1, 0x5020
    STRH    R1, [R4, #0x20]

    MOV     R4, #0x06000000      @ VRAM, 16-bit port.
    LOADH   R1, 0x6020
    STRH    R1, [R4, #0x20]

    MOV     R4, #0x07000000      @ OAM, 32-bit port in this RTL.
    LOADW   R1, 0x07, 0x12, 0x34, 0x56
    STR     R1, [R4, #0x20]

    MOV     R4, #0x08000000      @ PAK_ROM aperture, SDRAM-backed here.
    ADD     R5, R4, #0x1000
    LOADH   R1, 0x8020
    STRH    R1, [R5]

    MOV     R4, #0x0E000000      @ Cart SRAM, 8-bit port.
    MOV     R1, #0xE0
    STRB    R1, [R4, #0x20]

    MOV     R4, #0x02000000
    LDRH    R2, [R4, #0x20]
    LOADH   R1, 0xE201
    CHECK_EQ 0x01, R4

    MOV     R4, #0x03000000
    LDR     R2, [R4, #0x20]
    LOADW   R1, 0x03, 0x12, 0x34, 0x56
    CHECK_EQ 0x02, R4

    MOV     R4, #0x04000000
    LDRH    R2, [R4, #0x08]
    LOADH   R1, 0x4018
    CHECK_EQ 0x03, R4

    MOV     R4, #0x05000000
    LDRH    R2, [R4, #0x20]
    LOADH   R1, 0x5020
    CHECK_EQ 0x04, R4

    MOV     R4, #0x06000000
    LDRH    R2, [R4, #0x20]
    LOADH   R1, 0x6020
    CHECK_EQ 0x05, R4

    MOV     R4, #0x07000000
    LDR     R2, [R4, #0x20]
    LOADW   R1, 0x07, 0x12, 0x34, 0x56
    CHECK_EQ 0x06, R4

    MOV     R4, #0x08000000
    ADD     R5, R4, #0x1000
    LDRH    R2, [R5]
    LOADH   R1, 0x8020
    CHECK_EQ 0x07, R5

    MOV     R4, #0x0E000000
    LDRB    R2, [R4, #0x20]
    MOV     R1, #0xE0
    CHECK_EQ 0x08, R4

@ ==============================================================================
@ PHASE 2 - 16-bit RAM byte lanes and mirrors, excluding SDRAM-backed EWRAM
@ Palette and VRAM use gba_ram_w16, so byte writes, signed loads, and mirrors
@ should work without involving the SDRAM controller.
@ ==============================================================================
phase_w16_local:
    MOV     R7, #2

    MOV     R4, #0x05000000      @ Palette byte lanes.
    MOV     R1, #0
    STRH    R1, [R4, #0x40]
    MOV     R1, #0xA5
    STRB    R1, [R4, #0x40]
    MOV     R1, #0x5A
    STRB    R1, [R4, #0x41]
    LDRH    R2, [R4, #0x40]
    LOADH   R1, 0x5AA5
    CHECK_EQ 0x01, R4

    MOV     R1, #0x80
    STRB    R1, [R4, #0x42]
    LDRSB   R2, [R4, #0x42]
    MVN     R1, #0x7F           @ 0xFFFFFF80
    CHECK_EQ 0x02, R4

    LOADH   R1, 0x5A5A          @ Palette 0x400-byte mirror.
    STRH    R1, [R4, #0x80]
    ADD     R5, R4, #0x400
    LDRH    R2, [R5, #0x80]
    LOADH   R1, 0x5A5A
    CHECK_EQ 0x03, R5

    MOV     R4, #0x06000000      @ VRAM byte lanes.
    MOV     R1, #0
    STRH    R1, [R4, #0x40]
    MOV     R1, #0xC3
    STRB    R1, [R4, #0x40]
    MOV     R1, #0x3C
    STRB    R1, [R4, #0x41]
    LDRH    R2, [R4, #0x40]
    LOADH   R1, 0x3CC3
    CHECK_EQ 0x04, R4

    LOADH   R1, 0xFF80
    STRH    R1, [R4, #0x42]
    LDRSH   R2, [R4, #0x42]
    MVN     R1, #0x7F           @ 0xFFFFFF80
    CHECK_EQ 0x05, R4

    LOADH   R1, 0x6A6A          @ VRAM upper 32 KB fold.
    ADD     R5, R4, #0x10000
    STRH    R1, [R5, #0x40]
    ADD     R5, R5, #0x8000
    LDRH    R2, [R5, #0x40]
    LOADH   R1, 0x6A6A
    CHECK_EQ 0x06, R5

    LOADH   R1, 0x6B6B          @ VRAM 0x20000-byte mirror.
    STRH    R1, [R4, #0x80]
    ADD     R5, R4, #0x20000
    LDRH    R2, [R5, #0x80]
    LOADH   R1, 0x6B6B
    CHECK_EQ 0x07, R5

@ ==============================================================================
@ PHASE 3 - 32-bit memories and mirrors
@ IWRAM and OAM are backed by the 32-bit sram.v wrapper in this design.
@ ==============================================================================
phase_w32:
    MOV     R7, #3

    MOV     R4, #0x03000000      @ IWRAM word and byte readback.
    LOADW   R1, 0x11, 0x22, 0x33, 0x44
    STR     R1, [R4, #0x100]
    LDR     R2, [R4, #0x100]
    LOADW   R1, 0x11, 0x22, 0x33, 0x44
    CHECK_EQ 0x01, R4

    LDRB    R2, [R4, #0x101]
    MOV     R1, #0x33
    CHECK_EQ 0x02, R4

    LOADH   R1, 0xABCD
    ADD     R5, R4, #0x100
    STRH    R1, [R5, #2]
    LDR     R2, [R4, #0x100]
    LOADW   R1, 0xAB, 0xCD, 0x33, 0x44
    CHECK_EQ 0x03, R4

    LOADW   R1, 0x13, 0x57, 0x9B, 0xDF
    STR     R1, [R4, #0x120]
    ADD     R5, R4, #0x8000
    LDR     R2, [R5, #0x120]
    LOADW   R1, 0x13, 0x57, 0x9B, 0xDF
    CHECK_EQ 0x04, R5

    MOV     R4, #0x07000000      @ OAM word and mirror.
    LOADW   R1, 0x21, 0x43, 0x65, 0x87
    STR     R1, [R4, #0x100]
    LDRB    R2, [R4, #0x103]
    MOV     R1, #0x21
    CHECK_EQ 0x05, R4

    LOADW   R1, 0xCA, 0xFE, 0xBA, 0xBE
    STR     R1, [R4, #0x120]
    ADD     R5, R4, #0x400
    LDR     R2, [R5, #0x120]
    LOADW   R1, 0xCA, 0xFE, 0xBA, 0xBE
    CHECK_EQ 0x06, R5

@ ==============================================================================
@ PHASE 4 - IO register file semantics
@ Checks generic byte/half/word storage plus a few hardware-driven fields wired
@ at top level: KEY = 0x03FF, VCOUNT = 0, DISPSTAT status bits = 0.
@ ==============================================================================
phase_io:
    MOV     R7, #4
    MOV     R4, #0x04000000

    LOADW   R1, 0x13, 0x57, 0x24, 0x68
    STR     R1, [R4, #0x28]      @ BG2X low/high registers.
    LDR     R2, [R4, #0x28]
    LOADW   R1, 0x13, 0x57, 0x24, 0x68
    CHECK_EQ 0x01, R4

    MOV     R1, #0xAA
    STRB    R1, [R4, #0x29]
    LDRH    R2, [R4, #0x28]
    LOADH   R1, 0xAA68
    CHECK_EQ 0x02, R4

    LOADH   R1, 0xFFFF
    STRH    R1, [R4, #0x04]      @ DISPSTAT: low status bits are read-only.
    LDRH    R2, [R4, #0x04]
    LOADH   R1, 0xFFF8
    CHECK_EQ 0x03, R4

    LDRH    R2, [R4, #0x06]      @ VCOUNT input tied to zero.
    MOV     R1, #0
    CHECK_EQ 0x04, R4

    ADD     R5, R4, #0x100
    LDRH    R2, [R5, #0x30]      @ KEY input tied to all released.
    LOADH   R1, 0x03FF
    CHECK_EQ 0x05, R5

    LOADH   R1, 0xFFFF
    ADD     R5, R4, #0x200
    STRH    R1, [R5, #2]         @ IF is write-1-to-clear, no IRQ sources set.
    LDRH    R2, [R5, #2]
    MOV     R1, #0
    CHECK_EQ 0x06, R5

@ ==============================================================================
@ PHASE 5 - Cart SRAM byte port and mirrors
@ The implemented cart RAM is byte-only. Strict wider-access behavior is checked
@ later because it requires bus splitting outside cart_ram.v.
@ ==============================================================================
phase_cart:
    MOV     R7, #5
    MOV     R4, #0x0E000000

    MOV     R1, #0x5A
    STRB    R1, [R4, #0x40]
    MOV     R1, #0xA5
    STRB    R1, [R4, #0x41]

    LDRB    R2, [R4, #0x40]
    MOV     R1, #0x5A
    CHECK_EQ 0x01, R4

    LDRB    R2, [R4, #0x41]
    MOV     R1, #0xA5
    CHECK_EQ 0x02, R4

    MOV     R1, #0x3C
    STRB    R1, [R4, #0x80]
    MOV     R5, #0x0F000000
    LDRB    R2, [R5, #0x80]
    MOV     R1, #0x3C
    CHECK_EQ 0x03, R5

@ ==============================================================================
@ PHASE 6 - SDRAM-backed EWRAM and PAK_ROM address mirrors
@ These verify the address folding implemented in sdram_controller_top.v.
@ ==============================================================================
phase_sdram_map:
    MOV     R7, #6

    MOV     R4, #0x02000000      @ EWRAM mirrors every 0x40000.
    LOADH   R1, 0x2A2A
    STRH    R1, [R4, #0x80]
    ADD     R5, R4, #0x40000
    LDRH    R2, [R5, #0x80]
    LOADH   R1, 0x2A2A
    CHECK_EQ 0x01, R5

    MOV     R4, #0x08000000      @ ROM image mirrors 0x08/0x0A/0x0C.
    ADD     R5, R4, #0x2000
    LOADH   R1, 0x8ACE
    STRH    R1, [R5]

    MOV     R5, #0x0A000000
    ADD     R5, R5, #0x2000
    LDRH    R2, [R5]
    LOADH   R1, 0x8ACE
    CHECK_EQ 0x02, R5

    MOV     R5, #0x0C000000
    ADD     R5, R5, #0x2000
    LDRH    R2, [R5]
    LOADH   R1, 0x8ACE
    CHECK_EQ 0x03, R5

@ ==============================================================================
@ PHASE 7 - immediate transfers through all four DMA channels
@ Each channel copies four halfwords between isolated IWRAM buffers. Channels
@ run sequentially because an immediate transfer stalls the CPU until it ends;
@ this avoids testing arbitration priority rather than each channel itself.
@ ==============================================================================
phase_dma:
    MOV     R7, #7
    MOV     R4, #0x03000000

@ ---- initialize four source/destination buffer pairs ------------------------
    LOADW   R1, 0xD0, 0x02, 0xD0, 0x01
    STR     R1, [R4, #0x400]
    LOADW   R1, 0xD0, 0x04, 0xD0, 0x03
    STR     R1, [R4, #0x404]
    MOV     R1, #0
    STR     R1, [R4, #0x420]
    STR     R1, [R4, #0x424]

    LOADW   R1, 0xD1, 0x02, 0xD1, 0x01
    STR     R1, [R4, #0x440]
    LOADW   R1, 0xD1, 0x04, 0xD1, 0x03
    STR     R1, [R4, #0x444]
    MOV     R1, #0
    STR     R1, [R4, #0x460]
    STR     R1, [R4, #0x464]

    LOADW   R1, 0xD2, 0x02, 0xD2, 0x01
    STR     R1, [R4, #0x480]
    LOADW   R1, 0xD2, 0x04, 0xD2, 0x03
    STR     R1, [R4, #0x484]
    MOV     R1, #0
    STR     R1, [R4, #0x4A0]
    STR     R1, [R4, #0x4A4]

    LOADW   R1, 0xD3, 0x02, 0xD3, 0x01
    STR     R1, [R4, #0x4C0]
    LOADW   R1, 0xD3, 0x04, 0xD3, 0x03
    STR     R1, [R4, #0x4C4]
    MOV     R1, #0
    STR     R1, [R4, #0x4E0]
    STR     R1, [R4, #0x4E4]

@ DMA0, DMA1, DMA2, DMA3 register blocks start at 0xB0, 0xBC, 0xC8, 0xD4.
    START_DMA_IWRAM 0xB0, 0x400, 0x420
    START_DMA_IWRAM 0xBC, 0x440, 0x460
    START_DMA_IWRAM 0xC8, 0x480, 0x4A0
    START_DMA_IWRAM 0xD4, 0x4C0, 0x4E0

@ ---- verify both word pairs from every DMA destination ----------------------
    MOV     R4, #0x03000000

    ADD     R5, R4, #0x400
    ADD     R5, R5, #0x20
    LDR     R2, [R5]
    LOADW   R1, 0xD0, 0x02, 0xD0, 0x01
    CHECK_EQ 0x01, R5
    ADD     R5, R4, #0x400
    ADD     R5, R5, #0x24
    LDR     R2, [R5]
    LOADW   R1, 0xD0, 0x04, 0xD0, 0x03
    CHECK_EQ 0x02, R5

    ADD     R5, R4, #0x400
    ADD     R5, R5, #0x60
    LDR     R2, [R5]
    LOADW   R1, 0xD1, 0x02, 0xD1, 0x01
    CHECK_EQ 0x03, R5
    ADD     R5, R4, #0x400
    ADD     R5, R5, #0x64
    LDR     R2, [R5]
    LOADW   R1, 0xD1, 0x04, 0xD1, 0x03
    CHECK_EQ 0x04, R5

    ADD     R5, R4, #0x400
    ADD     R5, R5, #0xA0
    LDR     R2, [R5]
    LOADW   R1, 0xD2, 0x02, 0xD2, 0x01
    CHECK_EQ 0x05, R5
    ADD     R5, R4, #0x400
    ADD     R5, R5, #0xA4
    LDR     R2, [R5]
    LOADW   R1, 0xD2, 0x04, 0xD2, 0x03
    CHECK_EQ 0x06, R5

    ADD     R5, R4, #0x400
    ADD     R5, R5, #0xE0
    LDR     R2, [R5]
    LOADW   R1, 0xD3, 0x02, 0xD3, 0x01
    CHECK_EQ 0x07, R5
    ADD     R5, R4, #0x400
    ADD     R5, R5, #0xE4
    LDR     R2, [R5]
    LOADW   R1, 0xD3, 0x04, 0xD3, 0x03
    CHECK_EQ 0x08, R5

@ ==============================================================================
@ PHASE 8 - strict GBA-compatible split-transfer checks
@ These are expected to fail on the current RTL if 16-bit/8-bit regions do not
@ receive byte enables or split wider CPU accesses into multiple bus cycles.
@ ==============================================================================
phase_strict_gba:
    MOV     R7, #8

    MOV     R4, #0x02000000      @ EWRAM byte lane through SDRAM path.
    ADD     R5, R4, #0x200
    MOV     R1, #0
    STRH    R1, [R5]
    MOV     R1, #0x12
    STRB    R1, [R5]
    MOV     R1, #0x34
    STRB    R1, [R5, #1]
    LDRH    R2, [R5]
    LOADH   R1, 0x3412
    CHECK_EQ 0x01, R5

    MOV     R1, #0
    STRH    R1, [R5]
    STRH    R1, [R5, #2]
    LOADW   R1, 0x55, 0x66, 0x77, 0x88
    STR     R1, [R5]
    LDRH    R2, [R5]
    LOADH   R1, 0x7788
    CHECK_EQ 0x02, R5
    LDRH    R2, [R5, #2]
    LOADH   R1, 0x5566
    CHECK_EQ 0x03, R5

    MOV     R4, #0x08000000      @ PAK_ROM/SDRAM 16-bit split behavior.
    ADD     R5, R4, #0x3000
    MOV     R1, #0
    STRH    R1, [R5]
    STRH    R1, [R5, #2]
    LOADW   R1, 0x99, 0xAA, 0xBB, 0xCC
    STR     R1, [R5]
    LDRH    R2, [R5]
    LOADH   R1, 0xBBCC
    CHECK_EQ 0x04, R5
    LDRH    R2, [R5, #2]
    LOADH   R1, 0x99AA
    CHECK_EQ 0x05, R5

    MOV     R4, #0x0E000000      @ Cart SRAM halfword split behavior.
    ADD     R5, R4, #0xC0
    MOV     R1, #0
    STRB    R1, [R5]
    STRB    R1, [R5, #1]
    LOADH   R1, 0xA55A
    STRH    R1, [R5]
    LDRB    R2, [R5]
    MOV     R1, #0x5A
    CHECK_EQ 0x06, R5
    LDRB    R2, [R5, #1]
    MOV     R1, #0xA5
    CHECK_EQ 0x07, R5

all_pass:
    MOV     R7, #0x0A
    MOV     R0, #0xAD
    B       all_pass

fail:
    B       fail

    .end
