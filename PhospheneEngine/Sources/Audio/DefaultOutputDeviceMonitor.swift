// DefaultOutputDeviceMonitor — CLEAN.1.5 / GAP-1.
//
// Watches `kAudioHardwarePropertyDefaultOutputDevice` on the Core Audio system
// object and invokes a callback whenever the default output device changes
// (AirPods connect, monitor unplug, DAC swap — the most common mid-session
// event). `SystemAudioCapture` uses it to reinstall its process tap so the
// visualizer keeps receiving audio instead of silently freezing on the dead
// device.
//
// Listening to a read-only system property requires no audio-capture (TCC)
// permission, so this is unit-testable headlessly — unlike the tap itself.

import Foundation
import CoreAudio
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "DefaultOutputDeviceMonitor")

/// Fires a callback when the system default output device changes.
public final class DefaultOutputDeviceMonitor: @unchecked Sendable {

    // MARK: - State

    /// Serial queue the Core Audio listener block is delivered on.
    private let queue = DispatchQueue(label: "com.phosphene.audio.defaultOutputMonitor")

    /// The registered listener block. Non-nil while monitoring. Retained so the
    /// exact same block can be passed to `AudioObjectRemovePropertyListenerBlock`.
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private let lock = NSLock()

    /// The property we watch: the system-wide default output device.
    private static var propertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    public init() {}

    // MARK: - Query

    /// The current default output device ID, or `0` if it can't be read.
    public func currentDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = Self.propertyAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    // MARK: - Lifecycle

    /// Start watching for default-output-device changes. `onChange` is invoked on
    /// a private serial queue each time the device changes. Idempotent. Returns
    /// `true` if a listener is registered (or already was).
    @discardableResult
    public func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard listenerBlock == nil else { return true }

        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        var addr = Self.propertyAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, queue, block
        )
        guard status == noErr else {
            logger.error("Failed to register default-output listener (status \(status))")
            return false
        }
        listenerBlock = block
        logger.info("Default-output-device listener registered")
        return true
    }

    /// Stop watching. Safe to call when not started, and to call repeatedly.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let block = listenerBlock else { return }
        var addr = Self.propertyAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, queue, block
        )
        listenerBlock = nil
        logger.info("Default-output-device listener removed")
    }

    /// Whether a listener is currently registered.
    public var isMonitoring: Bool {
        lock.withLock { listenerBlock != nil }
    }

    deinit {
        stop()
    }
}
