#!/usr/bin/env python3
"""bin2hex.py in.bin out.hex [max_words]: moi dong 1 word 32 bit (little-endian), dung cho $readmemh."""
import sys, struct
data = open(sys.argv[1], "rb").read()
data += b"\x00" * (-len(data) % 4)
words = struct.unpack("<%dI" % (len(data) // 4), data)
max_words = int(sys.argv[3]) if len(sys.argv) > 3 else 2048     # mac dinh: RAM 8 KB
if len(words) > max_words:
    sys.exit(f"firmware {len(words)*4} byte > {max_words*4} byte")
with open(sys.argv[2], "w") as f:
    for w in words:
        f.write("%08x\n" % w)
print(f"{len(words)*4} byte, {len(words)} word -> {sys.argv[2]}")
