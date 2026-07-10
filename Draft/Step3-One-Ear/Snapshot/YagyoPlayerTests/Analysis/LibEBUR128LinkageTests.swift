import CEBUR128
import XCTest

final class LibEBUR128LinkageTests: XCTestCase {
    func testVendoredLibraryReportsPinnedVersion() {
        var major: Int32 = 0
        var minor: Int32 = 0
        var patch: Int32 = 0
        ebur128_get_version(&major, &minor, &patch)
        XCTAssertEqual([major, minor, patch], [1, 2, 6])
    }
}
