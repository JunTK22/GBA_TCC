"""Convert one raw .gba image to the 128 KiB, 16-bit Game Pak ROM MIF."""

import sys
from pathlib import Path


ROM_BYTES = 128 * 1024
ROM_HALFWORDS = ROM_BYTES // 2


if len(sys.argv) != 3:
    raise SystemExit(
        f"usage: {Path(sys.argv[0]).name} <input.gba> <output.mif>"
    )

rom_path = Path(sys.argv[1])
mif_path = Path(sys.argv[2])
rom = rom_path.read_bytes()

if len(rom) > ROM_BYTES:
    raise SystemExit(
        f"ROM is {len(rom)} bytes; gamepak_rom holds only {ROM_BYTES} bytes"
    )

if len(rom) & 1:
    rom += b"\xff"

with mif_path.open("w", encoding="ascii", newline="\n") as mif:
    mif.write(f"DEPTH = {ROM_HALFWORDS};\n")
    mif.write("WIDTH = 16;\n")
    mif.write("ADDRESS_RADIX = HEX;\n")
    mif.write("DATA_RADIX = HEX;\n")
    mif.write("CONTENT BEGIN\n")

    for address in range(0, len(rom), 2):
        halfword = rom[address] | (rom[address + 1] << 8)
        mif.write(f"{address // 2:X} : {halfword:04X};\n")

    first_unused = len(rom) // 2
    if first_unused < ROM_HALFWORDS:
        mif.write(f"[{first_unused:X}..{ROM_HALFWORDS - 1:X}] : FFFF;\n")

    mif.write("END;\n")

print(
    f"Converted {rom_path} ({len(rom)} padded bytes) to {mif_path} "
    f"({ROM_HALFWORDS} halfwords)."
)
