# hg_sdf Vendoring — Increment Spec (SDF.1)

**Goal:** Vendor Mercury's `hg_sdf` as a shared Metal SDF operator library injected into every preset's shader preamble, then prove it by refactoring one existing ray-march preset to use it. Flips RENDERER capability **SDF authoring: Missing → Supported**.

**Why:** No shared SDF operators exist today — every ray-march preset rolls its own `sceneSDF`, and smooth-min lives only as a stray Quilez constant in Ferrofluid (per the 2026-06-29 audit). This is purely additive and immediately upgrades Glass Brutalist, Kinetic Sculpture, Lumen Mosaic, Volumetric Lithograph, and Ferrofluid (richer booleans/bevels, domain repetition), plus the Lipschitz discipline that targets the FA #64 dot-pattern class.

**Build boundary:** This is a Metal/Swift change — build, lint, and the `RENDER_VISUAL` harness run on macOS + Xcode + Apple Silicon (`xcodebuild -scheme PhospheneApp …`). It cannot be compiled in the Cowork Linux sandbox. This document is the hand-off; do the wholesale port + compile on the Mac (FA #73 — port the reference wholesale).

---

## 1. License (take the MIT option)

`hg_sdf` is dual-licensed **MIT OR CC-BY-NC-4.0** (verified at https://mercury.sexy/hg_sdf/, version line 2021-07-28). Take **MIT** so it's compatible with MIT-licensed Phosphene. Retain the original copyright + MIT notice as a header comment in the vendored file. Source of truth to port from: https://mercury.sexy/hg_sdf/hg_sdf.glsl (download on the Mac; it served as binary to the sandbox fetcher).

## 2. Placement & wiring

- Add a new utility tree, e.g. `PhospheneEngine/Sources/Presets/Utilities/SDF/hg_sdf.metal` (mirror the existing `Utilities/Volume`, `Utilities/Geometry`, `Utilities/PBR`, `Utilities/Noise` convention).
- Register it in the preamble loader: `PresetLoader+Preamble.swift` already does `loadUtilityDirectory("Utilities/Volume", …)` etc. (audit ref). Add the SDF tree to that load list. **Inject it before any preset `sceneSDF`** — the preamble is prepended, so order matters.
- `.metal` `file_length` lint is relaxed (SHADER_CRAFT §11.1), so a long single header is fine — don't split for lint.

## 3. GLSL → MSL translation checklist (the gotchas)

Port mechanically, but these are the traps that won't "just work":

1. **Types:** `vec2/3/4 → float2/3/4`, `mat2/3/4 → float2x2/3x3/4x4`, `vecN(0) → floatN(0.0)`.
2. **`inout` → `thread T&`.** Every `pMod*`/`pReflect`/`pR` takes `inout` — becomes a `thread&` reference param in MSL. Call sites are unchanged (pass the lvalue).
3. **`mod()` semantics.** GLSL `mod` is floored; MSL `fmod` truncates toward zero → wrong for negative coords (i.e. all the domain-repeat ops). **Define a floored `gmod` helper and use it everywhere hg_sdf uses `mod`.** This is the single most important gotcha — get it wrong and `pMod*` mirrors break on one side of the origin.
4. **`atan(y, x) → atan2(y, x)`** (used in `pModPolar`).
5. **`inversesqrt → rsqrt`.**
6. **Matrix construction is column-major in both, but syntax differs.** GLSL `mat2(a,b,c,d)` = columns `(a,b),(c,d)`; MSL `float2x2(float2(a,b), float2(c,d))`. Translate rotations explicitly and **verify handedness with a visual** (a rotated box should rotate the expected direction).
7. **Scalar literal strictness:** MSL won't promote `int`→`float` as loosely; write `0.0`, `2.0`, `0.5`.
8. **Symbol collisions.** The preamble concatenates multiple utility trees — if `Noise`/`Geometry`/`PBR` already define `PI`, `mod`, `sgn`, `saturate`, `rotate`, `pR`, a second definition is a compile error. **Grep the existing preamble trees first; prefix hg_sdf's helpers (`hg_`/`HG_`) or `#ifndef`-guard** to avoid redefinition. Don't assume a clean namespace.
9. **Precision:** keep `float` (not `half`) to match the ray-march preamble context.

## 4. Verified translation pattern (anchor the port to this)

These are ported correctly — use them as the idiom for the rest. Port the remaining operators from canonical `hg_sdf.glsl` following this exact pattern, compiling as you go.

```metal
// hg_sdf — Metal port. Original (c) Mercury, MIT option. https://mercury.sexy/hg_sdf/
#define HG_PI 3.14159265359

inline float hg_sgn(float x) { return x < 0.0 ? -1.0 : 1.0; }
inline float2 hg_sgn(float2 v) { return float2(v.x < 0.0 ? -1.0 : 1.0, v.y < 0.0 ? -1.0 : 1.0); }

// GLSL-floored mod (MSL fmod truncates — wrong for negatives). Use THIS wherever hg_sdf uses mod().
inline float  hg_mod(float x, float y)  { return x - y * floor(x / y); }
inline float2 hg_mod(float2 x, float y) { return x - y * floor(x / y); }

inline float hg_vmax(float3 v) { return max(max(v.x, v.y), v.z); }

// --- primitives ---
inline float fSphere(float3 p, float r) { return length(p) - r; }

inline float fBox(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return length(max(d, float3(0.0))) + hg_vmax(min(d, float3(0.0)));
}

// --- boolean: rounded union (the smooth-min already in use) ---
inline float fOpUnionRound(float a, float b, float r) {
    float2 u = max(float2(r - a, r - b), float2(0.0));
    return max(r, min(a, b)) - length(u);
}

// --- boolean: chamfer union (a different bevel aesthetic) ---
inline float fOpUnionChamfer(float a, float b, float r) {
    return min(min(a, b), (a - r + b) * sqrt(0.5));
}

// --- domain: repeat along one axis, returns cell index ---
inline float pMod1(thread float& p, float size) {
    float halfsize = size * 0.5;
    float c = floor((p + halfsize) / size);
    p = hg_mod(p + halfsize, size) - halfsize;   // hg_mod, NOT fmod
    return c;
}

// --- domain: polar repeat (radial symmetry) ---
inline float pModPolar(thread float2& p, float repetitions) {
    float angle = 2.0 * HG_PI / repetitions;
    float a = atan2(p.y, p.x) + angle * 0.5;      // atan2, NOT atan
    float r = length(p);
    float c = floor(a / angle);
    a = hg_mod(a, angle) - angle * 0.5;
    p = float2(cos(a), sin(a)) * r;
    if (abs(c) >= (repetitions * 0.5)) c = abs(c);
    return c;
}
```

## 5. Coverage to port (wholesale)

Port all of canonical hg_sdf, but the net-new value over today's codebase is:
- **Booleans:** `fOpUnionRound/Chamfer/Columns/Stairs`, `fOpIntersection*`, `fOpDifference*`, `fOpPipe`, `fOpGroove`, `fOpEngrave`, `fOpTongue`. (Columns/Stairs/Groove are the subtle ones — port from canonical carefully, they have multi-branch logic.)
- **Domain:** `pMod1/2/3`, `pModInterval1`, `pModPolar`, `pModMirror2`, `pReflect`, `pR` (2D rotate), `pModSingle1`.
- **Primitives:** sphere, box, rounded box, torus, cylinder, capsule, cone, plane, hexagon, etc.

## 6. Proof of integration (required — additive isn't enough; prove it in use)

Refactor **one** existing hard-surface ray-march preset (Glass Brutalist or Kinetic Sculpture are good fits) to consume an hg_sdf operator — e.g. replace a hand-rolled smooth-union with `fOpUnionRound`, or add a `pModPolar` radial repeat. Prove **no visual regression** with a `RENDER_VISUAL=1` contact sheet (before/after). This validates the injection wiring and the operator semantics on a real scene.

## 7. Closeout gates (per CLAUDE.md increment protocol)

- `xcodebuild -scheme PhospheneApp build` clean (warnings-as-errors via xcconfig).
- `swift test --package-path PhospheneEngine` + `xcodebuild test` all pass (regression gate).
- `swiftlint lint --strict` clean.
- `RENDER_VISUAL=1` contact sheet attached (proof-preset before/after).
- **Update `docs/CAPABILITY_REGISTRY/RENDERER.md`:** SDF authoring Missing → Supported, cite the new file + the proof-preset.
- `docs/ENGINEERING_PLAN.md` increment row (SDF.1, done-when = injected + one preset consuming it + registry flipped).
- `docs/RELEASE_NOTES_DEV.md` entry.
- `Scripts/closeout_evidence.sh` block in the closeout report.
- Commit `[SDF.1] Presets: vendor hg_sdf SDF operator library`. **Do not push without Matt's approval.**

## 8. Risks / watch-items

- **Symbol collisions** with existing preamble trees (gotcha #8) — most likely first compile failure.
- **`hg_mod` correctness** (gotcha #3) — verify a `pMod1` mirror is symmetric across the origin.
- **Matrix handedness** (gotcha #6) — verify with a rotation visual.
- **Preamble size/compile time** — injecting a large header into every preset preamble; confirm no measurable shader-compile regression at session start.
- Keep it a **pure addition** — do not refactor more than the single proof-preset in SDF.1 (scope discipline). Broader adoption is follow-on increments.
