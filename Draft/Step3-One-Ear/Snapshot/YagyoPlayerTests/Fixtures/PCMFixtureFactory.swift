import AVFoundation
import XCTest
@testable import YagyoPlayer

enum PCMFixtureFactory {
    static let sampleRate = 48_000.0

    static func format(
        channelCount: AVAudioChannelCount,
        sampleRate: Double = PCMFixtureFactory.sampleRate,
        interleaved: Bool = true,
        layoutTag: AudioChannelLayoutTag? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AVAudioFormat {
        guard let layoutTag else {
            return try format(
                channelCount: channelCount,
                sampleRate: sampleRate,
                interleaved: interleaved,
                file: file,
                line: line
            )
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
        channelLabels: [AudioChannelLabel],
        sampleRate: Double = PCMFixtureFactory.sampleRate,
        interleaved: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AVAudioFormat {
        let layout = try channelLayout(labels: channelLabels, file: file, line: line)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: interleaved,
            channelLayout: layout
        )
        let unwrapped = try XCTUnwrap(format, file: file, line: line)
        XCTAssertEqual(unwrapped.channelCount, AVAudioChannelCount(channelLabels.count), file: file, line: line)
        return unwrapped
    }

    static func format(
        channelCount: AVAudioChannelCount,
        sampleRate: Double = PCMFixtureFactory.sampleRate,
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

    private static func channelLayout(
        labels: [AudioChannelLabel],
        file: StaticString,
        line: UInt
    ) throws -> AVAudioChannelLayout {
        XCTAssertFalse(labels.isEmpty, file: file, line: line)
        let descriptionsOffset = try XCTUnwrap(
            MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions),
            file: file,
            line: line
        )
        let byteCount = descriptionsOffset + MemoryLayout<AudioChannelDescription>.stride * labels.count
        let rawLayout = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioChannelLayout>.alignment
        )
        defer { rawLayout.deallocate() }
        rawLayout.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        let layout = rawLayout.assumingMemoryBound(to: AudioChannelLayout.self)
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mChannelBitmap = AudioChannelBitmap()
        layout.pointee.mNumberChannelDescriptions = UInt32(labels.count)

        let descriptions = rawLayout
            .advanced(by: descriptionsOffset)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        for (index, label) in labels.enumerated() {
            descriptions[index] = AudioChannelDescription(
                mChannelLabel: label,
                mChannelFlags: AudioChannelFlags(),
                mCoordinates: (0, 0, 0)
            )
        }

        return AVAudioChannelLayout(layout: UnsafePointer(layout))
    }
}
