#!/bin/bash
# Cach dung: ./build.sh [ten_file_c]   (mac dinh: main.c)   -> tao fw.elf, fw.bin, fw.hex, fw.dis
set -e
SRC=${1:-main.c}
PFX=${PFX:-riscv64-unknown-elf}          # hoac PFX=riscv-none-elf neu dung xPack

$PFX-gcc -march=rv32i -mabi=ilp32 -O1 -Wall -nostdlib -ffreestanding \
         -Wl,-T,link.ld -o fw.elf crt0.S $SRC
$PFX-objcopy -O binary fw.elf fw.bin
$PFX-objdump -d -M no-aliases fw.elf > fw.dis
python3 bin2hex.py fw.bin fw.hex
