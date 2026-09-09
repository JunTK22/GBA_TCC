"""Convert one raw 16 KiB GBA BIOS image to a 4096x32 Quartus MIF."""

import hashlib
import sys
import zlib
from pathlib import Path


BIOS_BYTES = 16 * 1024
BIOS_WORDS = BIOS_BYTES // 4


if len(sys.argv) != 3:
    raise SystemExit(
        f"usage: {Path(sys.argv[0]).name} <input.rom> <output.mif>"
    )

bios_path = Path(sys.argv[1])
mif_path = Path(sys.argv[2])
bios = bios_path.read_bytes()

if len(bios) != BIOS_BYTES:
    raise SystemExit(
        f"BIOS is {len(bios)} bytes; expected exactly {BIOS_BYTES} bytes"
    )

with mif_path.open("w", encoding="ascii", newline="\n") as mif:
    mif.write(f"DEPTH = {BIOS_WORDS};\n")
    mif.write("WIDTH = 32;\n")
    mif.write("ADDRESS_RADIX = HEX;\n")
    mif.write("DATA_RADIX = HEX;\n")
    mif.write("CONTENT BEGIN\n")

    for offset in range(0, BIOS_BYTES, 4):
        word = int.from_bytes(bios[offset:offset + 4], byteorder="little")
        mif.write(f"{offset // 4:X} : {word:08X};\n")

    mif.write("END;\n")

print(
    f"Converted {bios_path} to {mif_path}: "
    f"CRC32={zlib.crc32(bios):08X} "
    f"SHA256={hashlib.sha256(bios).hexdigest()}"
)
