// WitchlightHomeTauSweep — WL.13 tasks 1–3, measured on the production path.
//
// Matt, 2026-08-07: "Is the ribbon path the same regardless of song or is the path of the
// ribbon influenced by the music?" `WitchlightPathDivergenceProbe` answered "yes, but": the
// music steers it, and two of three fixtures still draw r = +0.995 of the same figure.
//
// The mechanism is `desired = curvatureGain · phaseFromHome`, so the SIGN of the excursion
// from tonal home is the sign of the curvature: while the harmony sits on one side of home,
// curvature holds one sign and the pen winds a coil. Matt's call (option C) is to let home
// adapt faster so small harmonic moves register as direction changes — `homeTau` is the lever.
//
// Three measurements, in the order the increment needs them:
//
//   TASK 1 — is this a PATH finding or a DISPLAY one? `heading` is computed in `advancePen`
//     and no display stage writes back to it, but WL.2 asserted a confident and wrong
//     generator story about this preset once already, so the claim is VERIFIED not assumed:
//     drive the same fixtures under different per-session framings and require identical r.
//
//   TASK 2 — is the harmony actually static, or is `homeTau` just too slow to notice it
//     moving? The discriminator is φ̄'s own displacement over the timescale home tracks:
//     if φ̄ moves ~1 rad over 5 s, a faster home registers real motion; if it barely moves,
//     a faster home has nothing to register and adapting it would be inventing.
//
//   TASK 3 — the sweep. `homeTau` only; NOT gain (WL.2 measured k = 1.1 → 5.0 as no change,
//     because past k ≈ 1 the clamp saturates and heading becomes a slew-limited dither).
//
//   swift test --package-path PhospheneEngine --filter WitchlightHomeTau
//   WITCHLIGHT_SESSIONS=<dirA>:<dirB> swift test --package-path PhospheneEngine \
//       --filter WitchlightHomeTau

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

// MARK: - Shared measurement

/// One drive of the production path, with the per-frame series the WL.13 questions need.
struct WitchlightRun {
    let name: String
    let heading: [Float]
    /// φ̄ — the CR.1.2-smoothed harmonic phase, upstream of `home`.
    let smoothedPhase: [Float]
    let fromHome: [Float]
    let deltaTime: [Float]
    let monotonicity: Float
    let clampedFraction: Float
    let turnsPerTrail: Double
    let seconds: Float

    static func drive(_ drive: WitchlightFixtureDrive.Drive,
                      homeTau: Float = WitchlightTuning().homeTau,
                      normalise: Bool = WitchlightTuning().normaliseDeviationGain,
                      warmup: WitchlightTuning.HomeWarmup = WitchlightTuning().homeWarmup,
                      framing: Float? = nil) -> WitchlightRun {
        var tuning = WitchlightTuning()
        tuning.homeTau = homeTau
        tuning.normaliseDeviationGain = normalise
        tuning.homeWarmup = warmup
        let path = WitchlightPath()
        path.overrideTuning(tuning)
        if let framing { path.setSessionFraming(framing) }
        var structure = StructuralPrediction()
        var heading: [Float] = [], phase: [Float] = [], home: [Float] = [], dts: [Float] = []
        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
            heading.append(path.heading)
            phase.append(path.smoothedPhase)
            home.append(path.phaseFromHome)
            dts.append(max(drive.features[i].deltaTime, 1.0 / 240))
        }
        return WitchlightRun(name: drive.name, heading: heading, smoothedPhase: phase,
                             fromHome: home, deltaTime: dts,
                             monotonicity: path.headingMonotonicity,
                             clampedFraction: path.clampedFraction,
                             turnsPerTrail: path.responseMetric("headingTurnsPerTrail") ?? 0,
                             seconds: dts.reduce(0, +))
    }

    /// Sign changes of `phaseFromHome` per second — the only thing that makes the pen
    /// reverse. A coil is a long run of one sign.
    var crossingsPerSecond: Float {
        var crossings = 0
        for i in 1..<fromHome.count where fromHome[i - 1] * fromHome[i] < 0 { crossings += 1 }
        return Float(crossings) / max(seconds, 1)
    }

    /// `|net| / travel` of the heading over the first `seconds` only — the same quantity
    /// `headingMonotonicity` reports for a whole run, windowed. 1 = the pen turned one way
    /// the whole time (the §3.1(b) degenerate circle); 0 = it reversed, which is a figure.
    ///
    /// This is what separates a MECHANISM defect from a COLD-START one: `reset()` runs on
    /// every track change and leaves home at 0 rad, so if the coil is the warm-up ramp it
    /// will show up in a real session's first 30 s and be gone by its last.
    func monotonicity(overFirst seconds: Float) -> Float {
        var clock: Float = 0, travel: Float = 0, last = heading.first ?? 0
        var end = heading.first ?? 0
        for i in 1..<heading.count {
            clock += deltaTime[i]
            if clock > seconds { break }
            travel += abs(heading[i] - last); last = heading[i]; end = heading[i]
        }
        guard travel > 1e-4 else { return 0 }
        return abs(end - (heading.first ?? 0)) / travel
    }

    /// Median seconds `phaseFromHome` holds one sign. The crossing COUNT hides the shape:
    /// one 20 s coil plus a flurry of fast crossings averages to something unremarkable.
    var medianSignDwell: Float {
        var runs: [Float] = []
        var current: Float = 0
        for i in 1..<fromHome.count {
            current += deltaTime[i]
            if fromHome[i - 1] * fromHome[i] < 0 { runs.append(current); current = 0 }
        }
        guard !runs.isEmpty else { return seconds }
        runs.sort()
        return runs[runs.count / 2]
    }
}

/// Pearson r over the common prefix. Headings are unwrapped by construction.
func witchlightCorrelation(_ a: [Float], _ b: [Float]) -> Double {
    let n = min(a.count, b.count)
    guard n > 100 else { return .nan }
    let x = a.prefix(n).map(Double.init), y = b.prefix(n).map(Double.init)
    let mx = x.reduce(0, +) / Double(n), my = y.reduce(0, +) / Double(n)
    var num = 0.0, dx = 0.0, dy = 0.0
    for i in 0..<n {
        let a0 = x[i] - mx, b0 = y[i] - my
        num += a0 * b0; dx += a0 * a0; dy += b0 * b0
    }
    guard dx > 0, dy > 0 else { return .nan }
    return num / (dx * dy).squareRoot()
}

// MARK: - Suite

@Suite("Witchlight homeTau sweep (WL.13)")
struct WitchlightHomeTauSweep {

    private static let taus: [Float] = [2, 3, 4, 6, 8, 12, 16]

    // MARK: Task 1

    @Test("TASK 1 — the correlation is a PATH property, unchanged by the tumble framing")
    func headingIsUpstreamOfDisplay() throws {
        let drives = try WitchlightFixtureDrive.tracks.map { try WitchlightFixtureDrive.load($0) }
        // Canonical framing (what every other harness renders) vs deliberately varied
        // per-track framings — different tumble phase AND opposite roll handedness.
        let canonical = drives.map { WitchlightRun.drive($0) }
        let varied = zip(drives, [Float(0.37), 0.81, 0.13]).map { WitchlightRun.drive($0.0, framing: $0.1) }

        print("\nWL.13 TASK 1 — cross-track heading correlation, canonical framing vs nulled/varied tumble")
        var worstDelta = 0.0
        for i in 0..<canonical.count {
            for j in (i + 1)..<canonical.count {
                let base = witchlightCorrelation(canonical[i].heading, canonical[j].heading)
                let alt = witchlightCorrelation(varied[i].heading, varied[j].heading)
                worstDelta = max(worstDelta, abs(base - alt))
                print(String(format: "  %@ vs %@: r = %+.3f (canonical) | %+.3f (varied framing) | Δ %.6f",
                             canonical[i].name as NSString, canonical[j].name as NSString,
                             base, alt, abs(base - alt)))
            }
        }
        print(String(format: "  worst Δ = %.6f\n", worstDelta))

        #expect(worstDelta < 1e-6, """
            changing the per-session tumble framing moved the heading correlation by \
            \(worstDelta) — `heading` is NOT upstream of the display stages, so the WL.3 \
            story is repeating and the WL.13 diagnosis is wrong. STOP.
            """)
    }

    // MARK: Task 2

    @Test("TASK 2 — does the harmony genuinely not move, or does home track it too slowly?")
    func harmonyMotionCharacter() throws {
        print("\nWL.13 TASK 2 — is the harmony static, or is `home` too slow to see it move?")
        print("  φ̄ displacement = mean |wrap(φ̄(t) − φ̄(t−lag))|, radians. This is what a")
        print("  faster `home` would have to register. Near 0 => nothing to register.")
        for track in WitchlightFixtureDrive.tracks {
            let drive = try WitchlightFixtureDrive.load(track)
            let run = WitchlightRun.drive(drive)
            let raw = drive.features.map { $0.tonalPhaseFifths }

            // Raw driver: circular concentration R and the per-frame step, so the smoothed
            // numbers can be read against what actually arrived.
            let sinSum = raw.reduce(Float(0)) { $0 + sin($1) } / Float(raw.count)
            let cosSum = raw.reduce(Float(0)) { $0 + cos($1) } / Float(raw.count)
            let concentration = (sinSum * sinSum + cosSum * cosSum).squareRoot()

            var lagLine = ""
            for lag in [Float(2), 5, 10] {
                let frames = Int(lag / max(run.seconds / Float(run.heading.count), 1e-4))
                guard frames > 0, frames < run.smoothedPhase.count else { continue }
                var total: Float = 0
                for i in frames..<run.smoothedPhase.count {
                    var d = run.smoothedPhase[i] - run.smoothedPhase[i - frames]
                    while d > .pi { d -= 2 * .pi }
                    while d < -.pi { d += 2 * .pi }
                    total += abs(d)
                }
                lagLine += String(format: " | %.0fs %.2f rad", lag, total / Float(run.smoothedPhase.count - frames))
            }
            print(String(format: "  %-12@ circular R %.3f | φ̄ travel %5.2f rad%@",
                         track as NSString, concentration,
                         run.smoothedPhase.count > 1 ? phaseTravelOf(run) : 0, lagLine as NSString))
            print(String(format: "               sign-crossings %.2f/s | MEDIAN SIGN DWELL %5.2f s | |fromHome| mean %.2f rad (homeTau %.0f s)",
                         run.crossingsPerSecond, run.medianSignDwell,
                         run.fromHome.reduce(0) { $0 + abs($1) } / Float(run.fromHome.count),
                         WitchlightTuning().homeTau))
        }
        print("")
    }

    private func phaseTravelOf(_ run: WitchlightRun) -> Float {
        var total: Float = 0
        for i in 1..<run.smoothedPhase.count {
            var d = run.smoothedPhase[i] - run.smoothedPhase[i - 1]
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            total += abs(d)
        }
        return total
    }

    // MARK: Task 3

    @Test("TASK 3 — homeTau sweep on the fixtures")
    func sweepFixtures() throws {
        let drives = try WitchlightFixtureDrive.tracks.map { try WitchlightFixtureDrive.load($0) }
        print("\nWL.13 TASK 3 — homeTau sweep (fixtures). turns/trail floor 1.20 is a LIVE QG.5 band.")
        // `normaliseDeviationGain` is swept alongside because a faster home SHRINKS
        // |deviation| — the two levers pull opposite ways on turn magnitude, and reporting
        // homeTau alone would hide that the figure straightens for a reason the normaliser
        // already exists to answer. This is NOT raising `curvatureGain` (the Do-NOT): the
        // fixed gain is untouched; the normaliser is the shipped-but-off per-track scaler.
        for normalise in [false, true] {
            print("  --- normaliseDeviationGain = \(normalise) ---")
            for tau in Self.taus {
                let runs = drives.map { WitchlightRun.drive($0, homeTau: tau, normalise: normalise) }
                var pairs: [String] = []
                var worst = -1.0
                for i in 0..<runs.count {
                    for j in (i + 1)..<runs.count {
                        let r = witchlightCorrelation(runs[i].heading, runs[j].heading)
                        worst = max(worst, r)
                        pairs.append(String(format: "%+.3f", r))
                    }
                }
                print(String(format: "  homeTau %4.1f s | worst pair r %+.3f  (%@)",
                             tau, worst, pairs.joined(separator: " ") as NSString))
                for run in runs {
                    print(String(format: "      %-12@ turns/trail %.2f | monotonicity %.2f | clamp %4.1f %% | crossings %.2f/s | dwell %5.2f s",
                                 run.name as NSString, run.turnsPerTrail, run.monotonicity,
                                 run.clampedFraction * 100, run.crossingsPerSecond, run.medianSignDwell))
                }
            }
        }
        print("")
    }

    /// The 21 s fixtures cannot exercise a 12 s `home` past its warm-up: `reset()` leaves
    /// home at 0 rad and the EMA takes ~30 s to reach the real tonal centre, so for the whole
    /// clip `phaseFromHome` holds one sign and the pen coils. This A/B says how much of the
    /// r = +0.995 finding is that ramp rather than the steady-state steer — and it is the
    /// difference between a mechanism defect and a per-track-start one.
    @Test("TASK 3b — how much of the coil is `home` warming up from 0 rad?")
    func seedHomeAB() throws {
        let drives = try WitchlightFixtureDrive.tracks.map { try WitchlightFixtureDrive.load($0) }
        print("\nWL.13 TASK 3b — seeding `home` from the first frame's phase (homeTau unchanged at 12 s)")
        for seed in [WitchlightTuning.HomeWarmup.fromZero, .unbiased] {
            let runs = drives.map { WitchlightRun.drive($0, warmup: seed) }
            var pairs: [String] = []
            var worst = -1.0
            for i in 0..<runs.count {
                for j in (i + 1)..<runs.count {
                    let r = witchlightCorrelation(runs[i].heading, runs[j].heading)
                    worst = max(worst, r)
                    pairs.append(String(format: "%@/%@ %+.3f", String(runs[i].name.prefix(4)) as NSString,
                                        String(runs[j].name.prefix(4)) as NSString, r))
                }
            }
            print(String(format: "  homeWarmup %-16@ | worst pair r %+.3f  (%@)",
                         String(describing: seed) as NSString, worst,
                         pairs.joined(separator: "  ") as NSString))
            for run in runs {
                print(String(format: "      %-12@ turns/trail %.2f | monotonicity %.2f | clamp %4.1f %% | crossings %.2f/s | dwell %5.2f s",
                             run.name as NSString, run.turnsPerTrail, run.monotonicity,
                             run.clampedFraction * 100, run.crossingsPerSecond, run.medianSignDwell))
            }
        }
        print("")
    }

    @Test("TASK 3 — homeTau sweep on recorded sessions")
    func sweepSessions() throws {
        guard let joined = ProcessInfo.processInfo.environment["WITCHLIGHT_SESSIONS"] else { return }
        print("\nWL.13 TASK 3 — homeTau sweep (recorded sessions; the fixtures are 21 s and this is slow-timescale)")
        let drives = try joined.split(separator: ":").map(String.init).map { dir -> WitchlightFixtureDrive.Drive in
            let url = URL(fileURLWithPath: dir)
            return try WitchlightFixtureDrive.load(sessionDirectory: url, name: url.lastPathComponent)
        }
        // Is the coil a MECHANISM defect or a COLD-START one? Windowed monotonicity on real
        // multi-minute material, at the SHIPPED homeTau, against the three warm-up variants.
        print("  cold-start vs steady state — heading monotonicity by window (1 = coiling)")
        for drive in drives {
            for warm in [WitchlightTuning.HomeWarmup.fromZero, .unbiased] {
                let run = WitchlightRun.drive(drive, warmup: warm)
                print(String(format: "      %-22@ %-16@ | first 15 s %.2f | first 30 s %.2f | first 60 s %.2f | whole run %.2f",
                             drive.name as NSString, String(describing: warm) as NSString,
                             run.monotonicity(overFirst: 15), run.monotonicity(overFirst: 30),
                             run.monotonicity(overFirst: 60), run.monotonicity))
            }
        }
        for drive in drives {
            print("  \(drive.name) — \(drive.features.count) frames")
            for tau in Self.taus {
                let run = WitchlightRun.drive(drive, homeTau: tau)
                let norm = WitchlightRun.drive(drive, homeTau: tau, normalise: true)
                print(String(format: "      homeTau %4.1f s | turns/trail %.2f | monotonicity %.2f | clamp %4.1f %% | crossings %.2f/s | dwell %5.2f s   [normalised: turns %.2f | mono %.2f | clamp %4.1f %%]",
                             tau, run.turnsPerTrail, run.monotonicity,
                             run.clampedFraction * 100, run.crossingsPerSecond, run.medianSignDwell,
                             norm.turnsPerTrail, norm.monotonicity, norm.clampedFraction * 100))
            }
        }
        // Cross-SESSION correlation — the gate quantity on real material. Different sessions
        // are different music, which is the comparison Matt's question is about; the 21 s
        // fixtures cannot exercise a 12 s `home` past its warm-up ramp.
        guard drives.count > 1 else { print(""); return }
        print("  cross-session heading correlation (different music, same code):")
        for tau in Self.taus {
            let runs = drives.map { WitchlightRun.drive($0, homeTau: tau) }
            var pairs: [String] = []
            var worst = -1.0
            for i in 0..<runs.count {
                for j in (i + 1)..<runs.count {
                    let r = witchlightCorrelation(runs[i].heading, runs[j].heading)
                    worst = max(worst, r)
                    pairs.append(String(format: "%+.3f", r))
                }
            }
            print(String(format: "      homeTau %4.1f s | worst pair r %+.3f  (%@)",
                         tau, worst, pairs.joined(separator: " ") as NSString))
        }
        print("")
    }
}
