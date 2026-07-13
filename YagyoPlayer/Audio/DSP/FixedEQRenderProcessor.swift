struct FixedEQRenderReport: Equatable, Sendable {
    let appliedGeneration: UInt64?
    let processResult: FixedEQProcessResult
}

/// Render-owned kernel wrapper. A complete snapshot may be applied once, at the
/// beginning of each buffer, before any sample in that buffer is processed.
struct FixedEQRenderProcessor: ~Copyable, Sendable {
    private var consumer: FixedEQSnapshotConsumer
    private var kernel: FixedEQKernel

    init(
        consumer: consuming FixedEQSnapshotConsumer,
        initialSnapshot: FixedEQSnapshot = .original(generation: 0)
    ) {
        self.consumer = consume consumer
        kernel = FixedEQKernel(snapshot: initialSnapshot)
    }

    var isOriginalLatched: Bool {
        kernel.isOriginalLatched
    }

    mutating func reset() {
        kernel.reset()
    }

    mutating func latchOriginal() {
        kernel.latchOriginal()
    }

    mutating func process(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> FixedEQRenderReport {
        let nextSnapshot = consumer.dequeueLatest()
        if let nextSnapshot {
            kernel.apply(nextSnapshot)
        }

        let result = kernel.process(
            inputLeft: inputLeft,
            inputRight: inputRight,
            outputLeft: outputLeft,
            outputRight: outputRight,
            frameCount: frameCount
        )
        return FixedEQRenderReport(
            appliedGeneration: nextSnapshot?.generation,
            processResult: result
        )
    }
}
