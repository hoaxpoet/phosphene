// UMABuffer — Generic zero-copy UMA buffer abstraction for Apple Silicon.
// Wraps MTLBuffer with .storageModeShared so CPU, GPU, and ANE share the
// same physical memory with no implicit copies.
//
// Threading contract: callers must synchronize access externally (e.g. via
// Metal command buffer completion, DispatchSemaphore, or actor isolation).
// The @unchecked Sendable conformance reflects that the underlying memory
// is safe to reference from any thread — but concurrent mutation is the
// caller's responsibility.

import Metal

// MARK: - UMABuffer

/// A typed view over a `.storageModeShared` MTLBuffer.
///
/// Usage:
/// ```swift
/// let buf = try UMABuffer<Float>(device: device, capacity: 1024)
/// buf[0] = 42.0            // CPU write
/// encoder.setBuffer(buf.buffer, offset: 0, index: 0)  // GPU read — same pointer
/// ```
public final class UMABuffer<T>: @unchecked Sendable {

    /// The underlying Metal buffer. Bind this directly to compute/render encoders.
    public let buffer: MTLBuffer

    /// Number of elements of type `T` this buffer can hold.
    public let capacity: Int

    /// Create a shared-mode buffer sized for `capacity` elements of `T`.
    ///
    /// - Parameters:
    ///   - device: The Metal device to allocate from.
    ///   - capacity: Number of `T`-sized elements.
    /// - Throws: ``UMABufferError/allocationFailed`` if Metal cannot allocate.
    public init(device: MTLDevice, capacity: Int) throws {
        let byteLength = MemoryLayout<T>.stride * capacity
        guard let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else {
            throw UMABufferError.allocationFailed(byteLength: byteLength)
        }
        self.buffer = buffer
        self.capacity = capacity
    }

    /// Typed mutable pointer spanning the entire buffer.
    public var pointer: UnsafeMutableBufferPointer<T> {
        let raw = buffer.contents().bindMemory(to: T.self, capacity: capacity)
        return UnsafeMutableBufferPointer(start: raw, count: capacity)
    }

    /// Element access by index.
    public subscript(index: Int) -> T {
        get {
            precondition(index >= 0 && index < capacity, "UMABuffer index out of range")
            return pointer[index]
        }
        set {
            precondition(index >= 0 && index < capacity, "UMABuffer index out of range")
            pointer[index] = newValue
        }
    }

    /// Byte length of the buffer.
    public var byteLength: Int { MemoryLayout<T>.stride * capacity }

    /// Copy a contiguous collection into the buffer starting at `offset`.
    public func write<C: Collection<T>>(_ values: C, offset: Int = 0) {
        precondition(offset >= 0 && offset + values.count <= capacity,
                     "UMABuffer write would exceed capacity")
        var idx = offset
        for value in values {
            pointer[idx] = value
            idx += 1
        }
    }
}

// MARK: - UMARingBuffer

/// A fixed-capacity ring buffer backed by a UMA-shared MTLBuffer.
///
/// Designed for streaming audio frames: the CPU writes at the head,
/// the GPU reads the entire buffer each frame. Overwrites oldest data
/// when full, giving the GPU a sliding window of recent samples.
///
/// The ring is a simple overwrite ring — no consumer/producer
/// synchronization beyond what Metal's command buffer ordering provides.
public final class UMARingBuffer<T>: @unchecked Sendable {

    /// The underlying flat UMABuffer. Bind `storage.buffer` to encoders.
    public let storage: UMABuffer<T>

    /// Write position (next index to be written).
    public private(set) var head: Int = 0

    /// Number of valid elements currently in the ring.
    public private(set) var count: Int = 0

    /// Total element capacity.
    public var capacity: Int { storage.capacity }

    /// Convenience: the underlying MTLBuffer for GPU binding.
    public var buffer: MTLBuffer { storage.buffer }

    public var isFull: Bool { count == capacity }
    // swiftlint:disable:next empty_count
    public var isEmpty: Bool { count == 0 }

    /// Create a ring buffer sized for `capacity` elements of `T`.
    public init(device: MTLDevice, capacity: Int) throws {
        self.storage = try UMABuffer(device: device, capacity: capacity)
    }

    /// Write a single element at the head, advancing it.
    /// Overwrites the oldest element when full.
    @discardableResult
    public func write(_ value: T) -> Int {
        let idx = head
        storage[idx] = value
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        return idx
    }

    /// Write a contiguous sequence of elements. Overwrites oldest data as needed.
    public func write<C: Collection<T>>(contentsOf values: C) {
        for value in values {
            write(value)
        }
    }

    /// Index of the oldest valid element.
    public var tail: Int {
        if !isFull { return 0 }
        return head
    }

    /// Read element at a logical index (0 = oldest, count-1 = newest).
    public func read(at logicalIndex: Int) -> T {
        precondition(logicalIndex >= 0 && logicalIndex < count,
                     "UMARingBuffer logical index out of range")
        let physicalIndex = (tail + logicalIndex) % capacity
        return storage[physicalIndex]
    }

    /// Reset the ring to empty without deallocating.
    public func reset() {
        head = 0
        count = 0
    }
}

// MARK: - Error

public enum UMABufferError: Error, Sendable {
    case allocationFailed(byteLength: Int)
}
