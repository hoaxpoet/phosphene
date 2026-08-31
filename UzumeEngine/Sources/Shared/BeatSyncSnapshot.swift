// BeatSyncSnapshot — Per-frame beat-sync diagnostic snapshot for SessionRecorder.
//
// Written by the analysis queue in updateSpectralCartographBeatGrid,
// read by the command-buffer completion handler in VisualizerEngine+InitHelpers.
// NSLock-guarded on VisualizerEngine — never accessed bare.

/// Immutable per-frame capture of beat-grid state for offline latency/phase analysis.
///
/// Written to features.csv alongside FeatureVector at every rendered frame,
/// enabling tools like `Scripts/analyze_beat_sync_latency.py` to correlate
/// visual flash timing against expected beat positions.
public struct BeatSyncSnapshot: Sendable {
    /// Phrase-level ramp 0→1. 0 = no BeatGrid (reactive mode).
    public var barPhase01: Float
    /// Time-signature numerator from the BeatGrid (e.g. 4 for 4/4). 4 in reactive mode.
    public var beatsPerBar: Int
    /// 1-indexed beat position within the bar (1 = downbeat). 1 in reactive mode.
    public var beatInBar: Int
    /// True when `beatInBar == 1`.
    public var isDownbeat: Bool
    /// Session mode: 0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked.
    public var sessionMode: Int
    /// Drift-tracker lock state: 0=unlocked, 1=locking, 2=locked.
    public var lockState: Int
    /// BPM from the cached BeatGrid. 0 when no grid is installed.
    public var gridBPM: Float
    /// Elapsed track time in seconds (MIRPipeline.elapsedSeconds).
    public var playbackTimeS: Float
    /// Drift-tracker correction in milliseconds. 0 when no grid.
    public var driftMs: Float

    public init(
        barPhase01: Float, beatsPerBar: Int, beatInBar: Int, isDownbeat: Bool,
        sessionMode: Int, lockState: Int, gridBPM: Float,
        playbackTimeS: Float, driftMs: Float
    ) {
        self.barPhase01 = barPhase01
        self.beatsPerBar = beatsPerBar
        self.beatInBar = beatInBar
        self.isDownbeat = isDownbeat
        self.sessionMode = sessionMode
        self.lockState = lockState
        self.gridBPM = gridBPM
        self.playbackTimeS = playbackTimeS
        self.driftMs = driftMs
    }

    /// Zero snapshot for frames where no BeatGrid data is available.
    public static let zero = BeatSyncSnapshot(
        barPhase01: 0,
        beatsPerBar: 4,
        beatInBar: 1,
        isDownbeat: false,
        sessionMode: 0,
        lockState: 0,
        gridBPM: 0,
        playbackTimeS: 0,
        driftMs: 0
    )
}
