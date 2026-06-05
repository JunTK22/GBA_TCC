@ ==============================================================================
@ bus_test.s — Bus controller / bus arbiter / SDRAM controller bring-up test
@ Targets the GBA datapath wired in gba_rev0.v:
@     arm7tdmi_top -> bus_arbiter -> bus_controller -> {region RAMs, SDRAM}
@
@ Each phase exercises one subsystem and parks the PC in a uniquely-addressed
@ spin loop so the outcome is visible on HEX0-5 (r15) on hardware, while also
@ stamping a marker register (r0/r4/r9/r10/r11) for waveform / SignalTap.
@
@ --------------------------------------------------------------------------
@ KNOWN INTEGRATION LIMITS this test was written around (see chat notes):
@   * Region RAM data ports are 16-bit (8-bit for CART_RAM) on a 32-bit bus,
@     and `.size(MAS)` truncates to MAS[0]. => use STRH/LDRH (STRB/LDRB for
@     CART_RAM); word accesses to these regions mistranslate. The verify masks
@     loaded values to the port width because DIN's upper bits are undriven.
@   * SDRAM (PAK_ROM): `external_sdram` is a 1-bit implicit net and the
@     controller's RD_ADDR is hardwired to 0 (FIFO-streaming, not random
@     access). Phase 2 is therefore OBSERVE-ONLY — it cannot self-check.
@   * The bus arbiter only leaves CPU-passthrough while a DMA owns the bus,
@     but there is no CPU bus-hold (nWAIT/nMREQ open). On the current hardware
@     the DMA trigger hijacks the address bus and the CPU pipeline derails, so
@     Phase 3's verify is reliable only under a sim/wrapper that stalls the
@     CPU. r10/r11 mark progress regardless.
@   * NOTE: running this requires bios.mif to exist AND the BIOS fetch-address
@     bug fixed (gba_rev0.v passes a byte address where bios.v wants a word
@     address: `.addr(addr_bus[13:2])`). Until then nothing executes from BIOS.
@ ==============================================================================

    .arch   armv4t
    .arm
    .section .text
    .global  _start

@ ------------------------------------------------------------------------------
@ Exception vector table (first 32 bytes). Unexpected exceptions park in `trap`.
@ ------------------------------------------------------------------------------
_start:
    B   reset_handler        @ 0x00 Reset
    B   trap                 @ 0x04 Undefined
    B   trap                 @ 0x08 Software Interrupt
    B   trap                 @ 0x0C Prefetch Abort
    B   trap                 @ 0x10 Data Abort
    NOP                      @ 0x14 Reserved
    B   trap                 @ 0x18 IRQ
    B   trap                 @ 0x1C FIQ

trap:
    B   trap                 @ unexpected exception -> park here

reset_handler:
    MSR     CPSR, #0xDF      @ System mode, IRQ+FIQ masked (KEYs drive nIRQ/nFIQ)
    MOV     R3, #0xFF
    ORR     R3, R3, #0xFF00  @ R3 = 0x0000FFFF : halfword compare mask

@ ==============================================================================
@ PHASE 1 — BUS CONTROLLER  (self-checking)
@   Write a distinct sentinel to every writable region, THEN read them all
@   back. Distinct values + write-all-before-read-all catches mis-routed write
@   strobes, a mis-muxed read path, and stuck/duplicated write-enables. This
@   also exercises the arbiter's CPU-passthrough path for free.
@ ==============================================================================

@ ---- write phase (halfword regions; CART_RAM is an 8-bit port -> byte) -------
    MOV     R0, #0x02000000      @ EWRAM
    MOV     R1, #0x11
    ORR     R1, R1, #0x1100      @ 0x1111
    STRH    R1, [R0]

    MOV     R0, #0x03000000      @ IWRAM
    MOV     R1, #0x22
    ORR     R1, R1, #0x2200      @ 0x2222
    STRH    R1, [R0]

    MOV     R0, #0x05000000      @ PAL_RAM
    MOV     R1, #0x55
    ORR     R1, R1, #0x5500      @ 0x5555
    STRH    R1, [R0]

    MOV     R0, #0x06000000      @ VRAM
    MOV     R1, #0x66
    ORR     R1, R1, #0x6600      @ 0x6666
    STRH    R1, [R0]

    MOV     R0, #0x07000000      @ OAM
    MOV     R1, #0x77
    ORR     R1, R1, #0x7700      @ 0x7777
    STRH    R1, [R0]

    MOV     R0, #0x0E000000      @ CART_RAM (8-bit port)
    MOV     R1, #0xEE            @ 0xEE
    STRB    R1, [R0]

@ ---- read-back / verify phase ------------------------------------------------
    MOV     R0, #0x02000000      @ EWRAM
    LDRH    R2, [R0]
    AND     R2, R2, R3
    MOV     R1, #0x11
    ORR     R1, R1, #0x1100
    CMP     R2, R1
    BNE     fail_ewram

    MOV     R0, #0x03000000      @ IWRAM
    LDRH    R2, [R0]
    AND     R2, R2, R3
    MOV     R1, #0x22
    ORR     R1, R1, #0x2200
    CMP     R2, R1
    BNE     fail_iwram

    MOV     R0, #0x05000000      @ PAL_RAM
    LDRH    R2, [R0]
    AND     R2, R2, R3
    MOV     R1, #0x55
    ORR     R1, R1, #0x5500
    CMP     R2, R1
    BNE     fail_palram

    MOV     R0, #0x06000000      @ VRAM
    LDRH    R2, [R0]
    AND     R2, R2, R3
    MOV     R1, #0x66
    ORR     R1, R1, #0x6600
    CMP     R2, R1
    BNE     fail_vram

    MOV     R0, #0x07000000      @ OAM
    LDRH    R2, [R0]
    AND     R2, R2, R3
    MOV     R1, #0x77
    ORR     R1, R1, #0x7700
    CMP     R2, R1
    BNE     fail_oam

    MOV     R0, #0x0E000000      @ CART_RAM
    LDRB    R2, [R0]
    CMP     R2, #0xEE
    BNE     fail_cartram

    MOV     R4, #0x6000
    ORR     R4, R4, #0x0D        @ R4 = 0x600D : BUS CONTROLLER PASSED

@ ==============================================================================
@ PHASE 2 — SDRAM CONTROLLER  (observe-only)
@   Issue a read from PAK_ROM. Drives rden_pakrom + the SDRAM read path. NOT
@   self-checking (see header). R9 captures whatever the controller returns.
@ ==============================================================================
    MOV     R0, #0x08000000
    LDRH    R9, [R0]             @ observe-only: value is not the addressed word

@ ==============================================================================
@ PHASE 3 — BUS ARBITER via DMA0  (setup + trigger; best-effort verify)
@   Program DMA0 to copy 4 halfwords EWRAM(0x02000010)->IWRAM(0x03000010) with
@   immediate timing, then trigger it. The arbiter's DMA-grant mux only engages
@   while dma_active is high. CAVEAT: no CPU bus-hold -> the verify below is
@   trustworthy only in sim/wrapper that stalls the CPU (see header).
@ ==============================================================================

@ ---- fill EWRAM source buffer 0x02000010.. with A001,A002,A003,A004 ----------
    MOV     R0, #0x02000000
    ADD     R0, R0, #0x10
    MOV     R1, #0xA000
    ORR     R1, R1, #0x01        @ 0xA001
    STRH    R1, [R0]
    MOV     R1, #0xA000
    ORR     R1, R1, #0x02        @ 0xA002
    STRH    R1, [R0, #2]
    MOV     R1, #0xA000
    ORR     R1, R1, #0x03        @ 0xA003
    STRH    R1, [R0, #4]
    MOV     R1, #0xA000
    ORR     R1, R1, #0x04        @ 0xA004
    STRH    R1, [R0, #6]

@ ---- program DMA0 registers (word writes; io_registers is 32-bit-capable) ----
    MOV     R0, #0x04000000
    ORR     R0, R0, #0xB0        @ R0 = 0x040000B0 (DMA0SAD)

    MOV     R1, #0x02000000
    ADD     R1, R1, #0x10        @ src = 0x02000010
    STR     R1, [R0]             @ DMA0SAD

    MOV     R1, #0x03000000
    ADD     R1, R1, #0x10        @ dst = 0x03000010
    STR     R1, [R0, #4]         @ DMA0DAD

    MOV     R10, #0xDD
    ORR     R10, R10, #0xDD00    @ R10 = 0xDDDD : DMA armed

@ DMA0CNT (word @0x040000B8): low half = CNT_L = count(4), high half = CNT_H =
@ 0x8000 (enable | immediate timing | 16-bit). The write itself triggers DMA.
    MOV     R1, #0x80000000
    ORR     R1, R1, #0x04        @ 0x80000004
    STR     R1, [R0, #8]         @ DMA0CNT  <-- trigger

@ ---- best-effort verify: dst[0] should equal src[0] (0xA001) -----------------
    MOV     R0, #0x03000000
    ADD     R0, R0, #0x10
    LDRH    R11, [R0]
    AND     R11, R11, R3
    MOV     R1, #0xA000
    ORR     R1, R1, #0x01        @ 0xA001
    CMP     R11, R1
    BEQ     dma_pass
    B       dma_fail

@ ==============================================================================
@ Result spin loops — distinct addresses (r15/HEX) + distinct r0 codes.
@ ==============================================================================
dma_pass:
    MOV     R0, #0x6000
    ORR     R0, R0, #0x0D        @ R0 = 0x600D : all phases reached, DMA verified
    B       dma_pass

dma_fail:
    MOV     R0, #0xB00
    ORR     R0, R0, #0xAD        @ R0 = 0xBAD : DMA dst != src (or CPU derailed)
    B       dma_fail

fail_ewram:
    MOV     R0, #0x02
    B       fail_ewram
fail_iwram:
    MOV     R0, #0x03
    B       fail_iwram
fail_palram:
    MOV     R0, #0x05
    B       fail_palram
fail_vram:
    MOV     R0, #0x06
    B       fail_vram
fail_oam:
    MOV     R0, #0x07
    B       fail_oam
fail_cartram:
    MOV     R0, #0x0E
    B       fail_cartram

    .end
