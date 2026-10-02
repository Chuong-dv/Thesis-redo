#!/usr/bin/env python3
"""Doi file KAT cua Ascon (LWC_AEAD_KAT_*.txt) thanh file phang cho testbench SV doc bang $fscanf.

Moi vector 1 dong:  key nonce adlen ptlen ad pt ct tag
  - key, nonce, ad, pt, ct, tag: so hex (byte dau tien = byte cao nhat)
  - truong rong duoc ghi la 0 (do dai da co o adlen/ptlen)
  - ct = ciphertext (ptlen byte), tag = 16 byte cuoi cua truong CT trong file KAT
Script CHI chep va tach truong, khong tinh toan gi -> dap an van la cua KAT.
"""
import argparse

def parse(path):
    vecs, cur = [], {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                if cur:
                    vecs.append(cur); cur = {}
                continue
            k, _, v = line.partition("=")
            cur[k.strip()] = v.strip()
    if cur:
        vecs.append(cur)
    return vecs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kat"); ap.add_argument("out")
    ap.add_argument("--max-pt", type=int, default=32)
    ap.add_argument("--max-ad", type=int, default=32)
    a = ap.parse_args()

    n = 0
    with open(a.out, "w") as o:
        for v in parse(a.kat):
            key, nonce = v["Key"], v["Nonce"]
            pt, ad, ctt = v.get("PT", ""), v.get("AD", ""), v["CT"]
            ptlen, adlen = len(pt) // 2, len(ad) // 2
            assert len(ctt) // 2 == ptlen + 16, f"Count {v.get('Count')}: CT khong = PT + 16 byte"
            if ptlen > a.max_pt or adlen > a.max_ad:
                continue
            assert ptlen <= 32 and adlen <= 32, "testbench chi ho tro toi da 32 byte"
            ct, tag = ctt[:2 * ptlen], ctt[2 * ptlen:]
            o.write(f"{key} {nonce} {adlen} {ptlen} {ad or '0'} {pt or '0'} {ct or '0'} {tag}\n")
            n += 1
    print(f"da ghi {n} vector vao {a.out}")

if __name__ == "__main__":
    main()
