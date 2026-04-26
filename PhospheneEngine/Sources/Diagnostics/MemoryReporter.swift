// MemoryReporter — Mach task-info wrapper for resident memory snapshots (Increment 7.1).
//
// Uses `phys_footprint` (TASK_VM_INFO) rather than `resident_size` because phys_footprint
// excludes purgeable pages the OS can reclaim cheaply, matching what Activity Monitor's
// "Memory" column reports. resident_size over-counts. D-060(a).
//
// Sampling at 1 Hz is appropriate for soak-test slope detection over 2 hours.
// Sub-second growth bursts are Instruments territory — not what soak tests measure.
// D-060(a).

import Foundation
import QuartzCore

// MARK: - MemorySnapshot

/// A point-in-time memory measurement from the Mach task-info API.
public struct MemorySnapshot: Sendable, Equatable {
    /// `CACurrentMediaTime()` when the snapshot was taken.
    public let timestamp: TimeInterval

    /// Physical memory footprint in bytes (`phys_footprint`).
    ///
    /// This is the authoritative "how much RAM is this process actually using" number.
    /// It matches Activity Monitor's "Memory" column and excludes purgeable pages.
    /// Equivalent to `phys_footprint` from `task_vm_info_data_t`.
    public let residentBytes: UInt64

    /// Virtual address space size in bytes.
    public let virtualBytes: UInt64

    /// Purgeable volatile memory in bytes.
    ///
    /// When this is large, the OS can reclaim it without swapping. A growing
    /// `residentBytes` that is mostly `purgeableBytes` is not a real leak.
    public let purgeableBytes: UInt64

    public init(timestamp: TimeInterval,
                residentBytes: UInt64,
                virtualBytes: UInt64,
                purgeableBytes: UInt64) {
        self.timestamp = timestamp
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
        self.purgeableBytes = purgeableBytes
    }
}

// MARK: - MemoryReporter

/// Stateless wrapper around `task_vm_info` for resident memory snapshots.
///
/// Every call is a fresh Mach kernel query. There is no internal state.
public enum MemoryReporter {

    /// Take a memory snapshot for the current process.
    ///
    /// Returns `nil` if the Mach call fails (rare but possible under extreme load or
    /// sandboxing changes). A soak harness receiving more than 5 `nil` results in a
    /// run should treat it as a hard failure — repeated Mach instability is itself a bug.
    ///
    /// - Parameter now: Timestamp to embed in the snapshot. Defaults to `CACurrentMediaTime()`.
    public static func snapshot(now: TimeInterval = CACurrentMediaTime()) -> MemorySnapshot? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemorySnapshot(
            timestamp: now,
            residentBytes: UInt64(info.phys_footprint),
            virtualBytes: UInt64(info.virtual_size),
            purgeableBytes: UInt64(info.purgeable_volatile_pmap)
        )
    }
}
