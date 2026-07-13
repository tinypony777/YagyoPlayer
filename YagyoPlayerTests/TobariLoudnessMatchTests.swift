import XCTest
@testable import YagyoPlayer

final class TobariLoudnessMatchTests: XCTestCase {
    func testPairAllowsMatchOnlyForTheLoadedActiveSide() {
        let subjectID = UUID()
        let referenceID = UUID()
        let unrelatedID = UUID()
        let pair = TobariABPair(
            subjectTrackID: subjectID,
            referenceTrackID: referenceID
        )

        XCTAssertTrue(pair.canApply(to: subjectID, activeSide: .subject))
        XCTAssertTrue(pair.canApply(to: referenceID, activeSide: .reference))
        XCTAssertFalse(pair.canApply(to: referenceID, activeSide: .subject))
        XCTAssertFalse(pair.canApply(to: unrelatedID, activeSide: .subject))
        XCTAssertFalse(pair.canApply(to: nil, activeSide: .reference))
    }

    func testLouderSubjectIsAttenuatedToReference() throws {
        let match = try XCTUnwrap(TobariLoudnessMatch(
            subjectIntegratedLUFS: -12,
            referenceIntegratedLUFS: -18
        ))

        XCTAssertEqual(match.targetLUFS, -18, accuracy: 1e-12)
        XCTAssertEqual(match.subjectGainDB, -6, accuracy: 1e-12)
        XCTAssertEqual(match.referenceGainDB, 0, accuracy: 1e-12)
        XCTAssertEqual(match.multiplier(for: .subject), Float(pow(10, -6.0 / 20.0)), accuracy: 1e-6)
        XCTAssertEqual(match.multiplier(for: .reference), 1, accuracy: 1e-6)
    }

    func testLouderReferenceIsAttenuatedToSubject() throws {
        let match = try XCTUnwrap(TobariLoudnessMatch(
            subjectIntegratedLUFS: -20,
            referenceIntegratedLUFS: -14.5
        ))

        XCTAssertEqual(match.targetLUFS, -20, accuracy: 1e-12)
        XCTAssertEqual(match.subjectGainDB, 0, accuracy: 1e-12)
        XCTAssertEqual(match.referenceGainDB, -5.5, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(match.multiplier(for: .reference), 1)
    }

    func testEqualLoudnessUsesUnityForBothSides() throws {
        let match = try XCTUnwrap(TobariLoudnessMatch(
            subjectIntegratedLUFS: -16,
            referenceIntegratedLUFS: -16
        ))

        XCTAssertEqual(match.subjectGainDB, 0, accuracy: 1e-12)
        XCTAssertEqual(match.referenceGainDB, 0, accuracy: 1e-12)
        XCTAssertEqual(match.multiplier(for: .subject), 1)
        XCTAssertEqual(match.multiplier(for: .reference), 1)
    }

    func testMissingOrNonFiniteLoudnessCannotCreateMatch() {
        XCTAssertNil(TobariLoudnessMatch(subjectIntegratedLUFS: nil, referenceIntegratedLUFS: -18))
        XCTAssertNil(TobariLoudnessMatch(subjectIntegratedLUFS: -18, referenceIntegratedLUFS: nil))
        XCTAssertNil(TobariLoudnessMatch(subjectIntegratedLUFS: .nan, referenceIntegratedLUFS: -18))
        XCTAssertNil(TobariLoudnessMatch(subjectIntegratedLUFS: -18, referenceIntegratedLUFS: .infinity))
        XCTAssertNil(TobariLoudnessMatch(
            subjectIntegratedLUFS: Double.greatestFiniteMagnitude,
            referenceIntegratedLUFS: -Double.greatestFiniteMagnitude
        ))
    }
}
