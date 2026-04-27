---
name: Metal hash API — use hash_f01_3 for 3D positions
description: hash_f01(uint) is scalar-only; 3D world-space positions require hash_f01_3(float3)
type: feedback
---

Always use `hash_f01_3(float3 p)` when hashing 3D world-space positions in Metal shaders. `hash_f01(uint x)` only accepts a single `uint` — passing `uint3` or `float3` will produce a compile error.

**Why:** mat_sand_glints initially used `hash_f01(uint3(abs(wp * 500.0)))` which failed with "no matching function for call to 'hash_f01'; no known conversion from 'uint3' to 'uint'". The correct function `hash_f01_3` is defined in Noise/Hash.metal.

**How to apply:** In any Metal shader that needs a per-cell hash from a 3D world position, write `hash_f01_3(floor(wp * scale))`. The `floor()` before passing to `hash_f01_3` ensures integer cell snapping.
