# Convert ARM 32-bit hex words into a Quartus MIF padded to the SRAM depth.
# sram.v has DEPTH_POW2 = 12 -> 4096 words at WIDTH = 32.
import sys
from pathlib import Path

TARGET_DEPTH = 4096
WIDTH = 32

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {Path(sys.argv[0]).name} <hex_file>")

hex_path = Path(sys.argv[1])
if hex_path.suffix == "":
    hex_path = hex_path.with_suffix(".hex")

mif_path = hex_path.with_suffix(".mif")

with open(hex_path, "r") as f:
    words = f.read().split()

if len(words) > TARGET_DEPTH:
    raise SystemExit(
        f"hex has {len(words)} words but SRAM holds only {TARGET_DEPTH}"
    )

# Pad with explicit zeros so Quartus sees every address initialised.
words += ["00000000"] * (TARGET_DEPTH - len(words))

with open(mif_path, "w") as f:
    f.write(f"DEPTH = {TARGET_DEPTH};\n")
    f.write(f"WIDTH = {WIDTH};\n")
    f.write("ADDRESS_RADIX = HEX;\n")
    f.write("DATA_RADIX = HEX;\n")
    f.write("CONTENT BEGIN\n")
    for i, word in enumerate(words):
        f.write(f"{i:X} : {word};\n")
    f.write("END;\n")

print(f"Conversion complete! {TARGET_DEPTH} entries written to {mif_path}.")
