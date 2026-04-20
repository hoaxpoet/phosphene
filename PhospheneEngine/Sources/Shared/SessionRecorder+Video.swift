import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import os.log

private let videoLogger = Logger(subsystem: "com.phosphene", category: "SessionRecorder")

extension SessionRecorder {

    // MARK: - Video encoding

    func appendVideoFrame(from tex: MTLTexture, wallclock: CFAbsoluteTime) {
        let width = tex.width
        let height = tex.height

        guard initializeVideoWriterIfNeeded(width: width, height: height) else { return }

        let lockedW = writerLockedDims?.width ?? 0
        let lockedH = writerLockedDims?.height ?? 0
        if lockedW != width || lockedH != height {
            guard handleDimensionMismatch(
                width: width,
                height: height,
                lockedW: lockedW,
                lockedH: lockedH
            ) else { return }
        }

        guard let adaptor = pixelAdaptor,
              let pool = adaptor.pixelBufferPool,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else { return }

        var maybeBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = maybeBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        tex.getBytes(base, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        if videoStartTime == nil {
            let startTime = CMTime(value: CMTimeValue(wallclock * 1_000_000), timescale: 1_000_000)
            videoStartTime = startTime
            videoWriter?.startSession(atSourceTime: startTime)
        }
        let pts = CMTime(value: CMTimeValue(wallclock * 1_000_000), timescale: 1_000_000)
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    private func initializeVideoWriterIfNeeded(width: Int, height: Int) -> Bool {
        guard videoWriter == nil else { return true }
        if let last = lastObservedDims, last.width == width, last.height == height {
            sameDimsStreak += 1
        } else {
            lastObservedDims = (width, height)
            sameDimsStreak = 1
        }
        guard sameDimsStreak >= videoSizeStableThreshold else { return false }
        guard setupVideoWriter(width: width, height: height) else { return false }
        writerLockedDims = (width, height)
        writeLogLine("video writer locked to \(width)x\(height) after \(sameDimsStreak) stable frames")
        return true
    }

    private func handleDimensionMismatch(
        width: Int, height: Int, lockedW: Int, lockedH: Int
    ) -> Bool {
        skippedFrameCount += 1
        if let meta = mismatchedDims, meta.width == width, meta.height == height {
            mismatchedDimsStreak += 1
        } else {
            mismatchedDims = (width, height)
            mismatchedDimsStreak = 1
        }
        if mismatchedDimsStreak >= writerRelockThreshold {
            writeLogLine("video writer relocking: drawable stabilised at \(width)x\(height),"
                + " was locked at \(lockedW)x\(lockedH) (skipped \(skippedFrameCount) frames)")
            tearDownVideoWriter()
            if setupVideoWriter(width: width, height: height) {
                writerLockedDims = (width, height)
                writeLogLine("video writer relocked to \(width)x\(height)")
                skippedFrameCount = 0
                mismatchedDims = nil
                mismatchedDimsStreak = 0
                return true
            }
            writeLogLine("video writer relock FAILED — video output disabled")
            return false
        }
        if skippedFrameCount % 30 == 1 {
            writeLogLine("video frame skipped: drawable \(width)x\(height)"
                + " != writer \(lockedW)x\(lockedH) (skip count: \(skippedFrameCount))")
        }
        return false
    }

    func tearDownVideoWriter() {
        videoInput?.markAsFinished()
        if let writer = videoWriter, writer.status == .writing { writer.cancelWriting() }
        videoWriter = nil
        videoInput = nil
        pixelAdaptor = nil
        videoStartTime = nil
        lastVideoFrameTime = 0
        try? FileManager.default.removeItem(at: videoURL)
    }

    private func setupVideoWriter(width: Int, height: Int) -> Bool {
        do {
            let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let pbAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: pbAttributes
            )
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            guard writer.startWriting() else {
                videoLogger.error("AVAssetWriter.startWriting failed: \(writer.error?.localizedDescription ?? "nil")")
                return false
            }
            self.videoWriter = writer
            self.videoInput = input
            self.pixelAdaptor = adaptor
            return true
        } catch {
            videoLogger.error("AVAssetWriter init failed: \(error.localizedDescription)")
            return false
        }
    }
}
