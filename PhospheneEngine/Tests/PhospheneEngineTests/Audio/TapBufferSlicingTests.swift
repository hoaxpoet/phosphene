// TapBufferSlicingTests — BUG087.3 regression gate.
//
// AVAudioEngine ignores `installTap`'s `bufferSize` and hands the local-file path
// ~0.1 s buffers. Since `processAnalysisFrame` runs once per audio callback, that pinned
// the whole MIR chain at 10 Hz there against 51 Hz on the system tap. The fix slices each
// delivered buffer into `requestedTapFrames`-sized pieces.
//
// The property that has to hold is conservation: **every delivered frame is handed on
// exactly once, and no frame is invented.** Dropping the short tail would silently discard
// audio; zero-padding it would inject a fake transient into the onset detectors. Both are
// asserted here, at the real buffer sizes measured in captures.

import Testing
@testable import Audio

@Suite("Tap buffer slicing conserves frames (BUG087.3)")
struct TapBufferSlicingTests {

    /// Walk the same loop `deliverSliced` runs and collect the slice lengths.
    private func slices(frames: Int, sliceFrames: Int) -> [Int] {
        var out: [Int] = []
        var offset = 0
        while true {
            let take = TapBufferSlicing.frameCount(
                frames: frames, sliceFrames: sliceFrames, offset: offset
            )
            guard take > 0 else { break }
            out.append(take)
            offset += take
            if out.count > 10_000 { break }   // loop-safety, never reached in practice
        }
        return out
    }

    // MARK: - Conservation

    @Test("Slices sum to the buffer, at every measured real buffer size")
    func slicesSumToTheBuffer() {
        // 4410 = 0.1 s at 44.1 kHz, 4808/4800 = 0.1 s at 48 kHz (the local-file regime),
        // 939 ≈ the system tap's own buffer, 1024 = exactly one slice.
        for frames in [4410, 4800, 4808, 939, 1024, 1, 1023, 1025] {
            let parts = slices(frames: frames, sliceFrames: 1024)
            #expect(parts.reduce(0, +) == frames,
                    "frames=\(frames) sliced to \(parts) summing \(parts.reduce(0, +))")
        }
    }

    @Test("No slice is empty and none exceeds the slice size")
    func slicesAreWellFormed() {
        for frames in [4410, 4800, 4808, 939, 1024, 1, 1023, 1025] {
            for part in slices(frames: frames, sliceFrames: 1024) {
                #expect(part > 0, "empty slice for frames=\(frames)")
                #expect(part <= 1024, "oversized slice \(part) for frames=\(frames)")
            }
        }
    }

    @Test("The tail is short, not padded — padding would fake a transient")
    func tailIsShortNotPadded() {
        // 4808 = 4×1024 + 712. The last slice must be 712, not 1024.
        let parts = slices(frames: 4808, sliceFrames: 1024)
        #expect(parts.count == 5)
        #expect(parts.dropLast().allSatisfy { $0 == 1024 })
        #expect(parts.last == 712)
    }

    // MARK: - The rate this buys

    @Test("A 0.1 s buffer yields enough slices to clear the 40 Hz target")
    func sliceCountClearsTheRateTarget() {
        // BUG-087's done-when is ≥ 40 Hz. A 0.1 s buffer sliced at 1024 frames gives
        // 5 analysis frames per 100 ms at 48 kHz ⇒ ~47 Hz; 5 per 100 ms at 44.1 kHz ⇒ ~43 Hz.
        for (frames, rate) in [(4800, 48_000.0), (4410, 44_100.0)] {
            let parts = slices(frames: frames, sliceFrames: 1024)
            let bufferSeconds = Double(frames) / rate
            let hz = Double(parts.count) / bufferSeconds
            #expect(hz >= 40.0, "frames=\(frames) rate=\(rate) → \(hz) Hz")
        }
    }

    // MARK: - Degenerate inputs

    @Test("Zero-length and invalid inputs produce no slices rather than looping")
    func degenerateInputsProduceNothing() {
        #expect(slices(frames: 0, sliceFrames: 1024).isEmpty)
        #expect(TapBufferSlicing.frameCount(
            frames: 100, sliceFrames: 0, offset: 0) == 0)
        #expect(TapBufferSlicing.frameCount(
            frames: 100, sliceFrames: 1024, offset: 100) == 0)
        #expect(TapBufferSlicing.frameCount(
            frames: 100, sliceFrames: 1024, offset: 200) == 0)
    }
}
