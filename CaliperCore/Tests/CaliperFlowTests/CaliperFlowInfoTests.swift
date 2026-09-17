import XCTest
@testable import CaliperFlow

final class CaliperFlowInfoTests: XCTestCase {
    func testVersionMatchesCore() {
        XCTAssertEqual(CaliperFlowInfo.version, "0.1.0")
    }
}
