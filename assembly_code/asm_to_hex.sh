#!/usr/bin/env bash
# Assemble an ARM .s source into a 32-bit-per-line .hex for instrucoes.mif.
# Usage: ./asm_to_hex.sh <source.s> [base_addr]
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <source.s> [base_addr]" >&2
    exit 1
fi

src="$1"
base="${2:-0x00000000}"
stem="${src%.s}"

arm-none-eabi-as -march=armv4t -mthumb-interwork -o "${stem}.o" "${src}"
arm-none-eabi-ld -Ttext="${base}" -e _start -o "${stem}.elf" "${stem}.o"
arm-none-eabi-objcopy -O binary "${stem}.elf" "${stem}.bin"
hexdump -v -e '1/4 "%08X\n"' "${stem}.bin" > "${stem}.hex"
rm -f "${stem}.o" "${stem}.bin"

words=$(wc -l < "${stem}.hex")
echo "wrote ${stem}.hex (${words} words), ${stem}.elf"
