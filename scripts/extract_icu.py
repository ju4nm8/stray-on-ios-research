#!/usr/bin/env python3
"""Extract ONLY the UE ICU data tree from a Stray pak, preserving relative paths.

Usage: extract_icu.py <pak> <out_root>
Writes <out_root>/StrayICU/icudt64l/... and a manifest with sizes + sha256.
"""
import hashlib, os, sys
import repak

PAK = sys.argv[1]
OUT = sys.argv[2]
PREFIX = "Engine/Content/Internationalization/icudt64l/"
ROOT = os.path.join(OUT, "StrayICU", "icudt64l")

r = repak.PakBuilder().reader(PAK)
entries = sorted(x for x in r.files() if x.startswith(PREFIX))
print(f"entries found: {len(entries)}")
os.makedirs(ROOT, exist_ok=True)
manifest = []
total = 0
for i, e in enumerate(entries, 1):
    rel = e[len(PREFIX):]
    dest = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    r.read_file(e, dest)
    data = open(dest, "rb").read()
    total += len(data)
    manifest.append(f"{hashlib.sha256(data).hexdigest()}  {len(data):>9}  icudt64l/{rel}")
    if i % 500 == 0 or i == len(entries):
        print(f"  {i}/{len(entries)} files, {total/1e6:.2f} MB")
with open(os.path.join(OUT, "manifest_sha256.txt"), "w") as f:
    f.write("\n".join(manifest) + "\n")
print(f"done: {len(entries)} files, {total} bytes")
print(f"manifest: {os.path.join(OUT, 'manifest_sha256.txt')}")
