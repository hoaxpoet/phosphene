// TapBufferSlicing — how a delivered tap buffer is cut into analysis frames (BUG087.3).
//
// Deliberately its own type rather than a member of `LocalFilePlaybackProvider`: the
// arithmetic depends on nothing from AVFoundation, and living inside a type gated to
// macOS 14.2 forced that gate onto its tests, where it collides with swift-testing's
// `@Test` macro. Separating it also makes the property the fix rests on — frame
// conservation — testable without constructing an audio provider at all.

import Foundation

// MARK: - Tap Buffer Slicing

/// Slicing arithmetic for handing one delivered audio buffer to the analysis callback in
/// several smaller pieces.
///
/// AVAudioEngine ignores `installTap`'s `bufferSize` request and delivers ~0.1 s buffers,
/// and `processAnalysisFrame` runs once per callback — so one call per buffer pinned the
/// local-file MIR chain at 10 Hz against 51 Hz on the system tap (BUG-087).
public enum TapBufferSlicing {

    /// Frames to hand over for the slice starting at `offset`, or 0 when the buffer is
    /// exhausted.
    ///
    /// Returns a *length*, never a buffer, so the audio-thread loop slices by offsetting
    /// into an already-interleaved scratch rather than allocating per slice (the BUG-036
    /// real-time constraint). The final slice is short rather than zero-padded — padding a
    /// tail with silence would inject a fake transient into the onset detectors.
    public static func frameCount(frames: Int, sliceFrames: Int, offset: Int) -> Int {
        guard frames > offset, sliceFrames > 0, offset >= 0 else { return 0 }
        return min(sliceFrames, frames - offset)
    }
}
