---
name: Test suite baseline
description: Current passing test count and known pre-existing failures; a new failure is a regression
type: project
---

419 tests total (415 prior + 4 from Increment 5.2 PresetAcceptanceTests), 4 pre-existing Apple Music environment failures. Any 5th failure is a regression that must be investigated before merging.

Note: Swift Testing counts @Test function declarations, not parametrized cases. The 4 acceptance tests each run against 11 presets via @Test(arguments:), but Swift Testing reports them as 4 tests.

**Why:** The Apple Music failures require a running instance of Apple Music — they are environmental, not code failures. All other tests must pass.

**How to apply:** After any code change, run `swift test --package-path PhospheneEngine` and confirm the count is 419 with ≤ 4 failures. A new failure (5th+) is a regression.
