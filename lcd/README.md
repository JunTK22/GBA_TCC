# LCD display adapter (ILI9488, 480×320, 8080 parallel)

RTL that drives a 320×480 ILI9488 panel (used in landscape 480×320) from the GBA
PPU's composed pixel output. The GBA renders 240×160; this adapter upscales 2× in
both axes to fill the panel. Design reference and panel/timing details:
[`../docs/320x480_lcd_display/FPGA_LCD_INTEGRATION.md`](../docs/320x480_lcd_display/FPGA_LCD_INTEGRATION.md).

## Data flow

```
PPU output_pixel[14:0] (RGB555) ─┐
PPU output_valid ────────────────┤ clock_cpu (17 MHz)
PPU output_vblank ───────────────┘
                                  ▼
        ┌──────────────────────── lcd_top ────────────────────────┐
        │  RGB555→565 convert                                      │
        │  ┌───────────────┐   ┌──────────────────┐   ┌──────────┐│
        │  │lcd_initializer│   │ lcd_writer_fifo  │   │lcd_8080_ ││
        │  │ (68 MHz)      │   │ W:17MHz  R:68MHz  │   │ writer   ││
        │  │ ILI9488 init  │   │ ring FIFO + 2×2   │──▶│ (68 MHz) ││
        │  │ command stream│   │ upscale (M10K)    │pix│ frame    ││
        │  └──────┬────────┘   └──────────────────┘   │ +burst   ││
        │         │  init_done ────────────────────┐  └────┬─────┘│
        │         ▼                                 ▼       ▼      │
        │        8080 bus MUX (init drives during init, glue after)│
        └──────────────────────────┬──────────────────────────────┘
                                    ▼  GPIO_0[19:0]
              DB[15:0]=GPIO_0[15:0], CSX=[16], DCX=[17], WRX=[18], RESET=[19]
                                    ▼
                              ILI9488 panel
```

## Modules

| File | In synth build? | Role |
| --- | --- | --- |
| `lcd_top.v` | **yes** | Subsystem top: instantiates the three below, RGB555→565 conversion, 8080-bus mux, derives `frame_start` from `ppu_vblank`. Instantiated in `gba_rev0.v` as `u_lcd`. |
| `lcd_initializer.v` | **yes** | ILI9488 power-up FSM. Emits the fixed 70-write command/parameter stream (0x28 off … gamma/power … 0x36 MADCTL, 0x3A COLMOD, 0x11 sleep-out, 0x29 on) on 8-bit `cmd`/`param` buses with `CSX/DCX/WRX/nRST`. Asserts `init_done` at the end. |
| `lcd_writer_fifo.v` | **yes** | Deep row-buffer ring FIFO (producer `clk_W`=17 MHz, consumer `clk_R`=68 MHz). Gray-code async pointers, **synchronous (M10K) read**, 2×2 upscale on the read side, and a whole-frame-drop policy. This is the synthesizable writer. |
| `lcd_8080_writer.v` | **yes** | Per-frame sequencer: issues CASET(0x2A)/PASET(0x2B)/RAMWR(0x2C) then bursts `HRES*VRES` scaled pixels pulled from the FIFO, driving `CSX/DCX/WRX/DB`. |
| `lcd_writer.v` | no (reference) | Original **2-line-buffer** writer (ready-bit ownership handshake + demand-pull). Superseded by `lcd_writer_fifo` because two line buffers cannot sustain the sparse PPU cadence. Kept for its testbench and as documentation of the handshake. |

### How the writer FIFO works
- Each FIFO entry is one 240-pixel source row (`COLS`). Depth `NBUF` must be a
  **power of two ≥ 4** (gray-pointer requirement); default **32**.
- **Why 32:** the per-row producer/consumer rate mismatch builds a backlog during
  the active region that drains in VBlank. Simulation measured a **peak backlog of
  24 rows**, so 16 overflows and 32 is the smallest power-of-two that fits with margin.
- The read side registers `buf_mem` (`pixel_o_r <= buf_mem[addr]`) so it maps to
  **M10K** (~12 blocks) instead of ~123k fabric registers. The 1-cycle read latency
  is absorbed by masking `pixel_valid_o` for one warmup cycle after each advance, so
  the consumer self-times to it (the glue needs no change).
- **Frame-drop policy:** a source frame is captured only if the FIFO fully drained by
  its `frame_start`; otherwise the whole frame is skipped (`frame_dropped`), never a
  partial row. This keeps output row-aligned if the consumer ever falls behind. In the
  nominal case (NBUF ≥ peak) it never fires.

## Integration in `gba_rev0.v`
- Instantiated as `u_lcd`, tapping the previously-open PPU
  `output_valid`/`output_pixel[14:0]`/`output_vblank`. It is a **passive tap** — it
  adds no load on GBA VRAM arbitration, DMA, `mem_ready`, or `nWAIT`.
- Clocks: `clk_ppu = clock_cpu` (17 MHz), `clk_lcd = clock_sdram` (68 MHz). **The
  68 MHz consumer rate is required** — at 17 MHz no amount of buffering sustains the frame.
- Pins: `GPIO_0[15:0]`=DB, `[16]`=CSX, `[17]`=DCX, `[18]`=WRX, `[19]`=RESET (write-only;
  tie panel RDX high externally). Constraints for these outputs live in `gba_rev0.sdc`
  (`set_output_delay` + `set_multicycle_path -setup 2`; provisional pending board measurement).
- RGB555→565 conversion (`{r5,g5,g_msb,b5}`) happens once, in `lcd_top`.
- **Capture gated on `init_done`.** The CPU/PPU are left free-running during panel init (the tap
  is passive — the console does not depend on the display). `lcd_top` synchronizes `init_done`
  into `clk_ppu` and ANDs it with the `frame_start` pulse, so the FIFO first arms capture at the
  **first frame boundary after init** — the first displayed frame is a clean, frame-aligned current
  frame rather than stale data captured mid-init. (To instead show the BIOS boot from frame 0, hold
  the GBA core in reset until `init_done` via a startup sequencer — see Next steps.)

## Status / known limits
- Compiles, fits (36% ALMs, 33% M10K), and passes STA with **0 setup violations**.
- Init wait counts in `lcd_initializer.v` are **placeholders** (≈1000 cycles), not the
  ILI9488's real 120 ms reset/sleep delays — size them before real hardware.
- 8080 output timing to the panel is constrained only provisionally; confirm DB-vs-WRX
  setup/hold by measurement on the board.

## Testbenches

Sources: `../simulation/gba_rev0_tb/ppu_tbs/lcd_*_tb.v`.
Runner (Icarus/iverilog): `../simulation/gba_rev0_tb/run_lcd_aux.sh` — builds and runs
all six with `iverilog -g2012 -Wall`. Each prints a `PASS:`/`FAILED` line.

```bash
# run the whole LCD regression
bash code/simulation/gba_rev0_tb/run_lcd_aux.sh
```

| Testbench | Exercises | Checks |
| --- | --- | --- |
| `lcd_initializer_tb.v` | `lcd_initializer` | Emitted stream equals the intended 70-write ILI9488 table (DCX/CSX framing, reset order). |
| `lcd_writer_fifo_tb.v` | `lcd_writer_fifo` | Real-cadence peak-backlog sim (4:1 clocks, 1232-clk scanlines, 160 active + 68 VBlank). Reports peak occupancy (24), 0 drops, VBlank drain, exact 2×2 pixel stream. |
| `lcd_fifo_drop_tb.v` | `lcd_writer_fifo` | Deterministic frame-drop: a non-drained boundary skips the whole frame (no partial rows, no scramble), then recovers. |
| `lcd_8080_writer_tb.v` | `lcd_8080_writer` (+`lcd_writer`) | Small framing/passthrough/re-issue, then full 480×320: CASET/PASET byte-split (`00 00 01 DF` / `00 00 01 3F`), exactly 153 600 pixels/frame. |
| `lcd_top_tb.v` | `lcd_top` (full stack) | Init stream on the muxed bus → `init_done` → glue framing → pixel data == RGB565 conversion of the 2×2-upscaled source; no spurious frame drop. |
| `lcd_writer_tb.v` | `lcd_writer` (reference) | 2×2 upscale + ownership handshake of the old 2-buffer writer; dual-clock starvation demo. |

Run one manually (example — the top stack):

```bash
cd code/simulation/gba_rev0_tb
iverilog -g2012 -Wall -s lcd_top_tb -o /tmp/t.vvp \
    ../../lcd/lcd_top.v ../../lcd/lcd_initializer.v \
    ../../lcd/lcd_writer_fifo.v ../../lcd/lcd_8080_writer.v \
    ppu_tbs/lcd_top_tb.v && vvp /tmp/t.vvp
```

### Panel-disconnected bring-up dashboard (top-level, `gba_rev0.v`)

For a first hardware test with the LCD **disconnected**, the top mirrors adapter status to the
on-board HEX/LEDs (observation only — no LCD RTL/clocking changed). Set `SW[8]=1` for the LCD HEX
view: `HEX5:4` = init write count (settles to `46` = 70 writes), `HEX3:2` = last command byte (`29`
after init, then `2A`/`2B`/`2C` while streaming), `HEX1:0` = frame counter.

With `SW[8]=0` the HEX shows a CPU-debug word for hw-test ROM bring-up, selectable with `SW[7:6]`:
`00` = PC/r15 (`region · offset[19:0]`), `01` = r0[23:0], `10` = CPSR (flags on HEX5:4, mode on HEX1:0),
`11` = live bus address. Use these to see where a ROM settles / its result register on the board. `LEDR[9]` is a ~1 Hz
heartbeat (68 MHz LCD clock alive), `LEDR[3]` = `init_done`, `LEDR[4]` = `lcd_rst_n`, `LEDR[5]` =
`frame_dropped`, `LEDR[6]` = `ppu_ready`, and `LEDR[7:8]` blink on write/frame activity. `LEDR[2:0]`
keep their CPU-debug meaning. A slowed `clk_lcd` is deliberately **not** used (the init wait loops
would take ~18 min to play out); the latched `46`/`29` values are the actual verification.

The full integrated top (with `u_lcd`) is also verified functionally under Questa via
the PPU hw-test ROMs (`run_hw_test.sh` — e.g. `greenswap`, `vram-mirror` pass) and by
`quartus_sh --flow compile gba_rev0` (fit + STA).

## Next steps

Simulation and synthesis are clean; the remaining work is real-timing correctness and
board bring-up. Roughly in dependency order:

1. **Size the init delays (RTL). — DONE (2026-09-22).** `lcd_initializer` now uses real ILI9488
   delays via parameters `T_RST_LOW`/`T_RST_WAIT`/`T_SLEEP`/`T_DISPON`, defaulted for a 68 MHz
   `clk_lcd`: reset-low 10 ms (680 000), reset-release 120 ms (8 160 000), sleep-out 120 ms
   (8 160 000), display-on 20 ms (1 360 000). `lcd_top` forwards the same parameters (real defaults),
   so the synthesis build gets the real timing. The TBs override them with tiny values for fast sim.
   If `clk_lcd` ever changes from 68 MHz, rescale the defaults.

2. **Get the supplier's panel init profile.** The gamma/power table in `lcd_initializer.v`
   is the driver's generic default — an unqualified bring-up candidate, not a
   supplier-matched profile. Obtain the flex-marking-specific gamma/power/MADCTL/inversion
   values before trusting colour/contrast.

3. **Board hardware prep.** Verify FPC pin-1/continuity through the breakout; wire the
   mode straps **IM2:IM1:IM0 = 010** (16-bit 8080), hold **RDX high**, add current-limited
   backlight; arrange CSX/WRX high + RESET low during FPGA config. See
   [`FPGA_LCD_INTEGRATION.md`](../docs/320x480_lcd_display/FPGA_LCD_INTEGRATION.md) §Power/Wiring.

4. **Program and bring up incrementally.** Load `gba_rev0.sof`; check a lit backlight, then
   a solid fill, then labelled-corner patterns — verify black/white polarity, R/G/B,
   rotation/mirroring, and all four edges (a white screen only proves the backlight).

5. **Confirm 8080 output timing on the board.** The `set_output_delay` in `gba_rev0.sdc`
   is **provisional** (spec 10 ns + assumed ≤1 ns trace, modelled as multicycle-2 vs
   `clock_sdram`). Measure DB-vs-WRX setup/hold at the panel and re-derive the numbers
   from the actual jumper/trace delay.

6. **(Optional) Tearing/TE.** Only after basic writes work: sync the panel TE line into
   the adapter and enable it (`0x35`); verify its period and write deadline. TE must never
   replace GBA DISPSTAT/IRQ/DMA timing.

7. **(Optional, not LCD-specific) SDRAM→timers crossing.** The setup failure there was
   cleared with a `set_false_path` justified by the request-hold SDRAM CDC — it removes the
   paths from STA but does not change silicon. If that crossing is ever exercised outside
   the request-hold assumption, it wants a proper synchronizer/handshake. Pre-existing;
   unrelated to the LCD adapter.

8. **(Housekeeping) `lcd_writer.v`.** The original 2-line-buffer writer is kept only for its
   testbench and as reference; it is not in the synth build. Remove it and `lcd_writer_tb`
   if the reference is no longer wanted.
