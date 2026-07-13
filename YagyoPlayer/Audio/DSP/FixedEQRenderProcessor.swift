enum FixedEQTransitionState: UInt32, Equatable, Sendable {
    case steadyOriginal
    case rampingToProcessed
    case steadyProcessed
    case rampingToOriginal
    case replacingProcessed

    var isTransitioning: Bool {
        switch self {
        case .steadyOriginal, .steadyProcessed:
            return false
        case .rampingToProcessed, .rampingToOriginal, .replacingProcessed:
            return true
        }
    }
}

enum FixedEQTransitionContract {
    /// Keeps the configurable preview ramp bounded to a realtime-safe, short interval.
    static let maximumFrameCount = 8_192
}

struct FixedEQRenderReport: Equatable, Sendable {
    /// The newest request whose target state is now steady and audible. With a
    /// transition enabled this deliberately differs from "coefficients loaded".
    let appliedGeneration: UInt64?
    let processResult: FixedEQProcessResult
    let transitionState: FixedEQTransitionState
}

/// Render-owned kernel wrapper. A complete snapshot may be applied once, at the
/// beginning of each buffer, before any sample in that buffer is processed.
struct FixedEQRenderProcessor: ~Copyable, Sendable {
    private var consumer: FixedEQSnapshotConsumer
    private var kernel: FixedEQKernel
    private var activeSnapshot: FixedEQSnapshot
    private var pendingSnapshot: FixedEQSnapshot?
    private var transitionFrameCount: Int
    private var wetFramePosition: Int

    init(
        consumer: consuming FixedEQSnapshotConsumer,
        initialSnapshot: FixedEQSnapshot = .original(generation: 0),
        transitionFrameCount: Int = 0
    ) {
        precondition(
            (0...FixedEQTransitionContract.maximumFrameCount).contains(transitionFrameCount)
        )
        self.consumer = consume consumer
        kernel = FixedEQKernel(snapshot: initialSnapshot)
        activeSnapshot = initialSnapshot
        self.transitionFrameCount = transitionFrameCount
        wetFramePosition = initialSnapshot.mode == .processed ? transitionFrameCount : 0
    }

    var isOriginalLatched: Bool {
        kernel.isOriginalLatched
    }

    mutating func reset() {
        kernel.reset()
        if kernel.isOriginalLatched {
            pendingSnapshot = nil
            wetFramePosition = 0
        } else if pendingSnapshot != nil {
            // A discontinuity cannot safely resume halfway through a ramp. Keep the
            // target generation and restart from dry at the next render boundary.
            wetFramePosition = 0
        } else {
            wetFramePosition = activeSnapshot.mode == .processed
                ? transitionFrameCount
                : 0
        }
    }

    mutating func latchOriginal() {
        kernel.latchOriginal()
        pendingSnapshot = nil
        wetFramePosition = 0
    }

    /// Control-side configuration. The owning AU permits this only before render
    /// resources are allocated, so the render thread never races this mutation.
    mutating func configureTransition(frameCount: Int) {
        precondition((0...FixedEQTransitionContract.maximumFrameCount).contains(frameCount))
        transitionFrameCount = frameCount
        if kernel.isOriginalLatched {
            pendingSnapshot = nil
            wetFramePosition = 0
        } else if pendingSnapshot != nil {
            wetFramePosition = 0
        } else {
            wetFramePosition = activeSnapshot.mode == .processed ? frameCount : 0
        }
    }

    mutating func process(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> FixedEQRenderReport {
        let nextSnapshot = consumer.dequeueLatest()
        var appliedGeneration: UInt64?
        if let nextSnapshot {
            accept(nextSnapshot, appliedGeneration: &appliedGeneration)
        } else {
            completeDryBoundaryIfNeeded(appliedGeneration: &appliedGeneration)
        }

        let result = kernel.process(
            inputLeft: inputLeft,
            inputRight: inputRight,
            outputLeft: outputLeft,
            outputRight: outputRight,
            frameCount: frameCount
        )

        if kernel.isOriginalLatched {
            pendingSnapshot = nil
            wetFramePosition = 0
        } else if result == .processed, transitionFrameCount > 0 {
            blendAndAdvance(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: outputRight,
                frameCount: frameCount
            )
            completeWetBoundaryIfNeeded(appliedGeneration: &appliedGeneration)
        } else if result == .invalidBuffers {
            pendingSnapshot = nil
            wetFramePosition = 0
        }

        return FixedEQRenderReport(
            appliedGeneration: appliedGeneration,
            processResult: result,
            transitionState: currentTransitionState
        )
    }

    private var currentTransitionState: FixedEQTransitionState {
        if kernel.isOriginalLatched {
            return .steadyOriginal
        }
        guard transitionFrameCount > 0, let pendingSnapshot else {
            return activeSnapshot.mode == .processed ? .steadyProcessed : .steadyOriginal
        }
        if pendingSnapshot.mode == .original {
            return .rampingToOriginal
        }
        return processedPayloadMatchesActive(pendingSnapshot)
            ? .rampingToProcessed
            : .replacingProcessed
    }

    private mutating func accept(
        _ snapshot: FixedEQSnapshot,
        appliedGeneration: inout UInt64?
    ) {
        guard transitionFrameCount > 0 else {
            applyImmediately(snapshot)
            appliedGeneration = snapshot.generation
            return
        }

        if snapshot.mode == .original {
            if wetFramePosition == 0 {
                applyImmediately(snapshot)
                appliedGeneration = snapshot.generation
            } else {
                pendingSnapshot = snapshot
            }
            return
        }

        let canReuseActiveKernel = !kernel.isOriginalLatched
            && activeSnapshot.mode == .processed
            && processedPayloadMatchesActive(snapshot)
        if canReuseActiveKernel {
            if wetFramePosition == transitionFrameCount {
                pendingSnapshot = nil
                activeSnapshot = snapshot
                appliedGeneration = snapshot.generation
            } else {
                pendingSnapshot = snapshot
            }
            return
        }

        if wetFramePosition == 0 {
            kernel.apply(snapshot)
            activeSnapshot = snapshot
            pendingSnapshot = snapshot
        } else {
            // A different processed recipe first reaches dry. Coefficients and IIR
            // history are replaced only at the following render boundary.
            pendingSnapshot = snapshot
        }
    }

    private mutating func completeDryBoundaryIfNeeded(
        appliedGeneration: inout UInt64?
    ) {
        guard let pendingSnapshot else {
            return
        }
        if transitionFrameCount == 0 {
            applyImmediately(pendingSnapshot)
            appliedGeneration = pendingSnapshot.generation
            return
        }
        guard wetFramePosition == 0 else { return }

        if pendingSnapshot.mode == .original {
            applyImmediately(pendingSnapshot)
            appliedGeneration = pendingSnapshot.generation
            return
        }

        guard !processedPayloadMatchesActive(pendingSnapshot)
                || kernel.isOriginalLatched else {
            return
        }
        kernel.apply(pendingSnapshot)
        activeSnapshot = pendingSnapshot
        // Keep the request pending until its fade-in reaches fully wet.
    }

    private mutating func completeWetBoundaryIfNeeded(
        appliedGeneration: inout UInt64?
    ) {
        guard wetFramePosition == transitionFrameCount,
              let pendingSnapshot,
              pendingSnapshot.mode == .processed,
              processedPayloadMatchesActive(pendingSnapshot) else {
            return
        }
        activeSnapshot = pendingSnapshot
        self.pendingSnapshot = nil
        appliedGeneration = pendingSnapshot.generation
    }

    private mutating func blendAndAdvance(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) {
        let direction: Int
        if let pendingSnapshot {
            direction = pendingSnapshot.mode == .processed
                && processedPayloadMatchesActive(pendingSnapshot) ? 1 : -1
        } else {
            direction = 0
        }
        let inverseFrameCount = 1 / Float(transitionFrameCount)

        for frame in 0..<frameCount {
            let mix = Float(wetFramePosition) * inverseFrameCount
            if mix <= 0 {
                outputLeft[frame] = inputLeft[frame]
                if let inputRight, let outputRight {
                    outputRight[frame] = inputRight[frame]
                }
            } else if mix < 1 {
                let dryMix = 1 - mix
                outputLeft[frame] = inputLeft[frame] * dryMix + outputLeft[frame] * mix
                if let inputRight, let outputRight {
                    outputRight[frame] = inputRight[frame] * dryMix + outputRight[frame] * mix
                }
            }

            if direction > 0, wetFramePosition < transitionFrameCount {
                wetFramePosition += 1
            } else if direction < 0, wetFramePosition > 0 {
                wetFramePosition -= 1
            }
        }
    }

    private mutating func applyImmediately(_ snapshot: FixedEQSnapshot) {
        kernel.apply(snapshot)
        activeSnapshot = snapshot
        pendingSnapshot = nil
        wetFramePosition = snapshot.mode == .processed ? transitionFrameCount : 0
    }

    private func processedPayloadMatchesActive(_ snapshot: FixedEQSnapshot) -> Bool {
        snapshot.mode == .processed
            && activeSnapshot.mode == .processed
            && snapshot.bandCount == activeSnapshot.bandCount
            && snapshot.coefficients == activeSnapshot.coefficients
            && snapshot.inputHeadroomLinear == activeSnapshot.inputHeadroomLinear
            && snapshot.outputTrimLinear == activeSnapshot.outputTrimLinear
    }
}
