import CEBUR128
import Foundation

enum LoudnessReading: Equatable {
    case unavailable
    case negativeInfinity
    case finite(Double)

    var externalValue: Double? {
        guard case .finite(let value) = self else {
            return nil
        }
        return value
    }
}

final class EBUR128Meter {
    private(set) var consumedFrameCount: Int64 = 0

    private let format: AnalysisPCMFormat
    private var state: UnsafeMutablePointer<ebur128_state>?

    init(format: AnalysisPCMFormat) throws {
        self.format = format

        let roundedSampleRate = format.sampleRate.rounded()
        guard roundedSampleRate > 0,
              roundedSampleRate <= Double(UInt.max) else {
            throw EBUR128MeterError.invalidSampleRate
        }

        guard let state = ebur128_init(
            UInt32(format.channelCount),
            UInt(roundedSampleRate),
            Int32(EBUR128_MODE_I.rawValue | EBUR128_MODE_S.rawValue)
        ) else {
            throw EBUR128MeterError.initializationFailed
        }

        self.state = state
        for (index, role) in format.channelRoles.enumerated() {
            let result = ebur128_set_channel(state, UInt32(index), role.ebur128Channel)
            guard result == Self.successCode else {
                var stateToDestroy: UnsafeMutablePointer<ebur128_state>? = state
                ebur128_destroy(&stateToDestroy)
                self.state = nil
                throw EBUR128MeterError.channelMappingFailed(result)
            }
        }
    }

    deinit {
        var stateToDestroy = state
        if stateToDestroy != nil {
            ebur128_destroy(&stateToDestroy)
        }
        state = nil
    }

    func addFrames(
        _ interleavedSamples: UnsafeBufferPointer<Float>,
        frameCount: Int
    ) throws {
        guard frameCount >= 0 else {
            throw EBUR128MeterError.invalidFrameCount
        }
        let expectedSampleCount = frameCount * format.channelCount
        guard interleavedSamples.count >= expectedSampleCount else {
            throw EBUR128MeterError.invalidSampleCount
        }
        guard frameCount > 0 else {
            return
        }
        guard let state, let samples = interleavedSamples.baseAddress else {
            throw EBUR128MeterError.missingState
        }

        let result = ebur128_add_frames_float(state, samples, frameCount)
        guard result == Self.successCode else {
            throw EBUR128MeterError.addFramesFailed(result)
        }
        consumedFrameCount += Int64(frameCount)
    }

    func momentary() throws -> LoudnessReading {
        guard consumedFrameCount >= frames(forSeconds: 0.4) else {
            return .unavailable
        }
        var output = 0.0
        guard let state else {
            throw EBUR128MeterError.missingState
        }
        let result = ebur128_loudness_momentary(state, &output)
        return try Self.reading(result: result, output: output)
    }

    func shortTerm() throws -> LoudnessReading {
        guard consumedFrameCount >= frames(forSeconds: 3) else {
            return .unavailable
        }
        var output = 0.0
        guard let state else {
            throw EBUR128MeterError.missingState
        }
        let result = ebur128_loudness_shortterm(state, &output)
        return try Self.reading(result: result, output: output)
    }

    func integrated() throws -> LoudnessReading {
        var output = 0.0
        guard let state else {
            throw EBUR128MeterError.missingState
        }
        let result = ebur128_loudness_global(state, &output)
        return try Self.reading(result: result, output: output)
    }

    private func frames(forSeconds seconds: Double) -> Int64 {
        Int64((format.sampleRate * seconds).rounded(.up))
    }

    private static func reading(result: Int32, output: Double) throws -> LoudnessReading {
        guard result == successCode else {
            throw EBUR128MeterError.loudnessFailed(result)
        }
        if output.isInfinite, output.sign == .minus {
            return .negativeInfinity
        }
        guard output.isFinite else {
            throw EBUR128MeterError.nonFiniteLoudness(output)
        }
        return .finite(output)
    }

    private static let successCode = Int32(EBUR128_SUCCESS.rawValue)
}

enum EBUR128MeterError: Error, Equatable {
    case invalidSampleRate
    case initializationFailed
    case channelMappingFailed(Int32)
    case invalidFrameCount
    case invalidSampleCount
    case missingState
    case addFramesFailed(Int32)
    case loudnessFailed(Int32)
    case nonFiniteLoudness(Double)
}

private extension AudioChannelRole {
    var ebur128Channel: Int32 {
        switch self {
        case .left:
            Int32(EBUR128_Mp030.rawValue)
        case .right:
            Int32(EBUR128_Mm030.rawValue)
        case .center:
            Int32(EBUR128_Mp000.rawValue)
        case .lfe:
            Int32(EBUR128_UNUSED.rawValue)
        case .leftCenter:
            Int32(EBUR128_MpSC.rawValue)
        case .rightCenter:
            Int32(EBUR128_MmSC.rawValue)
        case .leftSurround:
            Int32(EBUR128_Mp110.rawValue)
        case .rightSurround:
            Int32(EBUR128_Mm110.rawValue)
        case .leftSurroundDirect:
            Int32(EBUR128_Mp090.rawValue)
        case .rightSurroundDirect:
            Int32(EBUR128_Mm090.rawValue)
        case .rearSurroundLeft:
            Int32(EBUR128_Mp135.rawValue)
        case .rearSurroundRight:
            Int32(EBUR128_Mm135.rawValue)
        case .centerSurround:
            Int32(EBUR128_Mp180.rawValue)
        }
    }
}
