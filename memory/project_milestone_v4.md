---
name: Phase V progress — V.4 complete
description: Phase V shader utility library status after Increment V.4
type: project
---

Phase V through V.4 complete (2026-04-26). Next increment is V.5 (Visual References library + quality reel).

V.4 delivered:
- SHADER_CRAFT.md audit: 12 drift items resolved, §4.10–§4.20 all upgraded to full Metal blocks
- 3 missing materials added: mat_velvet (Organic.metal §4.12), mat_sand_glints (Exotic.metal §4.19), mat_concrete (Dielectrics.metal §4.20)
- UtilityPerformanceHarness + UtilityPerformanceTests (24 GPU-timestamp benchmarks, PERF_TESTS=1 gated)
- UtilityCostTableUpdater CLI (sentinel-bounded §9.4 table update)
- docs/V4_PERF_RESULTS.json with initial estimates
- SHADER_CRAFT.md §9.4 two-column performance table
- D-063 in DECISIONS.md

**Why:** Track what's done so future sessions know the library is complete through V.4.

**How to apply:** When starting shader authoring work, all utility functions through V.4 are available. V.5 is next: per-preset visual reference folders under docs/VISUAL_REFERENCES/.
