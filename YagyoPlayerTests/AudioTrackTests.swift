import XCTest
@testable import YagyoPlayer

final class AudioTrackTests: XCTestCase {
    func testDurationTextFormatsMinutesAndSeconds() {
        let track = AudioTrack(
            title: "Matsuri",
            originalFilename: "matsuri.wav",
            storedFilename: "matsuri.wav",
            duration: 187
        )

        XCTAssertEqual(track.durationText, "3:07")
    }

    func testDurationTextFallsBackForMissingDuration() {
        let track = AudioTrack(
            title: "Quiet",
            originalFilename: "quiet.wav",
            storedFilename: "quiet.wav",
            duration: nil
        )

        XCTAssertEqual(track.durationText, "--:--")
    }
}
