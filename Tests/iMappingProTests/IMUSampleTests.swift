import XCTest
@testable import iMappingProCore

final class IMUSampleTests: XCTestCase {

    func testCSVIncludesPerSampleTimestampsAndSortsSamples() {
        let samples = [
            IMUSample(sensor: .gyroscope, timestamp: 2, x: 0.1, y: 0.2, z: 0.3),
            IMUSample(sensor: .accelerometer, timestamp: 1, x: -0.1, y: 0, z: 1),
        ]

        let csv = String(decoding: IMUSample.csvData(from: samples), as: UTF8.self)

        XCTAssertEqual(
            csv,
            """
            sensor,timestamp,x,y,z
            accelerometer,1.000000000,-0.100000000,0.000000000,1.000000000
            gyroscope,2.000000000,0.100000000,0.200000000,0.300000000

            """
        )
    }

    func testCSVHasHeaderWhenNoSamplesAreAvailable() {
        let csv = String(decoding: IMUSample.csvData(from: []), as: UTF8.self)

        XCTAssertEqual(csv, "sensor,timestamp,x,y,z\n")
    }
}
