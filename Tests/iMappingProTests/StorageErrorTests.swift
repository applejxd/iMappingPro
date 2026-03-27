import XCTest
@testable import iMappingProCore

final class StorageErrorTests: XCTestCase {

    func testDirectoryCreationFailedDescription() {
        let url = URL(fileURLWithPath: "/test/path")
        let error = StorageError.directoryCreationFailed(url)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("path"), "エラーメッセージにパス名を含む: \(desc)")
    }

    func testEncodingFailedDescription() {
        let error = StorageError.encodingFailed("test detail")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("test detail"), "エラーメッセージに詳細を含む: \(desc)")
    }

    func testDecodingFailedDescription() {
        let error = StorageError.decodingFailed("parse error")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("parse error"), "エラーメッセージに詳細を含む: \(desc)")
    }

    func testFileNotFoundDescription() {
        let url = URL(fileURLWithPath: "/test/file.json")
        let error = StorageError.fileNotFound(url)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("file.json"), "エラーメッセージにファイル名を含む: \(desc)")
    }

    func testSessionNotFoundDescription() {
        let id = UUID()
        let error = StorageError.sessionNotFound(id)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains(id.uuidString), "エラーメッセージにUUIDを含む: \(desc)")
    }
}
