# Convert ARM 32-bit hex words into a Quartus MIF padded to the SRAM depth.
# sram.v has DEPTH_POW2 = 12 -> 4096 words at WIDTH = 32.
TARGET_DEPTH = 4096
WIDTH = 32
hex_file1 = "instrucoes"
hex_file2 = "arm7tdmi_thumb_test"

#with open("instrucoes.hex", "r") as f:
with open(hex_file1+".hex", "r") as f:
    words = f.read().split()

if len(words) > TARGET_DEPTH:
    raise SystemExit(
        f"hex has {len(words)} words but SRAM holds only {TARGET_DEPTH}"
    )

# Pad with explicit zeros so Quartus sees every address initialised.
words += ["00000000"] * (TARGET_DEPTH - len(words))

with open(hex_file1+".mif", "w") as f:
    f.write(f"DEPTH = {TARGET_DEPTH};\n")
    f.write(f"WIDTH = {WIDTH};\n")
    f.write("ADDRESS_RADIX = HEX;\n")
    f.write("DATA_RADIX = HEX;\n")
    f.write("CONTENT BEGIN\n")
    for i, word in enumerate(words):
        f.write(f"{i:X} : {word};\n")
    f.write("END;\n")

print(f"Conversion complete! {TARGET_DEPTH} entries written to "+hex_file1+".mif.")