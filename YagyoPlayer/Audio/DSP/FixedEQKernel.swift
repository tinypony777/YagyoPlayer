import Foundation

enum FixedEQProcessResult: UInt32, Equatable, Sendable {
    case original
    case processed
    case latchedOriginal
    case invalidBuffers
}

/// Allocation-free mono/stereo DF2T kernel. The processed path requires separate
/// input/output buffers so a numerical failure can restore the whole buffer to Original.
struct FixedEQKernel: Sendable {
    private var snapshot: FixedEQSnapshot
    private var leftState = FixedEQChannelState()
    private var rightState = FixedEQChannelState()
    private(set) var isOriginalLatched = false

    init(snapshot: FixedEQSnapshot = .original(generation: 0)) {
        self.snapshot = snapshot
    }

    /// Apply only from the control boundary between render calls.
    /// Explicit application is the only operation that clears a safety latch.
    mutating func apply(_ snapshot: FixedEQSnapshot) {
        self.snapshot = snapshot
        isOriginalLatched = false
        reset()
    }

    /// Clears filter history for seek/discontinuity without clearing a safety latch.
    mutating func reset() {
        leftState = FixedEQChannelState()
        rightState = FixedEQChannelState()
    }

    mutating func process(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> FixedEQProcessResult {
        guard validBufferShape(
            inputLeft: inputLeft,
            inputRight: inputRight,
            outputLeft: outputLeft,
            outputRight: outputRight,
            frameCount: frameCount
        ) else {
            latchOriginal()
            return .invalidBuffers
        }

        if snapshot.mode == .original || isOriginalLatched {
            guard Self.originalBufferTopologyIsSafe(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: outputRight,
                frameCount: frameCount
            ) else {
                latchOriginal()
                return .invalidBuffers
            }

            guard inputsAreFinite(
                inputLeft: inputLeft,
                inputRight: inputRight,
                frameCount: frameCount
            ) else {
                latchOriginal()
                copyOriginal(
                    inputLeft: inputLeft,
                    inputRight: inputRight,
                    outputLeft: outputLeft,
                    outputRight: outputRight,
                    frameCount: frameCount,
                    sanitizeNonFinite: true
                )
                return .latchedOriginal
            }

            copyOriginal(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: outputRight,
                frameCount: frameCount,
                sanitizeNonFinite: false
            )
            return .original
        }

        guard Self.processedBufferTopologyIsSafe(
            inputLeft: inputLeft,
            inputRight: inputRight,
            outputLeft: outputLeft,
            outputRight: outputRight,
            frameCount: frameCount
        ) else {
            latchOriginal()
            return .invalidBuffers
        }

        guard snapshotIsSafe(snapshot),
              inputsAreFinite(
                  inputLeft: inputLeft,
                  inputRight: inputRight,
                  frameCount: frameCount
              ) else {
            latchOriginal()
            copyOriginal(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: outputRight,
                frameCount: frameCount,
                sanitizeNonFinite: true
            )
            return .latchedOriginal
        }

        let activeSnapshot = snapshot
        for frame in 0..<frameCount {
            guard let left = Self.processSample(
                inputLeft[frame],
                snapshot: activeSnapshot,
                state: &leftState
            ) else {
                return latchAndRestore(
                    inputLeft: inputLeft,
                    inputRight: inputRight,
                    outputLeft: outputLeft,
                    outputRight: outputRight,
                    frameCount: frameCount
                )
            }
            outputLeft[frame] = left

            if let inputRight, let outputRight {
                guard let right = Self.processSample(
                    inputRight[frame],
                    snapshot: activeSnapshot,
                    state: &rightState
                ) else {
                    return latchAndRestore(
                        inputLeft: inputLeft,
                        inputRight: inputRight,
                        outputLeft: outputLeft,
                        outputRight: outputRight,
                        frameCount: frameCount
                    )
                }
                outputRight[frame] = right
            }
        }
        return .processed
    }

    private mutating func latchAndRestore(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> FixedEQProcessResult {
        latchOriginal()
        copyOriginal(
            inputLeft: inputLeft,
            inputRight: inputRight,
            outputLeft: outputLeft,
            outputRight: outputRight,
            frameCount: frameCount,
            sanitizeNonFinite: true
        )
        return .latchedOriginal
    }

    mutating func latchOriginal() {
        isOriginalLatched = true
        reset()
    }

    private func validBufferShape(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        guard frameCount >= 0,
              inputLeft.count >= frameCount,
              outputLeft.count >= frameCount,
              (inputRight == nil) == (outputRight == nil) else {
            return false
        }
        if let inputRight, inputRight.count < frameCount {
            return false
        }
        if let outputRight, outputRight.count < frameCount {
            return false
        }
        return true
    }

    private func snapshotIsSafe(_ snapshot: FixedEQSnapshot) -> Bool {
        snapshot.mode == .processed
            && (FixedEQRecipeContract.minimumBandCount...FixedEQRecipeContract.maximumBandCount)
                .contains(snapshot.bandCount)
            && snapshot.coefficients.allFiniteAndStable
            && snapshot.inputHeadroomLinear.isFinite
            && snapshot.inputHeadroomLinear > 0
            && snapshot.inputHeadroomLinear <= 1
            && snapshot.outputTrimLinear.isFinite
            && snapshot.outputTrimLinear > 0
            && snapshot.outputTrimLinear <= 1
    }

    private func inputsAreFinite(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        for frame in 0..<frameCount {
            guard inputLeft[frame].isFinite else { return false }
            if let inputRight, !inputRight[frame].isFinite {
                return false
            }
        }
        return true
    }

    private func copyOriginal(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int,
        sanitizeNonFinite: Bool
    ) {
        for frame in 0..<frameCount {
            let left = inputLeft[frame]
            outputLeft[frame] = sanitizeNonFinite && !left.isFinite ? 0 : left
            if let inputRight, let outputRight {
                let right = inputRight[frame]
                outputRight[frame] = sanitizeNonFinite && !right.isFinite ? 0 : right
            }
        }
    }

    private static func processSample(
        _ input: Float,
        snapshot: FixedEQSnapshot,
        state: inout FixedEQChannelState
    ) -> Float? {
        var value = input * snapshot.inputHeadroomLinear
        guard value.isFinite,
              let first = state.first.process(value, coefficients: snapshot.coefficients.first),
              let second = state.second.process(first, coefficients: snapshot.coefficients.second),
              let third = state.third.process(second, coefficients: snapshot.coefficients.third) else {
            return nil
        }
        value = third

        if snapshot.bandCount >= 4 {
            guard let fourth = state.fourth.process(
                value,
                coefficients: snapshot.coefficients.fourth
            ) else {
                return nil
            }
            value = fourth
        }
        if snapshot.bandCount >= 5 {
            guard let fifth = state.fifth.process(
                value,
                coefficients: snapshot.coefficients.fifth
            ) else {
                return nil
            }
            value = fifth
        }

        let output = value * snapshot.outputTrimLinear
        return output.isFinite ? output : nil
    }

    private static func overlaps(
        _ input: UnsafeBufferPointer<Float>?,
        _ output: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        guard frameCount > 0,
              let inputBase = input?.baseAddress,
              let outputBase = output?.baseAddress else {
            return false
        }
        let byteCount = UInt(frameCount * MemoryLayout<Float>.stride)
        let inputStart = UInt(bitPattern: UnsafeRawPointer(inputBase))
        let outputStart = UInt(bitPattern: UnsafeRawPointer(outputBase))
        let inputEnd = inputStart &+ byteCount
        let outputEnd = outputStart &+ byteCount
        return inputStart < outputEnd && outputStart < inputEnd
    }

    private static func outputsOverlap(
        _ first: UnsafeMutableBufferPointer<Float>?,
        _ second: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        guard frameCount > 0,
              let firstBase = first?.baseAddress,
              let secondBase = second?.baseAddress else {
            return false
        }
        let byteCount = UInt(frameCount * MemoryLayout<Float>.stride)
        let firstStart = UInt(bitPattern: UnsafeRawPointer(firstBase))
        let secondStart = UInt(bitPattern: UnsafeRawPointer(secondBase))
        let firstEnd = firstStart &+ byteCount
        let secondEnd = secondStart &+ byteCount
        return firstStart < secondEnd && secondStart < firstEnd
    }

    private static func exactlyAliases(
        _ input: UnsafeBufferPointer<Float>?,
        _ output: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        guard frameCount > 0,
              let inputBase = input?.baseAddress,
              let outputBase = output?.baseAddress else {
            return false
        }
        return inputBase == UnsafePointer(outputBase)
    }

    private static func originalBufferTopologyIsSafe(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        let leftOverlap = overlaps(inputLeft, outputLeft, frameCount: frameCount)
        let rightOverlap = overlaps(inputRight, outputRight, frameCount: frameCount)
        return (!leftOverlap || exactlyAliases(inputLeft, outputLeft, frameCount: frameCount))
            && (!rightOverlap || exactlyAliases(inputRight, outputRight, frameCount: frameCount))
            && !overlaps(inputLeft, outputRight, frameCount: frameCount)
            && !overlaps(inputRight, outputLeft, frameCount: frameCount)
            && !outputsOverlap(outputLeft, outputRight, frameCount: frameCount)
    }

    private static func processedBufferTopologyIsSafe(
        inputLeft: UnsafeBufferPointer<Float>,
        inputRight: UnsafeBufferPointer<Float>?,
        outputLeft: UnsafeMutableBufferPointer<Float>,
        outputRight: UnsafeMutableBufferPointer<Float>?,
        frameCount: Int
    ) -> Bool {
        !overlaps(inputLeft, outputLeft, frameCount: frameCount)
            && !overlaps(inputLeft, outputRight, frameCount: frameCount)
            && !overlaps(inputRight, outputLeft, frameCount: frameCount)
            && !overlaps(inputRight, outputRight, frameCount: frameCount)
            && !outputsOverlap(outputLeft, outputRight, frameCount: frameCount)
    }
}

private struct FixedEQChannelState: Sendable {
    var first = BiquadState()
    var second = BiquadState()
    var third = BiquadState()
    var fourth = BiquadState()
    var fifth = BiquadState()
}

private struct BiquadState: Sendable {
    private static let denormalThreshold: Float = 1e-20

    var z1: Float = 0
    var z2: Float = 0

    mutating func process(_ input: Float, coefficients: BiquadCoefficients) -> Float? {
        let output = coefficients.b0 * input + z1
        let nextZ1 = coefficients.b1 * input - coefficients.a1 * output + z2
        let nextZ2 = coefficients.b2 * input - coefficients.a2 * output
        guard output.isFinite, nextZ1.isFinite, nextZ2.isFinite else {
            return nil
        }

        z1 = Self.flushDenormal(nextZ1)
        z2 = Self.flushDenormal(nextZ2)
        return output
    }

    private static func flushDenormal(_ value: Float) -> Float {
        abs(value) < denormalThreshold ? 0 : value
    }
}
