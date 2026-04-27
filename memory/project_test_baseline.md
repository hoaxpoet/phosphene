---
name: Test suite baseline
description: Current passing test count and known pre-existing failures; a new failure is a regression
type: project
---

830 engine tests (84 suites) after Increment V.4. Known flaky tests:
- **MemoryReporter** — "residentBytes grows by ≥ 5 MB" fails intermittently; macOS memory compression can suppress apparent physical-footprint growth for a 10 MB allocation. Environmental, not a code failure.
- **MetadataPreFetcher / PreviewResolver** — timing-sensitive; require network or run too fast in CI.

Any new failure beyond these is a regression that must be investigated before merging.

Note: Swift Testing counts @Test function declarations, not parametrized cases. Acceptance tests run against 11 presets via @Test(arguments:) but count as 4 @Test functions.

**Why:** The pre-existing failures are environmental (memory compression, network, Apple Music presence). All other tests must pass.

**How to apply:** After any code change, run `swift test --package-path PhospheneEngine` and confirm count is 830 with failures limited to the known flakes above.
