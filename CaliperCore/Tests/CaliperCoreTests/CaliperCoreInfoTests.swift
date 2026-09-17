import XCTest
@testable import CaliperCore

final class CaliperCoreInfoTests: XCTestCase {
    func testVersionIsSemver() {
        XCTAssertEqual(CaliperCoreInfo.version.split(separator: ".").count, 3)
    }
}
