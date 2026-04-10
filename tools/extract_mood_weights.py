#!/usr/bin/env python3
"""
Extract MoodClassifier weights from CoreML .mlpackage and emit Swift source.

The CoreML weight.bin uses a per-blob format:
  - 64-byte file header
  - Per tensor: 64-byte blob header (magic=0xDEADBEEF) + Float16 data

The last bias (net.6.bias, 2 values) is stored inline in the protobuf
as raw bytes rather than in the blob file.

Usage:
    python tools/extract_mood_weights.py

Output: Swift static [Float] arrays printed to stdout.
"""

import os
import struct
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

MLPACKAGE_DIR = os.path.join(
    PROJECT_ROOT,
    "PhospheneEngine", "Sources", "ML", "Models", "MoodClassifier.mlpackage",
    "Data", "com.apple.CoreML",
)
WEIGHT_BIN = os.path.join(MLPACKAGE_DIR, "weights", "weight.bin")

# Blob layout (validated by inspecting protobuf spec):
# Each blob has a 64-byte header, then Float16 data.
BLOB_LAYERS = [
    # (swift_name, blob_offset, element_count, shape)
    ("w0", 64, 640, (64, 10)),
    ("b0", 1408, 64, (64,)),
    ("w1", 1600, 2048, (32, 64)),
    ("b1", 5760, 32, (32,)),
    ("w2", 5888, 512, (16, 32)),
    ("b2", 6976, 16, (16,)),
    ("w3", 7104, 32, (2, 16)),
]

# net.6.bias is stored inline in protobuf as 4 raw bytes (2 Float16 values).
B3_RAW_BYTES = bytes([255, 43, 78, 26])


def read_blob_f16(data: bytes, offset: int, count: int) -> list[float]:
    """Read `count` Float16 values from blob at `offset` (skipping 64-byte header)."""
    start = offset + 64
    raw = data[start : start + count * 2]
    return list(struct.unpack(f"<{count}e", raw))


def format_swift_array(name: str, vals: list[float], shape: tuple) -> str:
    """Format a list of floats as a Swift static array declaration."""
    lines = []
    lines.append(f"    // shape {list(shape)}, {len(vals)} values")
    lines.append(f"    private static let {name}: [Float] = [")

    if len(shape) == 2:
        rows, cols = shape
        for r in range(rows):
            row_vals = vals[r * cols : (r + 1) * cols]
            formatted = ", ".join(f"{v: .6f}" for v in row_vals)
            comma = "," if r < rows - 1 else ""
            lines.append(f"        {formatted}{comma}")
    else:
        # Format in rows of 10
        for i in range(0, len(vals), 10):
            chunk = vals[i : i + 10]
            formatted = ", ".join(f"{v: .6f}" for v in chunk)
            comma = "," if i + 10 < len(vals) else ""
            lines.append(f"        {formatted}{comma}")

    lines.append("    ]")
    return "\n".join(lines)


def main():
    if not os.path.exists(WEIGHT_BIN):
        print(f"Error: {WEIGHT_BIN} not found", file=sys.stderr)
        sys.exit(1)

    with open(WEIGHT_BIN, "rb") as f:
        data = f.read()

    print("    // MARK: - Weights (extracted from MoodClassifier.mlpackage)")
    print()

    for swift_name, offset, count, shape in BLOB_LAYERS:
        vals = read_blob_f16(data, offset, count)
        print(format_swift_array(swift_name, vals, shape))
        print()

    # b3 from inline protobuf bytes
    b3_vals = list(struct.unpack("<2e", B3_RAW_BYTES))
    print(format_swift_array("b3", b3_vals, (2,)))
    print()

    total = sum(count for _, _, count, _ in BLOB_LAYERS) + 2
    print(f"    // Total: {total} parameters")


if __name__ == "__main__":
    main()
