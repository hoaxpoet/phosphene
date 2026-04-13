// Logging — Structured os.Logger instances for each Phosphene subsystem.
// Use these instead of creating ad-hoc loggers throughout the codebase.

import os.log

/// Namespace for shared os.Logger instances.
public enum Logging {
    private static let subsystem = "com.phosphene"

    /// Audio capture, input routing, audio buffers.
    public static let audio = Logger(subsystem: subsystem, category: "audio")

    /// DSP: spectral analysis, beat/onset detection, chroma, MFCCs.
    public static let dsp = Logger(subsystem: subsystem, category: "dsp")

    /// Metal rendering, shader compilation, pipeline management.
    public static let renderer = Logger(subsystem: subsystem, category: "renderer")

    /// AI VJ: anticipation engine, transitions, preset selection.
    public static let orchestrator = Logger(subsystem: subsystem, category: "orchestrator")

    /// CoreML: stem separation, mood classification.
    public static let ml = Logger(subsystem: subsystem, category: "ml")

    /// Metadata: track change detection, pre-fetching, MusicKit bridge.
    public static let metadata = Logger(subsystem: subsystem, category: "metadata")

    /// Session: playlist connection, preview pipeline, session state.
    public static let session = Logger(subsystem: subsystem, category: "session")
}
