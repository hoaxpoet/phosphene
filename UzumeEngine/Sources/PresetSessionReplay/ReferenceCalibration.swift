// ReferenceCalibration.swift — Calibrate rubric proxies against a
// preset's reference image set, then score the rendered output's frames
// against the calibrated family.
//
// Flow:
//   1. Load each reference image at canonical analysis resolution.
//   2. Run every rubric proxy on each reference image → raw scores per
//      (question, reference).
//   3. Run every rubric proxy on each anti-reference image → raw scores
//      per (question, anti-reference).
//   4. For each question, compute reference family mean + σ. Reference
//      scores cluster tightly when the proxy is well-calibrated; they
//      scatter when the proxy is broken.
//   5. Run every rubric proxy on each rendered video frame (uniform grid
//      of N frames). Average rendered scores per question.
//   6. Express each rendered score as σ-distance from the reference mean.
//
// SR.1 calibration-quality flag: when a question's reference scores have
// σ exceeding 50% of the mean (i.e., the proxy isn't tight on the
// references it should), the calibration is flagged as UNRELIABLE and the
// rendered verdict for that question is "cannot grade — proxy uncalibrated."
// This is the honest failure mode rather than asserting a verdict on a
// broken proxy.

import Foundation

public struct ReferenceImage: Sendable {
    public let name: String
    public let url: URL
}

public enum ReferenceCalibrationError: Error, CustomStringConvertible {
    case noReferences
    case loadFailure(URL, Error)

    public var description: String {
        switch self {
        case .noReferences: return "No references provided for calibration"
        case .loadFailure(let url, let err):
            return "Failed to load reference \(url.lastPathComponent): \(err)"
        }
    }
}

public struct CalibrationResult: Sendable {
    public let perQuestion: [QuestionCalibration]
    public let referenceReports: [RubricImageReport]
    public let antiReferenceReports: [RubricImageReport]
    public let renderedReports: [RubricImageReport]
}

public enum ReferenceCalibrator {

    /// Calibrate `questions` against `references` (positive anchors) and
    /// `antiReferences` (negative anchors), then score `renderedFrames`.
    /// Returns calibration data + per-image rubric reports for everything.
    public static func calibrate(
        questions: [RubricQuestion],
        references: [ReferenceImage],
        antiReferences: [ReferenceImage],
        renderedFrames: [ReferenceImage]
    ) throws -> CalibrationResult {
        guard !references.isEmpty else { throw ReferenceCalibrationError.noReferences }

        let refReports = try references.map { ref in
            try scoreImage(name: ref.name, url: ref.url, questions: questions)
        }
        let antiReports = try antiReferences.map { ref in
            try scoreImage(name: ref.name, url: ref.url, questions: questions)
        }
        let renderedReports = try renderedFrames.map { ref in
            try scoreImage(name: ref.name, url: ref.url, questions: questions)
        }

        // Per-question calibration: aggregate reference scores; compute
        // rendered mean across frames.
        var calibrations: [QuestionCalibration] = []
        for question in questions {
            let refScores = refReports.compactMap { report -> (String, Double)? in
                guard let score = report.scores.first(where: { $0.questionID == question.id }) else {
                    return nil
                }
                return (report.imageName, score.raw)
            }
            let antiScores = antiReports.compactMap { report -> (String, Double)? in
                guard let score = report.scores.first(where: { $0.questionID == question.id }) else {
                    return nil
                }
                return (report.imageName, score.raw)
            }
            // Rendered mean score (across all rendered frames).
            let renderedScores = renderedReports.compactMap { report -> Double? in
                report.scores.first(where: { $0.questionID == question.id })?.raw
            }
            let renderedMean = renderedScores.isEmpty
                ? nil
                : renderedScores.reduce(0, +) / Double(renderedScores.count)

            calibrations.append(QuestionCalibration(
                questionID: question.id,
                referenceScores: refScores,
                antiReferenceScores: antiScores,
                renderedScore: renderedMean
            ))
        }

        return CalibrationResult(
            perQuestion: calibrations,
            referenceReports: refReports,
            antiReferenceReports: antiReports,
            renderedReports: renderedReports
        )
    }

    private static func scoreImage(
        name: String, url: URL, questions: [RubricQuestion]
    ) throws -> RubricImageReport {
        let img: RGBAImage
        do {
            img = try ImageLoader.loadCanonical(url)
        } catch {
            throw ReferenceCalibrationError.loadFailure(url, error)
        }
        let scores = questions.map { question in
            RubricScore(questionID: question.id, raw: question.proxy(img))
        }
        return RubricImageReport(imageName: name, scores: scores)
    }
}

// MARK: - Calibration verdict

public enum CalibrationVerdict: String, Sendable {
    case withinFamily             // rendered within 1σ of reference mean
    case onFringe                 // 1σ–2σ from reference mean
    case outsideFamily            // > 2σ from reference mean
    case readsLikeAntiReference   // closer to anti-ref than to any ref
    case uncalibrated             // proxy σ unreliable (large relative scatter)
}

public extension QuestionCalibration {

    /// Whether the proxy is reliable enough to issue a verdict.
    /// Heuristic: a proxy is unreliable when ANY of:
    ///   - σ < 1e-6: proxy returned identical values for all references
    ///     (likely a fallback path producing a constant — informationless).
    ///   - relative σ (σ / |mean|) > 0.5: too scattered across references.
    ///   - mean ≈ 0 AND absolute σ > 0.10: noisy proxy with low signal.
    var proxyUnreliable: Bool {
        if referenceStddev < 1e-6 { return true }
        guard abs(referenceMean) > 1e-6 else {
            return referenceStddev > 0.10
        }
        return referenceStddev / abs(referenceMean) > 0.5
    }

    var verdict: CalibrationVerdict {
        guard renderedScore != nil else { return .uncalibrated }
        if proxyUnreliable { return .uncalibrated }
        if renderedClosestToAntiReference { return .readsLikeAntiReference }
        guard let sigma = sigmaDistance else { return .uncalibrated }
        let abss = abs(sigma)
        if abss <= 1.0 { return .withinFamily }
        if abss <= 2.0 { return .onFringe }
        return .outsideFamily
    }
}
