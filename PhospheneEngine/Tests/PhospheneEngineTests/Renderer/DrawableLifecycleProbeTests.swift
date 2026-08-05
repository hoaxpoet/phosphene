// DrawableLifecycleProbeTests — HANG.1 state-machine guards.

import Foundation
import Testing
@testable import Renderer

private final class DrawableProbeToken {}

@Test func drawableLifecycleProbe_balancedFrame_countsUniqueDrawableOnce() {
    let probe = DrawableLifecycleProbe()
    let commandBufferToken = DrawableProbeToken()
    let drawableToken = DrawableProbeToken()
    let commandBuffer = ObjectIdentifier(commandBufferToken)
    let drawable = ObjectIdentifier(drawableToken)

    probe.beginFrame(commandBufferID: commandBuffer)
    probe.beginRequest(
        commandBufferID: commandBuffer,
        kind: .renderPassDescriptor,
        site: "test.descriptor",
        now: 1
    )
    probe.endRequest(commandBufferID: commandBuffer, kind: .renderPassDescriptor, resolved: true)

    for _ in 0..<2 {
        probe.beginRequest(
            commandBufferID: commandBuffer,
            kind: .drawable,
            site: "test.drawable",
            now: 1
        )
        probe.endRequest(
            commandBufferID: commandBuffer,
            kind: .drawable,
            resolved: true,
            drawableID: drawable
        )
    }
    probe.recordPresent(commandBufferID: commandBuffer, drawableID: drawable)
    probe.recordCommit(commandBufferID: commandBuffer)
    probe.recordCompletion(commandBufferID: commandBuffer, succeeded: true)

    let snapshot = probe.snapshot(now: 2)
    #expect(snapshot.framesStarted == 1)
    #expect(snapshot.descriptorRequests == 1)
    #expect(snapshot.descriptorResolutions == 1)
    #expect(snapshot.drawableRequests == 2)
    #expect(snapshot.drawableResolutions == 2)
    #expect(snapshot.uniqueDrawablesAcquired == 1)
    #expect(snapshot.uniqueDrawablesPresented == 1)
    #expect(snapshot.commandBuffersCommitted == 1)
    #expect(snapshot.commandBuffersCompleted == 1)
    #expect(snapshot.commandBufferFailures == 0)
    #expect(snapshot.unpresentedAcquisitions == 0)
    #expect(snapshot.pendingRequestFrame == nil)
}

@Test func drawableLifecycleProbe_pendingRequest_exposesSiteAndAge() {
    let probe = DrawableLifecycleProbe()
    let commandBufferToken = DrawableProbeToken()
    let commandBuffer = ObjectIdentifier(commandBufferToken)

    probe.beginFrame(commandBufferID: commandBuffer)
    probe.beginRequest(
        commandBufferID: commandBuffer,
        kind: .drawable,
        site: "feedback.particles.descriptor",
        now: 10
    )

    let snapshot = probe.snapshot(now: 10.75)
    #expect(snapshot.pendingRequestFrame == 1)
    #expect(snapshot.pendingRequestSite == "feedback.particles.descriptor")
    #expect(snapshot.pendingRequestSeconds == 0.75)
    #expect(snapshot.logDescription.contains("age_ms:750"))
}

@Test func drawableLifecycleProbe_failedUnpresentedFrame_recordsBothSignals() {
    let probe = DrawableLifecycleProbe()
    let commandBufferToken = DrawableProbeToken()
    let drawableToken = DrawableProbeToken()
    let commandBuffer = ObjectIdentifier(commandBufferToken)
    let drawable = ObjectIdentifier(drawableToken)

    probe.beginFrame(commandBufferID: commandBuffer)
    probe.beginRequest(
        commandBufferID: commandBuffer,
        kind: .drawable,
        site: "test.drawable",
        now: 1
    )
    probe.endRequest(
        commandBufferID: commandBuffer,
        kind: .drawable,
        resolved: true,
        drawableID: drawable
    )
    probe.recordCommit(commandBufferID: commandBuffer)
    probe.recordCompletion(commandBufferID: commandBuffer, succeeded: false)

    let snapshot = probe.snapshot(now: 2)
    #expect(snapshot.commandBufferFailures == 1)
    #expect(snapshot.unpresentedAcquisitions == 1)
    #expect(snapshot.uniqueDrawablesAcquired == 1)
    #expect(snapshot.uniqueDrawablesPresented == 0)
}
