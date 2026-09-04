#!/bin/bash
# Tight loop of the 1080p ray-march frame-budget meter for $1 seconds.
# Direct xctest invocation (~1.2 s per pass) so the GPU never idles between
# passes — the 5x-`swift test` version measured clock ramp-up, not contention.
DUR=${1:-90}
B=UzumeEngine/.build/debug/UzumeEnginePackageTests.xctest
END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
  xcrun xctest -XCTest UzumeEngineTests.RayMarchPipelineTests/test_fullPipeline_under8ms_at1080p "$B" 2>&1 \
  | grep -o 'values: \[[^]]*\]' | sed 's/values: \[//; s/\]//; s/, /\n/g' \
  | awk '{printf "%.3f\n", $1*1000}'
done
