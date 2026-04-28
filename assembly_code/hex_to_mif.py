# Save this as convert.py and run it in the same folder as your hex file
with open("instrucoes.hex", "r") as f:
    raw_text = f.read()

# Split the text into individual 16-bit words (ignoring spaces/newlines)
words = raw_text.split()

with open("instrucoes.mif", "w") as f:
    f.write(f"DEPTH = {len(words)};\n")
    f.write("WIDTH = 16;\n")
    f.write("ADDRESS_RADIX = HEX;\n")
    f.write("DATA_RADIX = HEX;\n")
    f.write("CONTENT BEGIN\n")
    
    for i, word in enumerate(words):
        f.write(f"{i:X} : {word};\n")
        
    f.write("END;\n")

print("Conversion complete! Use instrucoes.mif in your project.")