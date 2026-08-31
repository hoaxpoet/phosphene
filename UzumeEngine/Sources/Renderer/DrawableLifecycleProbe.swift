// DrawableLifecycleProbe — BUG-085 / HANG.1 drawable-pool instrumentation.

import Foundation
import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - Snapshot

/// Point-in-time drawable lifecycle counters emitted to `session.log` by the app watchdog.
public struct DrawableLifecycleSnapshot: Sendable, Equatable {
    public let framesStarted: UInt64
    public let descriptorRequests: UInt64
    public let descriptorResolutions: UInt64
    public let drawableRequests: UInt64
    public let drawableResolutions: UInt64
    public let uniqueDrawablesAcquired: UInt64
    public let uniqueDrawablesPresented: UInt64
    public let commandBuffersCommitted: UInt64
    public let commandBuffersCompleted: UInt64
    public let commandBufferFailures: UInt64
    public let unpresentedAcquisitions: UInt64
    public let pendingRequestFrame: UInt64?
    public let pendingRequestSite: String?
    public let pendingRequestSeconds: TimeInterval?

    /// Compact durable representation for the HANG.1 session artifact.
    public var logDescription: String {
        let pending: String
        if let frame = pendingRequestFrame,
           let site = pendingRequestSite,
           let seconds = pendingRequestSeconds {
            pending = "pending=frame:\(frame),site:\(site),age_ms:\(Int(seconds * 1_000))"
        } else {
            pending = "pending=none"
        }
        return "frames=\(framesStarted) descriptor=\(descriptorResolutions)/\(descriptorRequests) "
            + "drawable=\(drawableResolutions)/\(drawableRequests) "
            + "unique_presented=\(uniqueDrawablesPresented)/\(uniqueDrawablesAcquired) "
            + "command_completed=\(commandBuffersCompleted)/\(commandBuffersCommitted) "
            + "failures=\(commandBufferFailures) unpresented=\(unpresentedAcquisitions) \(pending)"
    }
}

// MARK: - Probe

/// Lock-protected state machine that correlates drawable access with the command buffer
/// responsible for presenting it. Instrumentation only: it never changes render decisions.
final class DrawableLifecycleProbe: @unchecked Sendable {
    enum RequestKind {
        case renderPassDescriptor
        case drawable
    }

    private struct FrameState {
        let frame: UInt64
        var acquiredDrawableIDs: Set<ObjectIdentifier> = []
        var presentedDrawableIDs: Set<ObjectIdentifier> = []
    }

    private struct PendingRequest {
        let frame: UInt64
        let site: String
        let startedAt: TimeInterval
    }

    private struct State {
        var nextFrame: UInt64 = 0
        var frames: [ObjectIdentifier: FrameState] = [:]
        var framesStarted: UInt64 = 0
        var descriptorRequests: UInt64 = 0
        var descriptorResolutions: UInt64 = 0
        var drawableRequests: UInt64 = 0
        var drawableResolutions: UInt64 = 0
        var uniqueDrawablesAcquired: UInt64 = 0
        var uniqueDrawablesPresented: UInt64 = 0
        var commandBuffersCommitted: UInt64 = 0
        var commandBuffersCompleted: UInt64 = 0
        var commandBufferFailures: UInt64 = 0
        var unpresentedAcquisitions: UInt64 = 0
        var pendingRequest: PendingRequest?
    }

    private let lock = NSLock()
    private var state = State()

    func beginFrame(commandBufferID: ObjectIdentifier) {
        lock.withLock {
            state.nextFrame += 1
            state.framesStarted += 1
            state.frames[commandBufferID] = FrameState(frame: state.nextFrame)
        }
    }

    func beginRequest(
        commandBufferID: ObjectIdentifier,
        kind: RequestKind,
        site: String,
        now: TimeInterval
    ) {
        lock.withLock {
            switch kind {
            case .renderPassDescriptor:
                state.descriptorRequests += 1
            case .drawable:
                state.drawableRequests += 1
            }
            guard let frame = state.frames[commandBufferID]?.frame else { return }
            state.pendingRequest = PendingRequest(frame: frame, site: site, startedAt: now)
        }
    }

    func endRequest(
        commandBufferID: ObjectIdentifier,
        kind: RequestKind,
        resolved: Bool,
        drawableID: ObjectIdentifier? = nil
    ) {
        lock.withLock {
            state.pendingRequest = nil
            guard resolved else { return }
            switch kind {
            case .renderPassDescriptor:
                state.descriptorResolutions += 1
            case .drawable:
                state.drawableResolutions += 1
            }
            guard let drawableID,
                  var frame = state.frames[commandBufferID] else { return }
            if frame.acquiredDrawableIDs.insert(drawableID).inserted {
                state.uniqueDrawablesAcquired += 1
            }
            state.frames[commandBufferID] = frame
        }
    }

    func recordPresent(commandBufferID: ObjectIdentifier, drawableID: ObjectIdentifier) {
        lock.withLock {
            guard var frame = state.frames[commandBufferID] else { return }
            if frame.presentedDrawableIDs.insert(drawableID).inserted {
                state.uniqueDrawablesPresented += 1
            }
            state.frames[commandBufferID] = frame
        }
    }

    func recordCommit(commandBufferID: ObjectIdentifier) {
        lock.withLock {
            guard state.frames[commandBufferID] != nil else { return }
            state.commandBuffersCommitted += 1
        }
    }

    func recordCompletion(commandBufferID: ObjectIdentifier, succeeded: Bool) {
        lock.withLock {
            guard let frame = state.frames.removeValue(forKey: commandBufferID) else { return }
            state.commandBuffersCompleted += 1
            if !succeeded {
                state.commandBufferFailures += 1
            }
            state.unpresentedAcquisitions += UInt64(
                frame.acquiredDrawableIDs.subtracting(frame.presentedDrawableIDs).count
            )
        }
    }

    func snapshot(now: TimeInterval) -> DrawableLifecycleSnapshot {
        lock.withLock {
            let pendingSeconds = state.pendingRequest.map { max(0, now - $0.startedAt) }
            return DrawableLifecycleSnapshot(
                framesStarted: state.framesStarted,
                descriptorRequests: state.descriptorRequests,
                descriptorResolutions: state.descriptorResolutions,
                drawableRequests: state.drawableRequests,
                drawableResolutions: state.drawableResolutions,
                uniqueDrawablesAcquired: state.uniqueDrawablesAcquired,
                uniqueDrawablesPresented: state.uniqueDrawablesPresented,
                commandBuffersCommitted: state.commandBuffersCommitted,
                commandBuffersCompleted: state.commandBuffersCompleted,
                commandBufferFailures: state.commandBufferFailures,
                unpresentedAcquisitions: state.unpresentedAcquisitions,
                pendingRequestFrame: state.pendingRequest?.frame,
                pendingRequestSite: state.pendingRequest?.site,
                pendingRequestSeconds: pendingSeconds
            )
        }
    }
}

// MARK: - RenderPipeline bridge

extension RenderPipeline {
    /// Current HANG.1 lifecycle counters. Safe to read from the watchdog task.
    public func drawableLifecycleSnapshot() -> DrawableLifecycleSnapshot {
        drawableLifecycleProbe.snapshot(now: ProcessInfo.processInfo.systemUptime)
    }

    @MainActor
    func captureRenderedFrame(
        from view: MTKView,
        features: FeatureVector,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let hook = onFrameRendered,
              let drawable = instrumentedDrawable(
                  from: view, commandBuffer: commandBuffer, site: "draw.captureHook") else { return }
        let stems = stemFeaturesLock.withLock { latestStemFeatures }
        hook(drawable.texture, features, stems, commandBuffer)
    }

    func recordDrawableLifecycleCompletion(
        commandBufferID: ObjectIdentifier,
        commandBuffer: MTLCommandBuffer
    ) {
        drawableLifecycleProbe.recordCompletion(
            commandBufferID: commandBufferID,
            succeeded: commandBuffer.status == .completed
        )
    }

    @MainActor
    func instrumentedRenderPassDescriptor(
        from view: MTKView,
        commandBuffer: MTLCommandBuffer,
        site: String
    ) -> MTLRenderPassDescriptor? {
        let commandBufferID = ObjectIdentifier(commandBuffer as AnyObject)
        drawableLifecycleProbe.beginRequest(
            commandBufferID: commandBufferID,
            kind: .renderPassDescriptor,
            site: site,
            now: ProcessInfo.processInfo.systemUptime
        )
        let descriptor = view.currentRenderPassDescriptor
        drawableLifecycleProbe.endRequest(
            commandBufferID: commandBufferID,
            kind: .renderPassDescriptor,
            resolved: descriptor != nil
        )
        return descriptor
    }

    @MainActor
    func instrumentedDrawable(
        from view: MTKView,
        commandBuffer: MTLCommandBuffer,
        site: String
    ) -> CAMetalDrawable? {
        let commandBufferID = ObjectIdentifier(commandBuffer as AnyObject)
        drawableLifecycleProbe.beginRequest(
            commandBufferID: commandBufferID,
            kind: .drawable,
            site: site,
            now: ProcessInfo.processInfo.systemUptime
        )
        let drawable = view.currentDrawable
        drawableLifecycleProbe.endRequest(
            commandBufferID: commandBufferID,
            kind: .drawable,
            resolved: drawable != nil,
            drawableID: drawable.map { ObjectIdentifier($0 as AnyObject) }
        )
        return drawable
    }

    @MainActor
    func instrumentedPresent(_ drawable: CAMetalDrawable, on commandBuffer: MTLCommandBuffer) {
        drawableLifecycleProbe.recordPresent(
            commandBufferID: ObjectIdentifier(commandBuffer as AnyObject),
            drawableID: ObjectIdentifier(drawable as AnyObject)
        )
        commandBuffer.present(drawable)
    }
}
