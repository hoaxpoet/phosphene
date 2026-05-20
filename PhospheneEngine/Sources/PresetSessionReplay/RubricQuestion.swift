// RubricQuestion.swift — Generic per-question rubric scoring infrastructure.
//
// One RubricQuestion = one numerical proxy for one cert-rubric question.
// SR.1 design choice: each proxy returns a Double in a question-specific
// scale (NOT normalized to [0, 1]). The proxy's MEANING — what high/low
// scores correspond to — is documented in the question's `description` and
// `highMeans`/`lowMeans` fields. Normalization happens only at the
// reference-calibration step (see ReferenceCalibration.swift), where we
// compute σ-distance from the reference family centroid.
//
// Why this shape: it forces the calibration step to be load-bearing. If a
// proxy were normalized "0–1 where 1 = aurora-like" at the proxy itself,
// we'd be encoding judgment into the proxy without grounding. Computing
// raw scores per question + calibrating against the actual references
// keeps the judgment empirical.

import Foundation

/// One cert-rubric question and the proxy that scores it.
public struct RubricQuestion: Sendable {
    public let id: String          // e.g., "Q1", "Q3"
    public let name: String        // e.g., "Vertical stratification only"
    public let description: String
    public let highMeans: String   // English interpretation of a HIGH score
    public let lowMeans: String    // English interpretation of a LOW score
    public let proxyName: String   // English name of the proxy quantity
    public let proxy: @Sendable (RGBAImage) -> Double

    public init(
        id: String, name: String, description: String,
        highMeans: String, lowMeans: String, proxyName: String,
        proxy: @Sendable @escaping (RGBAImage) -> Double
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.highMeans = highMeans
        self.lowMeans = lowMeans
        self.proxyName = proxyName
        self.proxy = proxy
    }
}

/// One image's score on one question.
public struct RubricScore: Sendable {
    public let questionID: String
    public let raw: Double
}

/// Set of scores for one image across all questions of a rubric.
public struct RubricImageReport: Sendable {
    public let imageName: String
    public let scores: [RubricScore]
}

/// Calibration data for one question over a reference set.
public struct QuestionCalibration: Sendable {
    public let questionID: String
    public let referenceScores: [(name: String, score: Double)]
    public let referenceMean: Double
    public let referenceStddev: Double
    public let antiReferenceScores: [(name: String, score: Double)]

    /// Score for the rendered output, with σ-distance from reference mean
    /// computed once `scoreRendered` is set.
    public var renderedScore: Double?

    public init(
        questionID: String,
        referenceScores: [(name: String, score: Double)],
        antiReferenceScores: [(name: String, score: Double)],
        renderedScore: Double? = nil
    ) {
        self.questionID = questionID
        self.referenceScores = referenceScores
        self.antiReferenceScores = antiReferenceScores
        self.renderedScore = renderedScore
        let vals = referenceScores.map { $0.score }
        let mean = vals.reduce(0, +) / Double(max(vals.count, 1))
        let varc = vals.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(vals.count, 1))
        self.referenceMean = mean
        self.referenceStddev = sqrt(varc)
    }

    /// σ-distance of the rendered score from the reference family mean.
    /// Positive = rendered is above the family mean; negative = below.
    /// Returns nil if no rendered score has been set.
    public var sigmaDistance: Double? {
        guard let rendered = renderedScore else { return nil }
        guard referenceStddev > 1e-9 else {
            return rendered == referenceMean ? 0 : Double.infinity * (rendered > referenceMean ? 1 : -1)
        }
        return (rendered - referenceMean) / referenceStddev
    }

    /// True when the anti-reference's score is closer to the rendered
    /// score than the closest reference score. Useful for flagging
    /// "renderer reads like the anti-reference."
    public var renderedClosestToAntiReference: Bool {
        guard let rendered = renderedScore, !antiReferenceScores.isEmpty else { return false }
        let minRefDelta = referenceScores
            .map { abs($0.score - rendered) }
            .min() ?? Double.infinity
        let minAntiDelta = antiReferenceScores
            .map { abs($0.score - rendered) }
            .min() ?? Double.infinity
        return minAntiDelta < minRefDelta
    }
}
