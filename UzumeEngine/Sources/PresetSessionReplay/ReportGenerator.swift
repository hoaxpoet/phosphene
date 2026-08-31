// ReportGenerator.swift — Markdown report builder for a session replay run.
//
// Emits one Markdown file (replay_report.md) containing:
//   1. Session metadata (path, duration, frame count, FPS).
//   2. Per-route firing report — table of input min/p50/p90/p99/max, gate
//      threshold, % frames firing.
//   3. For each route: list of strongest events (timestamp + input value +
//      embedded frame image extracted at that timestamp).
//   4. Motion-band analysis — table of band energies (substorm / substrate /
//      pulsation / sub-second / aliased).
//   5. Discipline footer — explicit statement of what the report did and did
//      not verify, so future closeouts cite it correctly.
//
// SR.1 design notes (committed alongside the code so a future reader knows
// why the report looks the way it does):
//   - Markdown chosen over HTML because reports get committed alongside the
//     code that produced them. Diff-readable.
//   - Embedded images are relative paths to the extracted frame PNGs;
//     committed alongside the report.
//   - Per-route event timestamps are reported with both audio time and
//     wallclock time so cross-references against features.csv work.

import Foundation

// swiftlint:disable identifier_name function_body_length cyclomatic_complexity line_length
// Markdown emission uses single-letter aliases (r = report, b = band, q =
// question) for the many short-lived loop locals; long lines come from
// embedded prose blocks that read more clearly as a single string.

public struct ReplayReport: Sendable {
    public let session: SessionData
    public let routeReports: [RouteFiringReport]
    public let eventsByRoute: [String: [AudioEvent]]
    public let eventImages: [String: [URL]]   // routeName -> [imageURL per event]
    public let motionAnalysis: MotionAnalysis?
    public let motionGridURLs: [URL]
    public let calibration: CalibrationResult?
    public let questions: [RubricQuestion]
}

public enum ReportGenerator {

    public static func writeMarkdown(
        report: ReplayReport,
        to outputURL: URL,
        presetName: String
    ) throws {
        var lines: [String] = []

        // ── Header ─────────────────────────────────────────────────────────
        lines.append("# Session Replay — \(presetName)")
        lines.append("")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))  ")
        lines.append("Session: `\(report.session.path.lastPathComponent)`  ")
        lines.append("Duration: \(formatSeconds(report.session.durationSeconds))  ")
        lines.append("Frames: \(report.session.frames.count) (\(String(format: "%.1f", report.session.inferredFPS)) Hz)  ")
        lines.append("Video: \(report.session.videoURL?.lastPathComponent ?? "—")  ")
        lines.append("")

        // ── Route firing ──────────────────────────────────────────────────
        lines.append("## Route firing")
        lines.append("")
        lines.append("Per-route gate-crossing statistics. **% frames firing** is the load-bearing column — a route at 0 % did not fire during this session and any closeout claim that it worked is unsupported by the evidence below. **Partial fire %** (for routes with a smoothstep HI edge) measures how often the input reached the full-amplitude ceiling.")
        lines.append("")
        lines.append("| Route | Input | Gate | Partial Gate | Min | p50 | p90 | p99 | Max | Firing % | Partial % |")
        lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
        for r in report.routeReports {
            let partial = r.route.partialGateThreshold.map { String(format: "%.3f", $0) } ?? "—"
            let partialPct = r.partialFiringPercent
                .map { String(format: "%.2f", $0) } ?? "—"
            lines.append(
                "| \(r.route.name) | `\(r.route.inputName)` | \(String(format: "%.3f", r.route.gateThreshold)) | \(partial) | "
                + "\(String(format: "%.3f", r.inputMin)) | \(String(format: "%.3f", r.inputP50)) | "
                + "\(String(format: "%.3f", r.inputP90)) | \(String(format: "%.3f", r.inputP99)) | "
                + "\(String(format: "%.3f", r.inputMax)) | "
                + "**\(String(format: "%.2f", r.firingPercent))%** | \(partialPct)% |")
        }
        lines.append("")

        // ── Per-route event-aligned frames ────────────────────────────────
        lines.append("## Audio events + rendered frames")
        lines.append("")
        lines.append("For each route, the N strongest audio events (after refractory suppression) with the rendered video frame extracted at that timestamp. Use these side-by-side: if the route fires but the visual frame looks identical to the surrounding frames, the audio→visual coupling is not landing in the rendered output.")
        lines.append("")
        for r in report.routeReports {
            let events = report.eventsByRoute[r.route.name] ?? []
            let imgs = report.eventImages[r.route.name] ?? []
            lines.append("### \(r.route.name)")
            lines.append("")
            lines.append(r.route.description)
            lines.append("")
            if events.isEmpty {
                lines.append("**No events recorded — route did not cross gate during this session.**")
                lines.append("")
                continue
            }
            let t0 = report.session.frames.first?.wallclockSeconds ?? 0
            for (event, img) in zip(events, imgs) {
                let tt = String(format: "%.2f s", event.wallclockSeconds - t0)
                let val = String(format: "%.3f", event.inputValue)
                let rel = img.path.replacingOccurrences(of: outputURL.deletingLastPathComponent().path + "/", with: "")
                lines.append("- t = \(tt) (frame \(event.frameIndex)), \(r.route.inputName) = \(val)")
                lines.append("")
                lines.append("  ![event frame](\(rel))")
                lines.append("")
            }
        }

        // ── Motion-band analysis ──────────────────────────────────────────
        if let motion = report.motionAnalysis {
            lines.append("## Motion-band analysis")
            lines.append("")
            lines.append("Frame-delta frequency decomposition across \(motion.frameCount) frames sampled at \(String(format: "%.2f", motion.samplingHz)) Hz (Nyquist \(String(format: "%.2f", motion.nyquistHz)) Hz). Band energies are mean DFT magnitudes within each band. Higher = more motion energy at that timescale.")
            lines.append("")
            lines.append("⚠ The sampled grid's Nyquist limits what frequencies are observable. The default grid (~600 frames over a 132-s session) gives Nyquist ≈ 2.25 Hz — sub-second flicker (5–10 Hz) is below Nyquist and aliases. Use a denser grid for sub-second analysis.")
            lines.append("")
            lines.append("| Band | Range (Hz) | Energy |")
            lines.append("|---|---|---|")
            for b in motion.bands {
                lines.append("| \(b.name) | \(String(format: "%.3f", b.lowHz))-\(String(format: "%.3f", b.highHz)) | \(String(format: "%.6f", b.energy)) |")
            }
            lines.append("")
        }

        // ── Visual rubric calibration ─────────────────────────────────────
        if let cal = report.calibration {
            lines.append("## Visual rubric — calibrated against reference set")
            lines.append("")
            lines.append("Each rubric question has an image-processing proxy that scores the image numerically. Proxies are calibrated against the preset's reference set: per-question reference family mean + σ. The rendered video's per-question score is expressed as σ-distance from the reference mean. Proxies whose reference scatter is too wide (σ > 50 % of |mean|) are flagged UNCALIBRATED — the rendered verdict is withheld rather than asserted on a broken proxy.")
            lines.append("")
            lines.append("**Verdicts**: `within_family` ≤ 1σ of reference mean. `on_fringe` 1σ–2σ. `outside_family` > 2σ. `reads_like_anti_reference` = rendered score closer to an anti-reference than to any reference. `uncalibrated` = proxy unreliable.")
            lines.append("")
            lines.append("| Q | Question | Verdict | Rendered | Ref mean | Ref σ | σ-dist | Closest ref |")
            lines.append("|---|---|---|---|---|---|---|---|")
            for q in report.questions {
                guard let qc = cal.perQuestion.first(where: { $0.questionID == q.id }) else { continue }
                let v = qc.verdict
                let rendered = qc.renderedScore.map { String(format: "%.4f", $0) } ?? "—"
                let mean = String(format: "%.4f", qc.referenceMean)
                let sd = String(format: "%.4f", qc.referenceStddev)
                let sigma = qc.sigmaDistance.map { String(format: "%+.2f σ", $0) } ?? "—"
                let closest = qc.referenceScores
                    .min(by: { abs($0.score - (qc.renderedScore ?? 0)) < abs($1.score - (qc.renderedScore ?? 0)) })?
                    .name ?? "—"
                lines.append("| \(q.id) | \(q.name) | **\(v.rawValue)** | \(rendered) | \(mean) | \(sd) | \(sigma) | \(closest) |")
            }
            lines.append("")
            lines.append("### Per-image raw scores")
            lines.append("")
            lines.append("Reference + anti-reference + rendered scores per question. If two reference scores disagree by more than the rendered's distance from either, the proxy is detecting structural variation across the reference set itself (not just rendered vs references) — a flag that proxy interpretation needs care.")
            lines.append("")
            // Header
            var headerCols = ["Image"]
            for q in report.questions { headerCols.append(q.id) }
            lines.append("| " + headerCols.joined(separator: " | ") + " |")
            lines.append("|" + String(repeating: "---|", count: headerCols.count))
            func rowFor(_ rep: RubricImageReport) -> String {
                var cols = [rep.imageName]
                for q in report.questions {
                    let s = rep.scores.first(where: { $0.questionID == q.id })?.raw ?? .nan
                    cols.append(String(format: "%.4f", s))
                }
                return "| " + cols.joined(separator: " | ") + " |"
            }
            for r in cal.referenceReports { lines.append(rowFor(r)) }
            for r in cal.antiReferenceReports { lines.append("| **anti:** " + rowFor(r).dropFirst(2)) }
            for r in cal.renderedReports { lines.append("| **render:** " + rowFor(r).dropFirst(2)) }
            lines.append("")
            lines.append("### Per-question proxy definitions")
            lines.append("")
            for q in report.questions {
                lines.append("**\(q.id) — \(q.name).** \(q.description)")
                lines.append("- Proxy: `\(q.proxyName)`")
                lines.append("- HIGH means: \(q.highMeans)")
                lines.append("- LOW means: \(q.lowMeans)")
                lines.append("")
            }
        }

        // ── Discipline footer ─────────────────────────────────────────────
        lines.append("## What this report does and does not verify")
        lines.append("")
        lines.append("**Verified by this report:**")
        lines.append("- Per-route input statistics across the entire session.")
        lines.append("- % of frames where each route's gate condition fires.")
        lines.append("- Audio-event timestamps + rendered frames at those timestamps (visual response check is by inspection).")
        lines.append("- Frame-delta motion energy decomposed by timescale band (subject to Nyquist).")
        lines.append("")
        lines.append("**NOT verified by this report:**")
        lines.append("- Whether the audio-driven visual response feels musically correct (Matt's L4 review).")
        lines.append("- Fidelity to reference photographs (9-Q rubric — manual side-by-side).")
        lines.append("- Sub-second flicker if the sampled grid's Nyquist is below 10 Hz.")
        lines.append("- Codec compression effects on high-frequency motion energy.")
        lines.append("")
        lines.append("If a closeout cites this report as evidence that \"the route works,\" it must restrict the claim to what this report verifies (gate firing rates + audio-event frames present). A claim that the route produces a \"visible response\" requires manual inspection of the event-aligned frames OR a follow-up SR.2+ check that quantifies visual response.")
        lines.append("")

        let body = lines.joined(separator: "\n")
        try body.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func formatSeconds(_ s: Double) -> String {
        let m = Int(s / 60)
        let r = s - Double(m) * 60
        return String(format: "%d:%05.2f", m, r)
    }
}

// swiftlint:enable identifier_name function_body_length cyclomatic_complexity line_length
