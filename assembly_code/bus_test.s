@ ==============================================================================
@ bus_test.s — Bus controller / bus arbiter / SDRAM controller bring-up test
@
@ Datapath under test (gba_rev0.v):
@     arm7tdmi_top -> bus_arbiter -> bus_controller -> { on-chip region RAMs,
@                                                        Sdram_Control (PAK_ROM) }
@
@ Three phases, in the order requested (bus controller -> arbiter -> SDRAM).
@ Each terminal state is a uniquely-addressed spin loop so the outcome is
@ visible on HEX0-5 (r15) on hardware; marker registers (r6/r7/r9/r10/r11)
@ stamp progress for SignalTap / waveform inspection.
@
@ ------------------------------------------------------------------------------
@ RUN PREREQUISITES — this file only *assembles*; runtime is HARDWARE-ONLY:
@   * bios.mif must exist and the BIOS fetch-address handling in gba_rev0.v
@     must be correct, or nothing executes (the CPU boots at 0x0 = BIOS region).
@   * No SDRAM device model exists in-tree and the sim wrapper uses flat SRAM,
@     so none of these three subsystems is simulatable; Phase 3 in particular is
@     validated only against the DE1-SoC's physical SDRAM.
@
@ ACCESS-WIDTH constraints (region port widths bridged onto the 32-bit bus):
@   * EWRAM / PAL / VRAM / OAM = 16-bit ports -> use STRH/LDRH.
@   * IWRAM                    = 32-bit port  -> STRH used here for uniformity.
@   * CART_RAM                 =  8-bit port  -> use STRB/LDRB.
@   Read-backs are masked to the port width because DIN's unused upper bits are
@   undriven on these regions.
@ ==============================================================================

    .arch   armv4t
    .arm
    .section .text
    .global  _start

@ ---- exception vector table (unexpected exceptions park in `trap`) -----------
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
@   Write a distinct sentinel to every writable on-chip region, THEN read them
@   all back. Distinct values + write-all-before-read-all catches mis-routed
@   write strobes (we_*), a mis-muxed read path (data_o), and stuck/duplicated
@   write-enables. Also exercises the arbiter's CPU-passthrough mux for free.
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

    MOV     R10, #0xB000
    ORR     R10, R10, #0x05      @ R10 = 0xB005 : BUS CONTROLLER PASSED

@ ==============================================================================
@ PHASE 2 — BUS ARBITER via DMA0  (grant-mux exercise; best-effort data check)
@   Program DMA0 to copy 4 halfwords EWRAM(0x02000010)->IWRAM(0x03000010) with
@   immediate timing, then trigger it. While dma_active is high the arbiter must
@   switch addr_bus / data_main / MAS from the CPU over to DMA0, and the top's
@   `nWAIT <= (dma_active==0)` freezes the CPU (core gates `clk = MCLK & nWAIT`)
@   for the whole transfer, so the post-DMA read sees a settled result.
@
@   CAVEAT (current RTL): bus_controller's we_*/rden_* are decoded from the CPU's
@   nRW, which is NOT muxed with the DMA's wr_en. The arbiter grant-mux is still
@   exercised, but the end-to-end DMA *data* copy may not land. The compare
@   below is therefore BEST-EFFORT: it stamps R7 (0x0D ok / 0xAD not) and R11
@   (observed dst), then CONTINUES to Phase 3 — it does not park.
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

@ DMA0CNT (word @0x040000B8): low half = CNT_L = count(4); high half = CNT_H =
@ 0x8000 (enable | immediate timing | 16-bit | src/dst increment). The write
@ itself triggers the channel.
    MOV     R1, #0x80000000
    ORR     R1, R1, #0x04        @ 0x80000004
    STR     R1, [R0, #8]         @ DMA0CNT  <-- trigger

    NOP                          @ slack for the nWAIT gating window + transfer
    NOP
    NOP
    NOP

@ ---- best-effort verify: dst[0] should equal src[0] (0xA001) -----------------
    MOV     R0, #0x03000000
    ADD     R0, R0, #0x10
    LDRH    R11, [R0]
    AND     R11, R11, R3         @ R11 = observed DMA dst[0]
    MOV     R1, #0xA000
    ORR     R1, R1, #0x01        @ 0xA001
    CMP     R11, R1
    BEQ     dma_ok
    MOV     R7, #0xAD            @ R7 = 0xAD : DMA data NOT verified (see CAVEAT)
    B       sdram_phase
dma_ok:
    MOV     R7, #0x0D            @ R7 = 0x0D : DMA data verified

@ ==============================================================================
@ PHASE 3 — SDRAM CONTROLLER  (ROM-load burst write + read-back, self-checking)
@   The Terasic Sdram_Control is a FIFO/burst STREAMING controller, not random
@   access: WR_LOAD/RD_LOAD are tied 0 (per-access addresses ignored) and an
@   internal `flag` gates ALL SDRAM traffic until the write FIFO holds
@   WR_LENGTH = 128 words. So a single word write/read-back cannot self-check.
@
@   Instead we LOAD 128 halfwords into PAK_ROM — i.e. write the ROM image into
@   SDRAM, the valid operation needed to populate the game ROM. That fills the
@   write FIFO, sets `flag`, and triggers exactly one 128-word WRITEA burst to
@   the DRAM chip. We then read 128 halfwords back. The write and read pointers
@   both reset to the same base and have not incremented, so the burst we read
@   back IS the burst we wrote: the Nth word read == Nth word written
@   (correspondence is by FIFO order, not by CPU address).
@
@   ASSUMPTION: exactly one FIFO push per STRH and one pop per LDRH. `clock` and
@   `clock_n` are the same ~100 Hz reg inverted, so there is one clock_n edge
@   per CPU memory cycle -> one push/pop per access. A stream shift would show
@   up here as a read-back mismatch on otherwise-working hardware.
@   Pattern: value(i) = 0xC000 + i, for i = 0..127.
@ ==============================================================================
sdram_phase:
@ ---- write 128 halfwords -> one full WR burst is committed to SDRAM ----------
    MOV     R0, #0x08000000      @ PAK_ROM base (SDRAM)
    MOV     R5, #0xC000          @ value = 0xC000 + i
    MOV     R4, #0               @ i = 0
sdram_wr_loop:
    STRH    R5, [R0]             @ push one halfword into WR FIFO (we_pakrom)
    ADD     R0, R0, #2
    ADD     R5, R5, #1
    ADD     R4, R4, #1
    CMP     R4, #128             @ exactly WR_LENGTH = 128 pushes -> one burst
    BNE     sdram_wr_loop

@ ---- read 128 halfwords back and compare in FIFO order -----------------------
    MOV     R0, #0x08000000
    MOV     R5, #0xC000
    MOV     R4, #0
sdram_rd_loop:
    LDRH    R2, [R0]             @ pop one halfword from RD FIFO (rden_pakrom)
    AND     R2, R2, R3
    MOV     R9, R2               @ R9 = last value read back (debug)
    CMP     R2, R5
    BNE     fail_sdram
    ADD     R0, R0, #2
    ADD     R5, R5, #1
    ADD     R4, R4, #1
    CMP     R4, #128
    BNE     sdram_rd_loop

    MOV     R6, #0x5D00
    ORR     R6, R6, #0x0D        @ R6 = 0x5D0D : SDRAM PASSED

@ ==============================================================================
@ All phases reached. Park with a global PASS code. R7 still encodes whether the
@ best-effort DMA data copy verified (0x0D = yes, 0xAD = no).
@ ==============================================================================
all_pass:
    MOV     R0, #0x600
    ORR     R0, R0, #0x0D        @ R0 = 0x60D : all phases PASSED
    B       all_pass

@ ==============================================================================
@ Failure spin loops — distinct addresses (r15/HEX) + distinct r0 region codes.
@ ==============================================================================
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
fail_sdram:
    MOV     R0, #0x5D            @ R9 holds the mismatching value read back
    B       fail_sdram

    .end
