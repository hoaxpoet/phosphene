#!/usr/bin/env python3
"""Inject per-tensor sha256 into the stem (Open-Unmix HQ) weight manifest (CLEAN.5.5b).

Lean path: hash the *committed* .bin files (the bytes that ship, already in
LFS) and write the digest into each manifest entry. Does NOT re-run the umx
extraction — a fresh extraction could produce subtly different bytes; we pin
what ships. The beat_this manifest already carries sha256 (written by
Scripts/convert_beatthis_weights.py); this is the stem-side equivalent.

Usage:
    tools/add_stem_weight_checksums.py            # write digests into the manifest
    tools/add_stem_weight_checksums.py --check    # verify, exit 1 on any mismatch/missing

Hex is lowercase, no separators (matches `shasum -a 256` and Swift CryptoKit).
"""
import hashlib
import json
import sys
from pathlib import Path

WEIGHTS_DIR = Path(__file__).resolve().parent.parent / "PhospheneEngine/Sources/ML/Weights"
MANIFEST = WEIGHTS_DIR / "manifest.json"


def sha256_hex(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    check = "--check" in sys.argv[1:]
    manifest = json.loads(MANIFEST.read_text())
    tensors = manifest["tensors"]

    problems = []
    for key, entry in tensors.items():
        digest = sha256_hex(WEIGHTS_DIR / entry["file"])
        if check:
            if entry.get("sha256") != digest:
                problems.append(f"  {key}: manifest={entry.get('sha256')} actual={digest}")
        else:
            entry["sha256"] = digest

    if check:
        if problems:
            print(f"sha256 check FAILED for {len(problems)} tensor(s):")
            print("\n".join(problems))
            return 1
        print(f"sha256 check OK: {len(tensors)} stem tensors match.")
        return 0

    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Wrote sha256 for {len(tensors)} stem tensors into {MANIFEST.name}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
