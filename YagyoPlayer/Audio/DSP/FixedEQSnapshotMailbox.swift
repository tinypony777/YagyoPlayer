import Synchronization

/// One-shot builder for the producer and consumer endpoints. The builder and both
/// endpoints are noncopyable, and each endpoint can be taken only once.
struct FixedEQSnapshotMailbox: ~Copyable {
    static let capacity = 4

    private let storage = FixedEQSnapshotStorage()
    private var producerIsAvailable = true
    private var consumerIsAvailable = true

    mutating func takeProducer() -> FixedEQSnapshotProducer? {
        guard producerIsAvailable else { return nil }
        producerIsAvailable = false
        return FixedEQSnapshotProducer(storage: storage)
    }

    mutating func takeConsumer() -> FixedEQSnapshotConsumer? {
        guard consumerIsAvailable else { return nil }
        consumerIsAvailable = false
        return FixedEQSnapshotConsumer(storage: storage)
    }
}

/// Control-owned endpoint. It can be transferred once, but cannot be copied into a
/// second producer. A full mailbox rejects new data instead of overwriting unread data.
struct FixedEQSnapshotProducer: ~Copyable, Sendable {
    private let storage: FixedEQSnapshotStorage

    fileprivate init(storage: FixedEQSnapshotStorage) {
        self.storage = storage
    }

    mutating func enqueue(_ snapshot: FixedEQSnapshot) -> Bool {
        storage.enqueue(snapshot)
    }
}

/// Render-owned endpoint. It can be transferred into exactly one render processor.
struct FixedEQSnapshotConsumer: ~Copyable, Sendable {
    private let storage: FixedEQSnapshotStorage

    fileprivate init(storage: FixedEQSnapshotStorage) {
        self.storage = storage
    }

    /// Consumes one published batch and returns only its newest complete snapshot.
    /// Work is constant regardless of how many stale entries exist.
    mutating func dequeueLatest() -> FixedEQSnapshot? {
        storage.dequeueLatest()
    }
}

/// Storage is allocated once during endpoint creation. Access is safe only through the
/// unique producer and consumer values above.
private final class FixedEQSnapshotStorage: @unchecked Sendable {
    private static let capacity = FixedEQSnapshotMailbox.capacity
    private static let indexMask = UInt64(capacity - 1)

    private let publishedSequence = Atomic<UInt64>(0)
    private let consumedSequence = Atomic<UInt64>(0)
    private let storage: UnsafeMutablePointer<FixedEQSnapshot>

    init() {
        precondition(Self.capacity > 0 && Self.capacity.nonzeroBitCount == 1)
        storage = .allocate(capacity: Self.capacity)
        storage.initialize(
            repeating: .original(generation: 0),
            count: Self.capacity
        )
    }

    deinit {
        storage.deinitialize(count: Self.capacity)
        storage.deallocate()
    }

    func enqueue(_ snapshot: FixedEQSnapshot) -> Bool {
        let published = publishedSequence.load(ordering: .relaxed)
        let consumed = consumedSequence.load(ordering: .acquiring)
        guard published &- consumed < UInt64(Self.capacity) else {
            return false
        }

        storage[Int(published & Self.indexMask)] = snapshot
        publishedSequence.store(published &+ 1, ordering: .releasing)
        return true
    }

    func dequeueLatest() -> FixedEQSnapshot? {
        let consumed = consumedSequence.load(ordering: .relaxed)
        let published = publishedSequence.load(ordering: .acquiring)
        guard consumed != published else {
            return nil
        }

        let latestSequence = published &- 1
        let snapshot = storage[Int(latestSequence & Self.indexMask)]
        consumedSequence.store(published, ordering: .releasing)
        return snapshot
    }
}
