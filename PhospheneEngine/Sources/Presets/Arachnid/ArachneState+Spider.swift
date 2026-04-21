// ArachneState+Spider — Sub-bass easter egg gait solver and GPU buffer (Increment 3.5.9).
//
// The spider materialises as a rare reward (~1-in-10 songs) triggered by sustained
// sub-bass with low attack ratio — distinguishing deep resonant bass (James Blake,
// Burial) from transient kick drums. Session cooldown of 5 minutes prevents
// back-to-back appearances.
//
// ArachneSpiderGPU (80 bytes) is bound at fragment buffer(4) in drawWithMeshShader
// and consumed by the spider SDF ray-march in arachne_fragment.
//
// Trigger: stems.bassEnergy*1.5 (or features.subBass) > 0.65
//          AND stems.bassAttackRatio (or bassAttRel proxy) < 0.55
//          held continuously for ≥0.75 s
//          AND timeSinceLastSpider ≥ 300 s

import Metal
import Shared
import simd

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

// MARK: - Spider extension

extension ArachneState {

    // MARK: - Spider Constants

    /// Seconds of sustained sub-bass required to trigger the spider.
    static let sustainedTriggerThreshold: Float = 0.75
    /// Sub-bass energy level gate (FV: subBass 0–1; stems: bassEnergy × 1.5 proxy).
    static let subBassThreshold: Float = 0.65
    /// Attack-ratio upper bound — distinguishes resonant bass from kick drum transients.
    static let attackRatioThreshold: Float = 0.55
    /// Minimum seconds between spider appearances (session-level cooldown).
    static let sessionCooldownDuration: Float = 300.0
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
    func updateSpider(dt: Float, features: FeatureVector, stems: StemFeatures, stemMix: Float) {
        // Advance cooldown timer only when the spider is absent.
        if !spiderActive { timeSinceLastSpider += dt }

        // Sub-bass trigger: sustained resonant bass, not a kick drum.
        // FV proxy: features.subBass (6-band 20–80 Hz); stem: bassEnergy × 1.5.
        // Attack ratio: low ratio = sustained sine-like bass; high = transient percussion.
        let subBassLevel = arachMix(features.subBass,
                                    stems.bassEnergy * 1.5,
                                    stemMix)
        let attackRatio = arachMix(max(0, features.bassAttRel) + 0.5,
                                   stems.bassAttackRatio,
                                   stemMix)

        let conditionMet = subBassLevel > Self.subBassThreshold
                        && attackRatio < Self.attackRatioThreshold

        if conditionMet {
            sustainedSubBassAccumulator += dt
        } else {
            sustainedSubBassAccumulator = max(sustainedSubBassAccumulator - 2.0 * dt, 0)
        }

        // Trigger when sustained sub-bass fires and cooldown has elapsed.
        if !spiderActive
            && timeSinceLastSpider >= Self.sessionCooldownDuration
            && sustainedSubBassAccumulator >= Self.sustainedTriggerThreshold {
            activateSpider()
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

        if spiderBlend > 0 { updateSpiderGait(dt: dt) }
    }

    // MARK: - Private: activation

    private func activateSpider() {
        spiderActive = true
        timeSinceLastSpider = 0
        sustainedSubBassAccumulator = 0

        // Position at the hub of the most-opaque stable web (fallback: screen centre).
        var bestX: Float = 0, bestY: Float = 0, bestOpacity: Float = -1
        for web in webs where web.isAlive != 0 && WebStage(rawValue: web.stage) == .stable {
            if web.opacity > bestOpacity {
                bestOpacity = web.opacity
                bestX = web.hubX
                bestY = web.hubY
            }
        }
        spiderPosX  = bestOpacity >= 0 ? bestX : 0
        spiderPosY  = bestOpacity >= 0 ? bestY : 0
        spiderHeading   = lcg(&rng) * .pi * 2
        spiderLegPhase  = 0

        // Initialise leg tips in a resting spread around the body.
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
    func writeSpiderToGPU() {
        let gpu = ArachneSpiderGPU(
            blend: spiderBlend,
            posX: spiderPosX,
            posY: spiderPosY,
            heading: spiderHeading,
            tip0: spiderLegTips[0],
            tip1: spiderLegTips[1],
            tip2: spiderLegTips[2],
            tip3: spiderLegTips[3],
            tip4: spiderLegTips[4],
            tip5: spiderLegTips[5],
            tip6: spiderLegTips[6],
            tip7: spiderLegTips[7]
        )
        spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)[0] = gpu
    }

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
