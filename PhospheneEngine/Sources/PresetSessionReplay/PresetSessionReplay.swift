// PresetSessionReplay.swift — CLI entrypoint for the session-replay harness.
//
// Invocation:
//   swift run preset-session-replay \
//       --session /path/to/2026-05-20T01-23-03Z \
//       --preset aurora_veil \
//       [--output /tmp/replay] \
//       [--motion-grid-count 600] \
//       [--max-events-per-route 6]
//
// Outputs:
//   <output>/replay_report.md
//   <output>/events/<route>/event_NN.png
//   <output>/motion_grid/grid_NNN.png  (if motion-grid > 0)
//
// SR.1: Aurora Veil is the only registered preset. Future presets register
// their route specs in <Preset>Routes.swift and add a case to the
// PresetRegistry below.

import ArgumentParser
import Foundation
import Shared

@main
struct PresetSessionReplay: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "preset-session-replay",
        abstract: "Replay a recorded Phosphene session against a preset's route specs.",
        discussion: """
            Parses a session's features.csv + stems.csv, computes per-route
            firing statistics, extracts video frames at the strongest audio
            events, and emits a Markdown report. The report is the canonical
            evidence pack for closeout claims about audio-driven behaviour.

            See docs/ENGINE/SESSION_REPLAY.md for how to register a new preset.
            """
    )

    @Option(name: .shortAndLong, help: "Session directory (contains features.csv, stems.csv, video.mp4).")
    var session: String

    @Option(name: .shortAndLong, help: "Preset name (aurora_veil).")
    var preset: String

    @Option(name: .shortAndLong, help: "Output directory for report + extracted frames.")
    var output: String?

    @Option(name: .long, help: "Number of frames to extract for the motion-band uniform grid (0 to disable).")
    var motionGridCount: Int = 600

    @Option(name: .long, help: "Max number of strongest events to report per route.")
    var maxEventsPerRoute: Int = 6

    // swiftlint:disable:next line_length
    @Option(name: .long, help: "Directory of curated references for visual rubric calibration (e.g., docs/VISUAL_REFERENCES/aurora_veil/).")
    var referencesDir: String?

    @Option(name: .long, help: "Number of evenly-spaced rendered video frames to grade against the rubric.")
    var rubricFrameCount: Int = 24

    mutating func run() async throws {
        let sessionURL = URL(fileURLWithPath: session)
        let outputURL = URL(fileURLWithPath:
            output ?? "/tmp/phosphene_replay/\(sessionURL.lastPathComponent)_\(preset)")

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        print("Loading session: \(sessionURL.path)")
        let data = try SessionDataLoader.load(directory: sessionURL)
        print("  frames: \(data.frames.count)")
        print("  duration: \(String(format: "%.2f", data.durationSeconds)) s")
        print("  inferred fps: \(String(format: "%.2f", data.inferredFPS))")
        print("  video: \(data.videoURL?.lastPathComponent ?? "—")")

        let routes = try resolvePreset(preset)
        let routeAnalysis = try analyzeAllRoutes(
            routes: routes, data: data, outputURL: outputURL)

        let (motion, gridURLs) = try maybeAnalyzeMotion(data: data, outputURL: outputURL)

        // Visual rubric calibration (if --references-dir provided).
        let questions = AuroraVeilRubricQuestions.all
        let calibration = try maybeCalibrateRubric(
            data: data,
            outputURL: outputURL,
            questions: questions)

        let report = ReplayReport(
            session: data,
            routeReports: routeAnalysis.routeReports,
            eventsByRoute: routeAnalysis.eventsByRoute,
            eventImages: routeAnalysis.eventImages,
            motionAnalysis: motion,
            motionGridURLs: gridURLs,
            calibration: calibration,
            questions: questions
        )

        let reportURL = outputURL.appendingPathComponent("replay_report.md")
        try ReportGenerator.writeMarkdown(report: report, to: reportURL, presetName: preset)

        print("")
        print("Wrote report: \(reportURL.path)")
        print("Open with: open '\(reportURL.path)'")
    }

    // MARK: - Per-route analysis

    private struct RouteAnalysisBundle {
        var routeReports: [RouteFiringReport]
        var eventsByRoute: [String: [AudioEvent]]
        var eventImages: [String: [URL]]
    }

    private func analyzeAllRoutes(
        routes: [RouteSpec],
        data: SessionData,
        outputURL: URL
    ) throws -> RouteAnalysisBundle {
        print("Analyzing \(routes.count) routes for \(preset)...")
        var bundle = RouteAnalysisBundle(
            routeReports: [], eventsByRoute: [:], eventImages: [:])
        for route in routes {
            let report = RouteAnalyzer.analyze(route: route, session: data)
            bundle.routeReports.append(report)
            print("  \(route.name): \(String(format: "%.2f", report.firingPercent))% firing")
            let events = AudioEventExtractor.extract(
                route: route, from: data, maxEvents: maxEventsPerRoute)
            bundle.eventsByRoute[route.name] = events
            bundle.eventImages[route.name] = extractEventFrames(
                route: route, events: events, data: data, outputURL: outputURL)
        }
        return bundle
    }

    private func extractEventFrames(
        route: RouteSpec,
        events: [AudioEvent],
        data: SessionData,
        outputURL: URL
    ) -> [URL] {
        guard let videoURL = data.videoURL, !events.isEmpty else { return [] }
        let safeRouteName = route.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "→", with: "to")
            .replacingOccurrences(of: "/", with: "_")
        let eventsDir = outputURL
            .appendingPathComponent("events")
            .appendingPathComponent(safeRouteName)
        let t0 = data.frames.first?.wallclockSeconds ?? 0
        var imgs: [URL] = []
        for (idx, event) in events.enumerated() {
            let imgURL = eventsDir.appendingPathComponent(
                String(format: "event_%02d.png", idx))
            do {
                let extracted = try VideoFrameExtractor.extractFrame(
                    from: videoURL,
                    atSeconds: event.wallclockSeconds - t0,
                    to: imgURL)
                imgs.append(extracted)
            } catch {
                print("    warning: failed to extract frame at \(event.wallclockSeconds): \(error)")
            }
        }
        return imgs
    }

    // MARK: - Motion-band analysis

    private func maybeAnalyzeMotion(
        data: SessionData,
        outputURL: URL
    ) throws -> (MotionAnalysis?, [URL]) {
        guard motionGridCount > 0, let videoURL = data.videoURL else { return (nil, []) }
        print("Extracting motion grid (\(motionGridCount) frames)...")
        let gridDir = outputURL.appendingPathComponent("motion_grid")
        let gridURLs = try VideoFrameExtractor.extractUniformGrid(
            from: videoURL,
            count: motionGridCount,
            to: gridDir)
        let sampleHz = Double(motionGridCount) / data.durationSeconds
        let motionResult = try MotionBandAnalyzer.analyze(
            frameURLs: gridURLs,
            samplingHz: sampleHz)
        print("  bands:")
        for band in motionResult.bands {
            let line = String(
                format: "    %@: %.6f (%.3f–%.3f Hz)",
                band.name,
                band.energy,
                band.lowHz,
                band.highHz)
            print(line)
        }
        return (motionResult, gridURLs)
    }

    // MARK: - Visual rubric calibration

    private func maybeCalibrateRubric(
        data: SessionData,
        outputURL: URL,
        questions: [RubricQuestion]
    ) throws -> CalibrationResult? {
        guard let refsPath = referencesDir else { return nil }
        guard let videoURL = data.videoURL else {
            print("Skipping visual rubric: --references-dir set but session has no video.mp4.")
            return nil
        }
        print("Calibrating visual rubric against \(refsPath)...")
        let (refs, antiRefs) = resolveReferences(URL(fileURLWithPath: refsPath))
        print("  references: \(refs.count); anti-references: \(antiRefs.count)")
        let rubricDir = outputURL.appendingPathComponent("rubric_grid")
        let rubricFrameURLs = try VideoFrameExtractor.extractUniformGrid(
            from: videoURL,
            count: rubricFrameCount,
            to: rubricDir)
        print("  rendered frames: \(rubricFrameURLs.count)")
        let renderedFrames = rubricFrameURLs.enumerated().map { idx, url in
            ReferenceImage(name: "render_\(String(format: "%03d", idx))", url: url)
        }
        let result = try ReferenceCalibrator.calibrate(
            questions: questions,
            references: refs,
            antiReferences: antiRefs,
            renderedFrames: renderedFrames
        )
        for qcal in result.perQuestion {
            let question = questions.first(where: { $0.id == qcal.questionID })
            let label = question.map { "\($0.id) (\($0.name))" } ?? qcal.questionID
            print("  \(label): \(qcal.verdict.rawValue)")
        }
        return result
    }

    // MARK: - References discovery

    /// Discover reference + anti-reference images in a curated directory.
    /// Convention: files starting with `09_` are anti-references; all
    /// other numbered files (e.g., `01_`, `02_`, ...) are references.
    /// Matches the convention in docs/VISUAL_REFERENCES/<preset>/.
    private func resolveReferences(_ dir: URL) -> (refs: [ReferenceImage], antiRefs: [ReferenceImage]) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var refs: [ReferenceImage] = []
        var antiRefs: [ReferenceImage] = []
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png"].contains(ext) else { continue }
            let ref = ReferenceImage(name: name, url: url)
            if name.hasPrefix("09") {
                antiRefs.append(ref)
            } else if name.first?.isNumber == true {
                refs.append(ref)
            }
        }
        return (refs, antiRefs)
    }

    // MARK: - Preset registry

    private func resolvePreset(_ name: String) throws -> [RouteSpec] {
        switch name.lowercased() {
        case "aurora_veil", "aurora-veil", "auroraveil":
            return AuroraVeilRouteSpecs.all
        default:
            throw ValidationError(
                "Unknown preset '\(name)'. Registered: aurora_veil. "
                + "Add new presets in PresetSessionReplay.swift::resolvePreset.")
        }
    }
}
