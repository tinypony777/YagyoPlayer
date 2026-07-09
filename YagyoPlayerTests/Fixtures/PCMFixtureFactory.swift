import AVFoundation
import XCTest
@testable import YagyoPlayer

enum PCMFixtureFactory {
    static let sampleRate = 48_000.0

    static func format(
        channelCount: AVAudioChannelCount,
        interleaved: Bool = true,
        layoutTag: AudioChannelLayoutTag? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AVAudioFormat {
        guard let layoutTag else {
            return try format(channelCount: channelCount, interleaved: interleaved, file: file, line: line)
        }
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: layoutTag), file: file, line: line)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: interleaved,
            channelLayout: layout
        )
        let unwrapped = try XCTUnwrap(format, file: file, line: line)
        XCTAssertEqual(unwrapped.channelCount, channelCount, file: file, line: line)
        return unwrapped
    }

    static func format(
        channelCount: AVAudioChannelCount,
        interleaved: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AVAudioFormat {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: interleaved
        )
        return try XCTUnwrap(format, file: file, line: line)
    }

    static func buffer(
        format: AVAudioFormat,
        frameCount: Int,
        interleavedSamples: [Float],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AVAudioPCMBuffer {
        let channelCount = Int(format.channelCount)
        XCTAssertEqual(interleavedSamples.count, frameCount * channelCount, file: file, line: line)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
            file: file,
            line: line
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelData = try XCTUnwrap(buffer.floatChannelData, file: file, line: line)
        if format.isInterleaved {
            interleavedSamples.withUnsafeBufferPointer { samples in
                channelData[0].update(from: samples.baseAddress!, count: samples.count)
            }
        } else {
            for channel in 0..<channelCount {
                for frame in 0..<frameCount {
                    channelData[channel][frame] = interleavedSamples[frame * channelCount + channel]
                }
            }
        }
        return buffer
    }

    static func sine(
        format: AnalysisPCMFormat,
        duration: TimeInterval = 10,
        frequency: Double = 1_000,
        amplitude: Float = 0.1,
        activeChannels: Set<Int>? = nil
    ) -> [Float] {
        let frameCount = Int(format.sampleRate * duration)
        var samples = Array(repeating: Float(0), count: frameCount * format.channelCount)
        for frame in 0..<frameCount {
            let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / format.sampleRate))
            for channel in 0..<format.channelCount where activeChannels?.contains(channel) ?? true {
                samples[frame * format.channelCount + channel] = value
            }
        }
        return samples
    }
}
