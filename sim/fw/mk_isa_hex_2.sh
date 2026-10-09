#!/bin/bash
# Cach dung: ./mk_isa_hex.sh <thu_muc_riscv-tests/isa> [thu_muc_dau_ra] [mau_ten]
#   mau_ten mac dinh la "rv32ui-p-*"; vi du "rv32mi-p-*" cho bo kiem tra che do machine
# Voi moi test khop mau: tao <ra>/<ten>.hex (moi dong 1 word, bat dau tai 0x80000000)
# va ghi <ra>/list.txt gom cac dong "ten dia_chi_tohost_hex".
set -e
ISA=${1:?can duong dan toi riscv-tests/isa}
OUT=${2:-isa_hex}
PAT=${3:-rv32ui-p-*}
PFX=${PFX:-riscv64-unknown-elf}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"; : > "$OUT/list.txt"
for elf in "$ISA"/$PAT; do
    case "$elf" in *.dump|*.hex|*.bin) continue;; esac
    name=$(basename "$elf")
    $PFX-objcopy -O binary "$elf" "$OUT/$name.bin"
    python3 "$HERE/bin2hex_2.py" "$OUT/$name.bin" "$OUT/$name.hex" 16384 > /dev/null
    tohost=$($PFX-nm "$elf" | awk '$3=="tohost"{print $1}')
    echo "$name $tohost" >> "$OUT/list.txt"
    rm "$OUT/$name.bin"
done
echo "$(wc -l < "$OUT/list.txt") test -> $OUT/"