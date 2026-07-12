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
            guard let self else { return }
            // ASH.1: feed the health monitor the tap signal state. Dead-tap
            // detection only applies to process-tap modes — local-file silence
            // is real musical silence, not a broken tap.
            var tapMode = false
            if #available(macOS 14.2, *), let router = self.router as? AudioInputRouter {
                switch router.activeMode {
                case .systemAudio, .application: tapMode = true
                default: tapMode = false
                }
            }
            self.signalHealthMonitor.updateContext(signalState: state, tapModeActive: tapMode)
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
            // BUG-020 diagnostic — synchronous log of every callback invocation.
            // The async `Task { @MainActor }` block below logs "track → ..." but
            // can be delayed/dropped if the MainActor is busy. The destructive
            // resets (`mir.reset()`, `pipeline.resetAccumulatedAudioTime()`) fire
            // synchronously regardless. This diagnostic line captures the
            // "callback fired" moment with current + previous identity so a
            // spurious mid-track callback (suspected source of mid-track state
            // resets observed in session 2026-05-28T18-31-06Z) is visible in
            // session.log even when the async log line goes missing.
            let curTitle = event.current.title ?? "?"
            let curArtist = event.current.artist ?? "?"
            let prevTitle = event.previous?.title ?? "<nil>"
            let prevArtist = event.previous?.artist ?? "<nil>"
            let sameTrack = (event.previous?.title == event.current.title
                && event.previous?.artist == event.current.artist)
            self.sessionRecorder?.log(
                "WIRING: trackChangeCallback FIRED "
                + "current='\(curTitle)' currentArtist='\(curArtist)' "
                + "previous='\(prevTitle)' previousArtist='\(prevArtist)' "
                + "sameTrack=\(sameTrack)")
            // BUG-020 fix — gate ALL per-track-change side effects on title
            // change. Diagnosis: Spotify's metadata publisher emits a transitional
            // event during track-to-track transitions where the ARTIST updates
            // before the TITLE. The callback receives e.g. `current='Love Rehab'
            // currentArtist='Pink Floyd' previous='Love Rehab' previousArtist=
            // 'Chaim'` — a track that doesn't exist (`identity.spotifyID=nil
            // identity.duration=nil resolution=partialFallback`). Pre-fix the
            // callback fired its destructive resets anyway: `mir.reset()`,
            // `resetAccumulatedAudioTime()`, `resetStemPipeline(...)`. The real
            // track change (Money) then arrived 2 seconds later, by which point
            // mid-track state was destroyed → visible flicker / "idling".
            // Reproduced in session 2026-05-28T19-21-18Z, captured under
            // [BUG-020.diag] (commit 594e4181).
            //
            // Title-change gate is the smallest reliable signal: same-title
            // events are spurious by construction (a real track change always
            // produces a different title; covers/remasters with identical titles
            // are vanishingly rare in practice and would only produce
            // "no visible reset at the cover boundary," not a destructive bug).
            // Returning early also skips the orchestrator wire updates +
            // metadata pre-fetch, which would otherwise propagate the bad
            // metadata downstream.
            if event.previous?.title == event.current.title {
                self.sessionRecorder?.log(
                    "WIRING: trackChangeCallback SUPPRESSED (same title) "
                    + "current='\(curTitle)' currentArtist='\(curArtist)' "
                    + "previous='\(prevTitle)' previousArtist='\(prevArtist)'")
                return
            }
            mir.currentTrackName = event.current.title ?? ""
            mir.currentArtistName = event.current.artist ?? ""

            // BUG-015: resolve the live track's plan index on the audio thread
            // and store it under `orchestratorLock` for the analysis-queue
            // `runOrchestratorLiveUpdate(mir:)` wire. The MainActor field
            // `currentTrackIndex` is set inside the Task below for SwiftUI
            // consumers; both reflect the same plan walk so they stay in lock-
            // step. Resolved before the MainActor task so the orchestrator
            // wire sees the new index on the next analysis tick (~3 Hz).
            // `indexInLivePlan(matching:)` itself is non-actor-isolated and
            // takes `orchestratorLock` internally.
            let resolvedPlanIndex = self.indexInLivePlan(matching: event.current)
            self.orchestratorLock.withLock {
                self.liveTrackPlanIndex = resolvedPlanIndex
                // BUG-015 diagnostic: reset the per-track wire-active log
                // latch so the next analysis tick that reaches
                // `applyLiveUpdate(...)` produces exactly one diagnostic
                // line for this new track. Pairs with the latch set in
                // `runOrchestratorLiveUpdate(mir:)`.
                self.orchestratorWireLoggedThisTrack = false
                // LFPLAN.3: new track → plan resumes (clear the manual hold) and the
                // first planned segment applies (clear the last-applied marker).
                self.manualPresetOverrideThisTrack = false
                self.lastAppliedPlannedPresetID = nil
                // LFPLAN.4: reset the min-dwell clock so the new track's first apply lands promptly.
                self.lastPlannedApplyTrackTime = 0
            }

            // LF.6.streaming-S5: resolve the canonical identity BEFORE the
            // MainActor block so `streamingArtworkPublisher.update(for:)`
            // sees the full identity (with `spotifyArtworkURL` hint set by
            // S1) rather than a partial title+artist one. Identity
            // resolution is non-isolated; it acquires `orchestratorLock`
            // internally and is safe from any thread.
            let title = event.current.title ?? ""
            let artist = event.current.artist ?? ""
            let partialIdentity = TrackIdentity(title: title, artist: artist)
            // BUG-006.2 fix (cause 2): resolve the canonical TrackIdentity from
            // livePlan when one is present. Streaming metadata only carries
            // title+artist; the PlannedSession was constructed with full
            // identities (duration + spotifyID + spotifyPreviewURL hint) so a
            // partial-identity hash would miss the cache key SessionPreparer
            // stored. Falls back to the partial identity for ad-hoc/reactive
            // sessions where livePlan is nil.
            let identity = self.canonicalTrackIdentity(matching: partialIdentity) ?? partialIdentity

            Task { @MainActor in
                // R3.1 (PUB.9): ONE paired publish — title + plan index
                // (QR.4 / D-091) together, with artwork cleared in the same
                // tick so a prior LF session's bytes never dress the new
                // streaming title (LF.6.fix.1 / BUG-024); the LF.6.streaming
                // async fetch then lands the real bytes on a later tick.
                // The stale pre-fetched profile drops with it — the new
                // track's kickoffPreFetch repopulates.
                self.nowPlaying.publishTrack(
                    event.current, index: resolvedPlanIndex, artwork: .some(nil))
                self.streamingArtworkPublisher?.update(for: identity)
                self.nowPlaying.setProfile(nil)
                let displayTitle = event.current.title ?? "?"
                let displayArtist = event.current.artist ?? "?"
                captureLogger.info("Track: \(displayTitle) — \(displayArtist)")
                self.sessionRecorder?.log("track → \(displayTitle) — \(displayArtist)")
            }
            mir.reset()
            self.pipeline.resetAccumulatedAudioTime()
            // BUG-016 fix (2026-05-26): persist the resolved identity so
            // `applyPreset` can refresh per-track preset state (Lumen Mosaic
            // palette) when the user activates a preset mid-track. Before this
            // line existed, the identity escaped the closure scope and was only
            // available to `resetStemPipeline` below — so any preset whose
            // per-track GPU payload is wired through `resetStemPipeline` would
            // render against zero-filled defaults until the next track change.
            // Must precede `resetPerTrackPresetState()` (the Skein reseed
            // derives from it).
            self.lastResolvedTrackIdentity = identity
            // BUG-044: Nimbus settle (NB.4) + Skein §1.5 canvas wipe + reseed, shared with the
            // local-file advance path. See `resetPerTrackPresetState` in VisualizerEngine+Presets.
            self.resetPerTrackPresetState()
            self.logTrackChangeObserved(event: event, identity: identity)
            self.resetStemPipeline(for: identity, caller: .trackChange)
            self.kickoffPreFetch(for: event.current, fetcher: fetcher)
        }
    }

    /// Run the metadata pre-fetcher for a new track and apply BPM/key on the main actor.
    func kickoffPreFetch(for track: TrackMetadata, fetcher: MetadataPreFetcher) {
        Task {
            let profile = await fetcher.prefetch(for: track)
            await MainActor.run {
                self.nowPlaying.setProfile(profile)
                if let bpm = profile?.bpm {
                    self.estimatedTempo = bpm
                    captureLogger.info("Using pre-fetched BPM: \(bpm)")
                }
                if let key = profile?.key {
                    self.estimatedKey = key
                    captureLogger.info("Using pre-fetched key: \(key)")
                }
                // Round 25 (2026-05-15): metadata-driven meter override.
                // The ML beat detector's auto-detected `beatsPerBar` is
                // sometimes wrong on odd time-signature tracks (e.g.
                // Money classified as 2/X instead of 7/X). When the
                // external metadata source returns a `time_signature`,
                // override the live drift tracker's meter so wave
                // cycling on bar-locked presets (Ferrofluid Ocean) uses
                // the correct value. No-op when the field is nil
                // (source doesn't expose it) or matches the current
                // value.
                if let timeSignature = profile?.timeSignature {
                    self.mirPipeline.liveDriftTracker
                        .overrideBeatsPerBar(timeSignature)
                    captureLogger.info(
                        "Using pre-fetched time signature: \(timeSignature)/X"
                    )
                }
            }
        }
    }
}
