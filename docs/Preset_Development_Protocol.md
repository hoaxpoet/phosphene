# Phosphene Preset Development Protocol

Every complex preset must pass through these gates before implementation.

## Gate 0 — Intake completeness

Required inputs:
- Preset name
- Preset family
- Intended emotional / musical role
- Reference images
- Reference README
- Anti-references
- Audio-reactive intent
- Performance target
- Target render pipeline
- Known constraints

If any are missing, stop and ask for clarification.

## Gate 1 — Reference trait extraction

Before coding, extract:

- Macro composition traits
- Meso structure traits
- Micro-detail traits
- Material traits
- Lighting traits
- Motion traits
- Audio-reactive traits
- Failure modes
- Anti-reference warnings

Output a trait matrix.

## Gate 2 — Renderer capability audit

Before coding, determine whether the engine supports the required primitives.

Examples:
- offscreen render targets
- multi-pass composition
- screen-space refraction
- SDF line fields
- particle fields
- volumetric fog
- blur/focus treatment
- texture sampling
- normal estimation
- lighting model
- material functions
- temporal state
- visual harness captures
- audio feature access

If a required primitive is missing, do not implement the preset yet.

## Gate 3 — Gap report

For each missing capability, classify:

- Blocking
- High priority
- Nice to have
- Not needed

Blocking gaps must be resolved before preset implementation.

## Gate 4 — Rendering architecture contract

Define the pass structure, materials, state model, audio routing, debug views, and acceptance criteria.

## Gate 5 — Phased implementation

Implement in small phases. Each phase must produce visual harness artifacts.

No phase is accepted merely because it “looks better.”

## Gate 6 — Certification

Certify against:
- hero references
- anti-references
- silence fixture
- steady fixture
- beat-heavy fixture
- performance budget
- architecture constraints