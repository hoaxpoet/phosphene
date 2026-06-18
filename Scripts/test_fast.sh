#!/usr/bin/env bash
#
# test_fast.sh — the FAST test tier (CLEAN.7.2a).
#
# A quick, broad pure-logic signal for the inner dev loop: ~978 of the ~1,524 engine
# tests (DSP / Orchestrator / Shared / Session-logic / Audio-core / Doc gates) in
# ~13 s of test time — and GREEN in a git worktree, because it skips the audio-fixture
# suites that fail-loud when the gitignored fixtures (love_rehab.m4a, …) are absent.
#
# This is NOT the gate. The full `swift test --package-path PhospheneEngine` (run by
# Scripts/closeout_evidence.sh) stays the merge / closeout gate and runs everything,
# including the GPU / ML / fixture / visual / perf / integration / soak suites skipped
# here. For a tighter, targeted loop, prefer:
#     swift test --package-path PhospheneEngine --filter <SuiteName>
#
# Mechanism: exclusion by `swift test --skip <regex>` (matches swift-testing display
# names AND XCTest class names). It is a CURATED skip-list — the full run is the source
# of truth. ponytail: exclusion-based, so a NEW heavy suite is not auto-skipped; when you
# add a slow GPU/ML/fixture/visual suite, add its name fragment to the right group below.

set -euo pipefail

# Heavy / environment-dependent suites, grouped by why they're slow. Joined with `|`.
SKIP_PATTERNS=(
  # GPU / Metal renderer (need the device; slower, and don't run headless in CI)
  "SSGI" "RayIntersect" "RayMarch" "MVWarp" "RenderPipeline" "MeshGenerator"
  "BVHBuilder" "ProceduralGeometry" "PostProcessChain" "SpectralCartograph"
  "MetalContext" "ShaderLibrary" "IBL" "SceneUniforms" "FeatureVectorExtended"
  "ShaderUtility" "NoiseUtility" "PBRUtility" "NoiseTestHarness" "DrawableResize"
  # ML model inference (Open-Unmix / Beat This! — seconds of real graph work)
  "BeatThis" "StemSeparator" "StemModel" "StemFFT"
  # audio-fixture-dependent (gitignored fixtures; fail loud in worktrees, slow elsewhere)
  "LiveDrift" "LiveBeatDrift" "BeatGridAccuracy" "PreviewAudio" "loveRehab" "love_rehab"
  "Churn"
  # preset visual / fidelity (GPU + the 2,477-line Skein canvas-hold long pole)
  "Skein" "Ferrofluid" "Dragon Bloom" "DragonBloom" "Nimbus" "Fata" "Lumen"
  "Murmuration" "Arachne" "PresetVisualReview" "Fidelity Rubric"
  "Photosensitivity" "flash-safe" "Multi-Pass Flash"
  # slow infra (perf gates, integration, memory/concurrency soak, disk cache)
  "Performance" "Integration" "Soak" "Concurrency stress" "PersistentStemCache"
  # network-timeout timing tests (real waits on URLProtocol stubs)
  "MetadataPreFetcher" "StreamingMetadata" "PreviewDownloader" "PreviewResolver"
)

SKIP="$(IFS='|'; echo "${SKIP_PATTERNS[*]}")"

echo "[test_fast] FAST tier — pure-logic core, ~13s. NOT the gate."
echo "[test_fast] Full gate: Scripts/closeout_evidence.sh  |  Targeted: swift test … --filter <Suite>"
echo ""

exec swift test --package-path PhospheneEngine --skip "$SKIP"
