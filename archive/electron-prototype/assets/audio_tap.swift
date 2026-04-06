import ScreenCaptureKit
import CoreMedia
import Foundation

class AudioTap: NSObject, SCStreamDelegate, SCStreamOutput {
    var stream: SCStream?
    
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            FileHandle.standardError.write("No display\n".data(using: .utf8)!)
            return
        }
        
        FileHandle.standardError.write("Found \(content.displays.count) displays\n".data(using: .utf8)!)
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = false
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream!.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        try await stream!.startCapture()
        FileHandle.standardError.write("Capture started - streaming PCM to stdout\n".data(using: .utf8)!)
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let ptr = dataPointer else { return }
        let data = Data(bytes: ptr, count: length)
        FileHandle.standardOutput.write(data)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write("Stream error: \(error)\n".data(using: .utf8)!)
    }
}

let tap = AudioTap()
signal(SIGTERM, SIG_IGN)
signal(SIGINT) { _ in exit(0) }

Task {
    do {
        try await tap.start()
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

RunLoop.main.run()
