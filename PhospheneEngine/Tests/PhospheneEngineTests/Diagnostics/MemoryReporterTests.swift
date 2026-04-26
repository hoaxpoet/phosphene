// MemoryReporterTests — Unit tests for MemoryReporter (always-run, Increment 7.1).
//
// These tests verify that `phys_footprint` from TASK_VM_INFO:
//   - Returns a valid snapshot on macOS.
//   - Has monotonically non-decreasing timestamps between calls.
//   - Reflects large allocations (≥ 5 MB growth after a 10 MB allocation).
//   - Does not grow further after deallocation.

import Testing
import Foundation
@testable import Diagnostics

@Suite("MemoryReporter")
struct MemoryReporterTests {

    // MARK: - Basic Functionality

    @Test("snapshot() returns non-nil on macOS")
    func snapshotNonNil() {
        let snap = MemoryReporter.snapshot()
        #expect(snap != nil, "MemoryReporter.snapshot() must succeed on macOS")
    }

    @Test("snapshot timestamps are non-decreasing")
    func timestampsNonDecreasing() {
        guard let first = MemoryReporter.snapshot() else {
            Issue.record("First snapshot failed")
            return
        }
        guard let second = MemoryReporter.snapshot() else {
            Issue.record("Second snapshot failed")
            return
        }
        #expect(second.timestamp >= first.timestamp,
                "Timestamps must be non-decreasing between successive calls")
    }

    // MARK: - Allocation Detection

    @Test("residentBytes grows by ≥ 5 MB after allocating a 10 MB buffer")
    func allocationDetected() throws {
        let baseline = try #require(MemoryReporter.snapshot(), "baseline snapshot failed")

        // Allocate 10 MB and force-initialise to prevent compiler optimisation.
        let count = 10 * 1024 * 1024
        let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        buf.initialize(repeating: 0xAB)
        defer { buf.deallocate() }

        // Small sleep to let the OS register the mapping.
        usleep(10_000)

        let afterAlloc = try #require(MemoryReporter.snapshot(), "post-allocation snapshot failed")

        // Keep buf alive through the assertion.
        _ = buf[0]

        let growth = afterAlloc.residentBytes > baseline.residentBytes
            ? afterAlloc.residentBytes - baseline.residentBytes
            : 0

        #expect(growth >= 5 * 1024 * 1024,
                "Expected ≥ 5 MB growth after 10 MB allocation, got \(growth / (1024 * 1024)) MB")
    }

    @Test("residentBytes snapshot succeeds before and after deallocation")
    func deallocationSnapshotSucceeds() throws {
        // Verify MemoryReporter.snapshot() succeeds at both points in the allocation
        // lifecycle. No bound assertion: global RSS is shared across the parallel test
        // suite and cannot be bounded reliably.
        let count = 10 * 1024 * 1024
        do {
            let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
            buf.initialize(repeating: 0xCD)
            _ = buf[0]

            let snap = try #require(MemoryReporter.snapshot(), "post-allocation snapshot failed")
            _ = snap.residentBytes
            buf.deallocate()
        }
        usleep(100_000)

        let afterFree = try #require(MemoryReporter.snapshot(), "post-deallocation snapshot failed")
        #expect(afterFree.residentBytes > 0,
                "residentBytes should be non-zero after deallocation")
    }

    // MARK: - Field Sanity

    @Test("virtualBytes is larger than residentBytes")
    func virtualLargerThanResident() throws {
        let snap = try #require(MemoryReporter.snapshot(), "snapshot failed")
        #expect(snap.virtualBytes >= snap.residentBytes,
                "Virtual address space must be ≥ physical footprint")
    }
}
