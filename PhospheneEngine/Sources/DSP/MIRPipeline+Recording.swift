import Foundation
import os.log

private let recordingLogger = Logger(subsystem: "com.phosphene.dsp", category: "MIRPipeline")

extension MIRPipeline {

    // MARK: - Recording Mode

    /// Start recording feature vectors to CSV at ~/phosphene_features.csv.
    /// Writes one row per second with timestamp + 10 features.
    public func startRecording() {
        let path = NSHomeDirectory() + "/phosphene_features.csv"
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            recordingLogger.error("Failed to create recording file: \(path)")
            return
        }
        let header = "timestamp,track,artist,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,stableKey,stableBPM,"
            + "valence,arousal\n"
        handle.write(Data(header.utf8))
        recordingHandle = handle
        lastRecordTime = elapsedSeconds
        recordingLogger.info("Recording started: \(path)")
    }

    /// Stop recording and close the file.
    public func stopRecording() {
        recordingHandle?.closeFile()
        recordingHandle = nil
        recordingLogger.info("Recording stopped")
    }

    /// Write a feature row if recording and throttle interval has passed.
    /// Called from process() with the current feature values.
    func writeRecordingRow(
        energy: BandEnergyProcessor.Result,
        centroid: Float,
        flux: Float,
        majorCorr: Float,
        minorCorr: Float
    ) {
        guard let handle = recordingHandle else { return }
        guard elapsedSeconds - lastRecordTime >= 1.0 else { return }
        lastRecordTime = elapsedSeconds
        let track = currentTrackName.replacingOccurrences(of: ",", with: ";")
        let artist = currentArtistName.replacingOccurrences(of: ",", with: ";")
        let row = String(
            format: "%.1f,%@,%@,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%@,%.1f,,\n",
            elapsedSeconds,
            track,
            artist,
            energy.subBass,
            energy.lowBass,
            energy.lowMid,
            energy.midHigh,
            energy.highMid,
            energy.high,
            centroid,
            flux,
            majorCorr,
            minorCorr,
            stableKey ?? "",
            stableBPM ?? 0
        )
        handle.write(Data(row.utf8))
    }
}
