// ArachneState+Spider — Sub-bass easter egg gait solver and GPU buffer (Increment 3.5.9).
//
// The spider materialises as a rare reward (≤ once per Arachne segment) triggered
// by sustained sub-bass with low attack ratio — distinguishing deep resonant bass
// (James Blake, Burial) from transient kick drums.
//
// V.7.7C.2 (D-095): the V.7.5 300 s session cooldown is REPLACED by a per-segment
// guard (`spiderFiredInSegment`). At most one spider appearance per Arachne
// segment; the flag is reset only by `ArachneState.reset()`. The V.7.5
// sustained-bass conditions are preserved on top of the new guard.
//
// ArachneSpiderGPU (80 bytes) is bound at fragment buffer(7) in the mv_warp/direct
// fragment pass and consumed by the spider SDF in arachne_fragment.
// (D-040 originally specified buffer(4)/meshPresetFragmentBuffer; the buffer moved
// to buffer(7)/directPresetFragmentBuffer2 in the ray-march remaster, Increment 3.5.10.)
//
// Trigger (V.7.5 §10.1.9, restoring D-040 + re-tuned per M7 data; per-segment gate per V.7.7C.2):
//   features.subBass > 0.30
//   AND stems.bassAttackRatio ∈ (0, 0.55)
//   held continuously for ≥ 0.75 s
//   AND !spiderFiredInSegment   (V.7.7C.2 / D-095 — replaces V.7.5's 300 s session timer)
//
// History: D-040 specified an attack-ratio gate; pre-V.7.5 it was removed on the
// theory that the 0.75 s sustain accumulator alone debounces kicks. M7 capture
// session 2026-05-01T22-14-25Z showed the threshold was unreachable in live
// AGC for the originally-targeted James Blake "Limit to Your Love" — max
// sustained subBass > 0.65 was 0.43 s, never the 0.75 s required. Re-tuning
// to 0.30 brings the threshold back into the reachable distribution; restoring
// the AR gate provides the kick-debounce that the lower threshold loses.

import Metal
import os.log
import Shared
import simd

private let spiderLogger = Logger(subsystem: "com.phosphene.presets", category: "ArachneSpider")

// MARK: - ArachneSpiderGPU

/// GPU-side spider descriptor — 80 bytes.
///
/// Layout: 4 × Float (16 B header) + 8 × SIMD2<Float> leg tips (64 B).
/// Must match `ArachneSpiderGPU` in Arachne.metal byte-for-byte.
public struct ArachneSpiderGPU: Sendable {
    /// 0 = absent, 1 = fully materialised.
    public var blend: Float
    /// Clip-space body centre X.
    public var posX: Float
    /// Clip-space body centre Y.
    public var posY: Float
    /// Spider orientation (radians).
    public var heading: Float
    // 8 leg tip positions in clip space (tuple = contiguous memory = matches MSL float2[8]).
    public var tip0: SIMD2<Float>
    public var tip1: SIMD2<Float>
    public var tip2: SIMD2<Float>
    public var tip3: SIMD2<Float>
    public var tip4: SIMD2<Float>
    public var tip5: SIMD2<Float>
    public var tip6: SIMD2<Float>
    public var tip7: SIMD2<Float>

    public static let zero = ArachneSpiderGPU(
        blend: 0,
        posX: 0,
        posY: 0,
        heading: 0,
        tip0: .zero,
        tip1: .zero,
        tip2: .zero,
        tip3: .zero,
        tip4: .zero,
        tip5: .zero,
        tip6: .zero,
        tip7: .zero
    )
}

// MARK: - ArachneSpiderDiag

/// Read-only snapshot of spider trigger and render state for debug overlay.
public struct ArachneSpiderDiag: Sendable {
    /// Sustained sub-bass accumulator — counts up to 0.75 s then fires.
    public let accumulator: Float
    /// Current blend value (0 = absent, 1 = fully visible).
    public let blend: Float
    /// V.7.7C.2: 0 if the spider can still fire this segment, 1 if it has
    /// already fired (per-segment cooldown gate; resets at `reset()`).
    /// Pre-V.7.7C.2 this field carried "seconds until session cooldown elapses";
    /// the V.7.7C.2 per-segment semantic supersedes that. The debug overlay's
    /// "cooldown" label still reads this field; non-zero means "spider has
    /// already fired in this segment".
    public let cooldownRemaining: Float
    /// Whether the force-trigger is active (DEBUG builds only; always false in Release).
    public let isForced: Bool
}

// MARK: - Spider extension

extension ArachneState {

    // MARK: - Spider Constants

    /// Seconds of sustained sub-bass required to trigger the spider.
    static let sustainedTriggerThreshold: Float = 0.75
    /// Pre-V.7.7C.2 V.7.5 session-cooldown duration. **Deprecated** —
    /// superseded by the per-segment `spiderFiredInSegment` guard
    /// (D-095 / §6.5). Retained as a no-op constant so the
    /// `ARACHNE_M7_DIAG` build's logging line continues to compile.
    static let sessionCooldownDuration: Float = 300.0
    /// Sub-bass energy level gate — AGC-normalised FV subBass (20–80 Hz).
    /// V.7.5 §10.1.9 / D-071: re-tuned from 0.65 → 0.30 after M7 session
    /// 2026-05-01T22-14-25Z showed f.subBass mean ≈ 0.13 in LTYL with sustained
    /// values up to ~0.30 (14.8 % of frames). The original 0.65 threshold from
    /// D-040 — based on an assumption that LTYL hits 3.9–5.9 at the drop — was
    /// unreachable in live AGC. Lowering the threshold reopens the trigger;
    /// the restored AR gate (bassAttackRatio < 0.55) supplies the kick debounce.
    static let subBassThreshold: Float = 0.30
    /// Seconds to blend blend 0→1 on materialisation.
    static let spiderFadeInDuration: Float = 2.0
    /// Seconds to blend blend 1→0 on dematerialisation.
    static let spiderFadeOutDuration: Float = 2.0
    /// Clip-space radius of the resting leg spread.
    static let spiderLegRadius: Float = 0.26
    /// Gait cycles per second (alternating-tetrapod).
    static let spiderGaitRate: Float = 1.5

    // MARK: - Spider Update (called from _tick while lock is held)

    /// Advance spider state by one frame. Call from `_tick` while holding the lock.
    func updateSpider(dt: Float, features: FeatureVector, stems: StemFeatures) {
        // Sub-bass trigger: AGC-normalised FV subBass (20–80 Hz). stems.bassEnergy is
        // unreliable for deep electronic sub-bass (Open-Unmix attributes 40–60 Hz to
        // "other", not "bass"), so the FV band remains the energy source.
        //
        // V.7.5 §10.1.9 / D-040 / D-071: AR gate restored. bassAttackRatio < 0.55
        // distinguishes sustained resonant bass from transient kick drums whose
        // attack ratio is closer to 1.0. The > 0 check guards against zero-stem
        // frames before the warmup completes.
        let conditionMet = features.subBass > Self.subBassThreshold
                        && stems.bassAttackRatio > 0.0
                        && stems.bassAttackRatio < 0.55

        if conditionMet {
            sustainedSubBassAccumulator += dt
        } else {
            sustainedSubBassAccumulator = max(sustainedSubBassAccumulator - 2.0 * dt, 0)
        }

        // V.7.7C.2 (D-095) §6.5: per-segment cooldown gate. The V.7.5 300 s
        // session timer is REPLACED by `spiderFiredInSegment` — at most one
        // spider appearance per Arachne segment; the flag resets only on
        // `ArachneState.reset()`.
        if !spiderActive
            && !spiderFiredInSegment
            && sustainedSubBassAccumulator >= Self.sustainedTriggerThreshold {
            activateSpider()
            let sbStr = String(format: "%.2f", features.subBass)
            spiderLogger.notice("[arachne.spider] organic trigger fired (per-segment)")
            spiderLogger.notice("  subBass=\(sbStr)")
        }

        // Dematerialise when the triggering condition no longer holds.
        if spiderActive && !conditionMet {
            spiderActive = false
        }

        // Blend fade in / out.
        if spiderActive {
            spiderBlend = min(spiderBlend + dt / Self.spiderFadeInDuration, 1.0)
        } else {
            spiderBlend = max(spiderBlend - dt / Self.spiderFadeOutDuration, 0.0)
        }

        // Force-override: applied after organic logic so organic state is fully preserved.
        // When forced, position is set once (no re-jitter on subsequent ticks) and blend is
        // pinned to 1.0. Turning force off lets the organic blend path take over naturally.
        #if DEBUG
        if forceSpiderActive {
            activateSpiderIfNeeded()
            spiderBlend = 1.0
        }
        #endif

        if spiderBlend > 0 { updateSpiderGait(dt: dt) }

        // V.7.7D listening pose runs after the gait so the lift uses up-to-date
        // tip positions when written to the GPU struct. Defined in
        // ArachneState+ListeningPose.swift; CPU-side only — shader contract
        // unchanged. D-094.
        updateListeningPose(features: features, stems: stems, dt: dt)
    }

    // MARK: - Private: activation

    private func activateSpider() {
        spiderActive = true
        spiderFiredInSegment = true   // V.7.7C.2: per-segment guard latches on fire
        sustainedSubBassAccumulator = 0
        placeSpiderAtBestHub()
    }

    /// Position the spider at the most-opaque stable web hub, only when not already placed.
    /// Organic `spiderActive` flag and cooldown state are untouched.
    private func activateSpiderIfNeeded() {
        // Guard: spider already placed if position is non-zero (no stable web is at exact origin).
        guard spiderPosX == 0.0 && spiderPosY == 0.0 else { return }
        placeSpiderAtBestHub()
    }

    /// Set position + heading + leg tips from the best available stable web.
    private func placeSpiderAtBestHub() {
        var bestX: Float = 0, bestY: Float = 0, bestOpacity: Float = -1
        for web in webs where web.isAlive != 0 && WebStage(rawValue: web.stage) == .stable {
            if web.opacity > bestOpacity {
                bestOpacity = web.opacity
                bestX = web.hubX
                bestY = web.hubY
            }
        }
        spiderPosX    = bestOpacity >= 0 ? bestX : 0
        spiderPosY    = bestOpacity >= 0 ? bestY : 0
        spiderHeading = lcg(&rng) * .pi * 2
        spiderLegPhase = 0

        for idx in 0..<8 {
            let angle = spiderHeading + Float(idx) * (.pi * 2 / 8)
            spiderLegTips[idx] = SIMD2<Float>(
                spiderPosX + cos(angle) * Self.spiderLegRadius,
                spiderPosY + sin(angle) * Self.spiderLegRadius
            )
        }
    }

    // MARK: - Private: gait

    private func updateSpiderGait(dt: Float) {
        spiderLegPhase = (spiderLegPhase + dt * Self.spiderGaitRate)
            .truncatingRemainder(dividingBy: 1.0)

        // Alternating-tetrapod: Group A (even indices) and Group B (odd) offset by 0.5.
        // Swing phase occupies the last 25 % of each cycle — the foot plants toward rest.
        for idx in 0..<8 {
            let isGroupB = (idx & 1) != 0
            let phase = isGroupB
                ? (spiderLegPhase + 0.5).truncatingRemainder(dividingBy: 1.0)
                : spiderLegPhase

            if phase > 0.75 {
                let swingRaw = (phase - 0.75) / 0.25
                // Smoothstep easing for natural foot-plant motion.
                let easedT = swingRaw * swingRaw * (3 - 2 * swingRaw)
                let angle = spiderHeading + Float(idx) * (.pi * 2 / 8)
                let restTip = SIMD2<Float>(
                    spiderPosX + cos(angle) * Self.spiderLegRadius,
                    spiderPosY + sin(angle) * Self.spiderLegRadius
                )
                spiderLegTips[idx] += (restTip - spiderLegTips[idx]) * easedT
            }
            // During stance (phase 0–0.75) the tip remains planted.
        }
    }

    // MARK: - GPU write

    /// Flush spider state to `spiderBuffer`. Called from `tick` (outside lock).
    ///
    /// V.7.7D: applies the listening-pose lift to legs 0+1 in clip-space Y just
    /// before binding. The shader's IK then derives the raised knee analytically
    /// from the lifted tip — no shader changes required for the listening pose.
    /// Magnitude `0.5 × kSpiderScale × listenLiftEMA` per §6.1 / §6.3 (D-094).
    func writeSpiderToGPU() {
        var tip0 = spiderLegTips[0]
        var tip1 = spiderLegTips[1]
        let lift = Self.listenLiftTipMagnitudeUV * listenLiftEMA
        tip0.y += lift
        tip1.y += lift

        let gpu = ArachneSpiderGPU(
            blend: spiderBlend,
            posX: spiderPosX,
            posY: spiderPosY,
            heading: spiderHeading,
            tip0: tip0,
            tip1: tip1,
            tip2: spiderLegTips[2],
            tip3: spiderLegTips[3],
            tip4: spiderLegTips[4],
            tip5: spiderLegTips[5],
            tip6: spiderLegTips[6],
            tip7: spiderLegTips[7]
        )
        spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)[0] = gpu
    }

    // MARK: - Diagnostics

    /// Thread-safe snapshot of spider trigger + render state for the debug overlay.
    ///
    /// - Returns: `ArachneSpiderDiag` populated from current spider state.
    public func spiderDiagnostics() -> ArachneSpiderDiag {
        lock.withLock {
            ArachneSpiderDiag(
                accumulator: sustainedSubBassAccumulator,
                blend: spiderBlend,
                cooldownRemaining: spiderFiredInSegment ? 1.0 : 0.0,
                isForced: {
                    #if DEBUG
                    return forceSpiderActive
                    #else
                    return false
                    #endif
                }()
            )
        }
    }

    // MARK: - Test helpers

    #if DEBUG
    /// Pin the spider to a deterministic state for fixture rendering tests.
    ///
    /// Sets blend=1, positions the body at the given UV coordinate, heading=0,
    /// and all leg tips at their rest-pose angular offsets. Does not run the
    /// gait solver — tips are set directly so the output is frame-stable.
    ///
    /// - Parameter uvPosition: UV-space anchor point (e.g. `SIMD2(0.42, 0.40)`).
    public func forceActivateForTest(at uvPosition: SIMD2<Float>) {
        // Convert UV → clip space: clipX = uv.x * 2 − 1, clipY = 1 − uv.y * 2.
        let clipX = uvPosition.x * 2.0 - 1.0
        let clipY = 1.0 - uvPosition.y * 2.0
        lock.withLock {
            spiderBlend    = 1.0
            spiderPosX     = clipX
            spiderPosY     = clipY
            spiderHeading  = 0
            spiderLegPhase = 0
            for idx in 0..<8 {
                let angle = Float(idx) * (.pi * 2 / 8)
                spiderLegTips[idx] = SIMD2<Float>(
                    clipX + cos(angle) * Self.spiderLegRadius,
                    clipY + sin(angle) * Self.spiderLegRadius
                )
            }
        }
        writeSpiderToGPU()
    }
    #endif

    // MARK: - Helpers used by both ArachneState.swift and this extension

    /// Web-to-GPU flush. Called from `tick` (outside lock).
    func writeToGPU() {
        let ptr = webBuffer.contents().bindMemory(to: WebGPU.self, capacity: Self.maxWebs)
        lock.withLock {
            for i in 0..<Self.maxWebs { ptr[i] = webs[i] }
        }
    }

    // MARK: - Math helpers

    func arachSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let value = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return value * value * (3 - 2 * value)
    }

    func arachMix(_ from: Float, _ to: Float, _ factor: Float) -> Float {
        from + (to - from) * factor
    }

    func saturateF(_ x: Float) -> Float { min(max(x, 0), 1) }
}
