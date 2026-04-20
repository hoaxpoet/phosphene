// VisualizerEngine+Capture — Recording, capture, signal state, and track-change callbacks.

import Audio
import DSP
import Foundation
import Session
import Shared
import os.log

private let captureLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

extension VisualizerEngine {

    // MARK: - Recording and Capture

    /// Toggle MIR feature recording to ~/phosphene_features.csv.
    func toggleRecording() {
        if mirPipeline.isRecording { mirPipeline.stopRecording() } else { mirPipeline.startRecording() }
    }

    /// Toggle feature vector capture to CSV file.
    func toggleCapture() {
        if isCapturing { stopCapture() } else { startCapture() }
    }

    func startCapture() {
        let dir = FileManager.default.temporaryDirectory
        let name = "phosphene_features_\(Int(Date().timeIntervalSince1970)).csv"
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            captureLogger.error("Failed to create capture file: \(url.path)")
            return
        }
        let header = "timestamp,track,artist,genre,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,bass3,mid3,treble3,magMax,key\n"
        handle.write(Data(header.utf8))
        captureHandle = handle
        captureFilePath = url.path
        isCapturing = true
        captureLogger.info("Feature capture started: \(url.path, privacy: .public)")
    }

    func stopCapture() {
        captureHandle?.closeFile()
        captureHandle = nil
        isCapturing = false
        if let path = captureFilePath {
            captureLogger.info("Feature capture stopped: \(path, privacy: .public)")
        }
    }

    /// Write a feature row to the capture file (called from analysis queue).
    func writeCaptureRow(features: [Float], fv: Shared.FeatureVector, magMax: Float, key: String?) {
        guard let handle = captureHandle else { return }
        let track = currentTrack?.title ?? ""
        let artist = currentTrack?.artist ?? ""
        let genre = preFetchedProfile?.genreTags.joined(separator: "|") ?? ""
        let fmt = "%.3f,%@,%@,%@,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
            + "%.5f,%.5f,%.5f,%.5f,%.4f,%.4f,%.4f,%.5f,%@\n"
        let row = String(
            format: fmt,
            Date().timeIntervalSince1970,
            track.replacingOccurrences(of: ",", with: ";"),
            artist.replacingOccurrences(of: ",", with: ";"),
            genre.replacingOccurrences(of: ",", with: "|"),
            features[0],
            features[1],
            features[2],
            features[3],
            features[4],
            features[5],
            features[6],
            features[7],
            features[8],
            features[9],
            fv.bass,
            fv.mid,
            fv.treble,
            magMax,
            key ?? "nil"
        )
        handle.write(Data(row.utf8))
    }

    // MARK: - Signal State

    /// Build the onSignalStateChanged callback. Called on the real-time audio thread —
    /// dispatches to the main actor for @Published property updates.
    func makeSignalStateCallback() -> (AudioSignalState) -> Void {
        return { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioSignalState = state
                self.sessionRecorder?.log("audio signal → \(state)")
                switch state {
                case .silent:
                    captureLogger.info("Audio signal lost — DRM silence or no active audio source")
                case .recovering:
                    captureLogger.info("Audio signal returning — confirming recovery")
                case .active:
                    captureLogger.info("Audio signal restored")
                case .suspect:
                    captureLogger.debug("Audio signal suspect — monitoring for sustained silence")
                }
            }
        }
    }

    // MARK: - Track Change

    /// Build the onTrackChange callback that resets MIR state and kicks off async metadata pre-fetching.
    func makeTrackChangeCallback(fetcher: MetadataPreFetcher) -> (TrackChangeEvent) -> Void {
        let mir = mirPipeline
        return { [weak self] event in
            guard let self else { return }
            mir.currentTrackName = event.current.title ?? ""
            mir.currentArtistName = event.current.artist ?? ""
            Task { @MainActor in
                self.currentTrack = event.current
                self.preFetchedProfile = nil
                let title = event.current.title ?? "?"
                let artist = event.current.artist ?? "?"
                captureLogger.info("Track: \(title) — \(artist)")
                self.sessionRecorder?.log("track → \(title) — \(artist)")
            }
            mir.reset()
            self.pipeline.resetAccumulatedAudioTime()
            let identity = TrackIdentity(
                title: event.current.title ?? "",
                artist: event.current.artist ?? ""
            )
            self.resetStemPipeline(for: identity)
            self.kickoffPreFetch(for: event.current, fetcher: fetcher)
        }
    }

    /// Run the metadata pre-fetcher for a new track and apply BPM/key on the main actor.
    func kickoffPreFetch(for track: TrackMetadata, fetcher: MetadataPreFetcher) {
        Task {
            let profile = await fetcher.prefetch(for: track)
            await MainActor.run {
                self.preFetchedProfile = profile
                if let bpm = profile?.bpm {
                    self.estimatedTempo = bpm
                    captureLogger.info("Using pre-fetched BPM: \(bpm)")
                }
                if let key = profile?.key {
                    self.estimatedKey = key
                    captureLogger.info("Using pre-fetched key: \(key)")
                }
            }
        }
    }
}
