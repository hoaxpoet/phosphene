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

    // MARK: - Slice count — the COMPUTATION rate, which is not what a preset sees

    @Test("A 0.1 s buffer yields 5 analysis frames — a ~47 Hz computation rate")
    func sliceCountPerBuffer() {
        // ⚠ This asserts the COMPUTATION rate, not the rate a preset observes.
        //
        // An earlier version of this test asserted `hz >= 40.0` against BUG-087's
        // done-when, and it passed — while the live capture measured **16.4 Hz**
        // effective. All five slices of a buffer complete within microseconds of each
        // other, so the render loop samples roughly 1.6 of them as distinct values and
        // the rest are superseded before anything reads them. The binding constraint is
        // how often audio ARRIVES (every 100 ms on this path), not how finely it is cut.
        //
        // The assertion is kept because slice count is a real property worth pinning —
        // but it is named for what it measures, so nobody reads a green tick here as
        // evidence the preset-facing rate cleared 40 Hz. It did not.
        for (frames, rate) in [(4800, 48_000.0), (4410, 44_100.0)] {
            let parts = slices(frames: frames, sliceFrames: 1024)
            #expect(parts.count == 5, "frames=\(frames) → \(parts.count) slices")
            let computationHz = Double(parts.count) / (Double(frames) / rate)
            #expect(computationHz >= 40.0, "computation rate \(computationHz) Hz")
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
