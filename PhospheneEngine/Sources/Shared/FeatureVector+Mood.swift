// FeatureVector+Mood — safe unipolar readings of the BIPOLAR mood primitives (BUG-094).
//
// `valence` and `arousal` are declared −1…+1. A consumer that wants a 0…1 envelope must MAP
// that range, not clamp it:
//
//     let lift = max(0, min(features.arousal, 1))   // ← WRONG: discards the entire calm half
//     let lift = features.arousal01                 // ← right
//
// **This is not hypothetical.** Meniscus wrote the first form in two places
// (`MeniscusStemDrops` drop density and `MeniscusCamera` dolly), and on calm material it cost
// the preset a whole region: measured on `so_what` (quiet modal jazz) arousal runs
// −0.393…+0.519 with **35 % of frames negative**, all collapsing to zero, until the
// backbeat-gated vocals region placed **0 drops across the entire track**. It stayed hidden
// because MEN.4a was calibrated on one capture where arousal never went negative.
//
// The clamp is not always wrong — `max(0, valence)` / `max(0, -valence)` in
// `RayMarchPipeline+MetalFX` deliberately splits the bipolar signal into two unipolar channels
// and loses nothing, and the `*Dev` family is `max(0, *Rel)` by definition. The rule is
// narrower than "avoid `max(0,)`": **do not clamp a bipolar primitive to one side of zero and
// then treat the result as its full range.**

import Foundation

extension FeatureVector {

    /// `arousal` mapped from its declared −1…+1 onto 0…1, preserving both halves.
    ///
    /// Use this for any 0…1 envelope driven by arousal. The orchestrator uses a deliberately
    /// COMPRESSED variant (`0.5 + 0.4 · x`, `PresetScorer` / `SessionPlanner`) because scoring
    /// wants headroom at both ends; a visual envelope wants the full span, so this is the
    /// straight map.
    public var arousal01: Float { (max(-1, min(arousal, 1)) + 1) * 0.5 }

    /// `valence` mapped from its declared −1…+1 onto 0…1, preserving both halves.
    /// No consumer yet — added alongside `arousal01` because it carries the identical hazard
    /// and a future reader reaching for one will look for the other.
    public var valence01: Float { (max(-1, min(valence, 1)) + 1) * 0.5 }
}
