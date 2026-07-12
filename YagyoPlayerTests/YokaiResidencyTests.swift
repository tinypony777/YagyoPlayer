import XCTest
@testable import YagyoPlayer

final class YokaiResidencyTests: XCTestCase {
    func testRosterOrderIsACompatibilityContract() {
        XCTAssertEqual(
            YokaiResidency.stableSpriteIDs,
            ["oni", "mokugyo", "kasa", "kappa", "kitsune", "tengu", "yuki", "biwa"]
        )
    }

    func testKnownLegacyUUIDStillMapsToYuki() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertEqual(YokaiResidency.spriteID(for: id), "yuki")
    }

    func testResidentLeadsWithoutDuplication() {
        let ids = YokaiResidency.processionIDs(residentID: "kasa", isUshimitsu: false)
        XCTAssertEqual(ids.first, "kasa")
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(Set(ids).count, 8)
        XCTAssertEqual(Array(ids.dropFirst()), ["oni", "mokugyo", "kappa", "kitsune", "tengu", "yuki", "biwa"])
    }

    func testUnknownResidentFallsBackAndUshimitsuAppendsHitotsume() {
        XCTAssertEqual(
            YokaiResidency.processionIDs(residentID: "unknown", isUshimitsu: true),
            YokaiResidency.stableSpriteIDs + ["hitotsume"]
        )
    }
}
