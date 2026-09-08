import XCTest
@testable import iMappingProCore

final class ScanStateTests: XCTestCase {

    func testAllCases() {
        // ScanState の全ケースが存在することを確認
        let states: [ScanState] = [.idle, .preparing, .scanning, .paused, .saving]
        XCTAssertEqual(states.count, 5)
    }

    func testEquality() {
        XCTAssertTrue(ScanState.idle == .idle)
        XCTAssertTrue(ScanState.preparing == .preparing)
        XCTAssertTrue(ScanState.scanning == .scanning)
        XCTAssertTrue(ScanState.paused == .paused)
        XCTAssertTrue(ScanState.saving == .saving)
    }

    func testInequality() {
        XCTAssertFalse(ScanState.idle == .scanning)
        XCTAssertFalse(ScanState.idle == .preparing)
        XCTAssertFalse(ScanState.preparing == .scanning)
        XCTAssertFalse(ScanState.scanning == .paused)
        XCTAssertFalse(ScanState.paused == .saving)
    }
}
