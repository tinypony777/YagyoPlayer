import AVFoundation
import XCTest

enum WAVFixtureWriter {
    static func write(
        samples: [Float],
        format: AVAudioFormat,
        frameCount: Int,
        to url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let buffer = try PCMFixtureFactory.buffer(
            format: format,
            frameCount: frameCount,
            interleavedSamples: samples,
            file: file,
            line: line
        )
        let output = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )
        try output.write(from: buffer)
    }
}
