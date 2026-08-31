// DefaultOutputDeviceMonitorTests — CLEAN.1.5 / GAP-1.
//
// Validates the default-output-device listener mechanism (registration,
// teardown, idempotency, re-start) that drives SystemAudioCapture's tap
// reinstall. Listening to `kAudioHardwarePropertyDefaultOutputDevice` on the
// system object needs no audio-capture permission, so this runs headlessly.
//
// The actual firing on a real device swap (AirPods connect / monitor unplug) is
// validated manually — there is no supported API to change the default output
// device from a unit test.

import Testing
import CoreAudio
@testable import Audio

@Suite("DefaultOutputDeviceMonitor (CLEAN.1.5 / GAP-1)")
struct DefaultOutputDeviceMonitorTests {

    @Test func start_registersListener_andIsMonitoring() {
        let monitor = DefaultOutputDeviceMonitor()
        #expect(!monitor.isMonitoring)
        let ok = monitor.start { }
        #expect(ok, "listener registration on the system object should succeed (no TCC permission needed)")
        #expect(monitor.isMonitoring)
        monitor.stop()
    }

    @Test func start_isIdempotent() {
        let monitor = DefaultOutputDeviceMonitor()
        #expect(monitor.start { })
        #expect(monitor.start { })   // second start is a no-op; still registered once
        #expect(monitor.isMonitoring)
        monitor.stop()
    }

    @Test func stop_unregisters_andIsSafeToRepeat() {
        let monitor = DefaultOutputDeviceMonitor()
        _ = monitor.start { }
        monitor.stop()
        #expect(!monitor.isMonitoring)
        monitor.stop()   // idempotent — must not crash
        #expect(!monitor.isMonitoring)
    }

    @Test func restart_afterStop_works() {
        let monitor = DefaultOutputDeviceMonitor()
        #expect(monitor.start { })
        monitor.stop()
        #expect(monitor.start { }, "monitor should be re-startable after stop")
        #expect(monitor.isMonitoring)
        monitor.stop()
    }

    @Test func currentDefaultOutputDeviceID_isReadableAndStable() {
        let monitor = DefaultOutputDeviceMonitor()
        // Permission-free read; returns the device ID (0 if none). Must not crash
        // and should be stable across back-to-back calls.
        let first = monitor.currentDefaultOutputDeviceID()
        let second = monitor.currentDefaultOutputDeviceID()
        #expect(first == second, "default-output-device ID read should be stable within a test")
    }
}
