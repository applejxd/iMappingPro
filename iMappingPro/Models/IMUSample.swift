import Foundation

enum IMUSensor: String, Codable {
    case accelerometer
    case gyroscope
}

struct IMUSample: Codable, Equatable {
    let sensor: IMUSensor
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double

    static func csvData(from samples: [IMUSample]) -> Data {
        let locale = Locale(identifier: "en_US_POSIX")
        let sortedSamples = samples.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.sensor.rawValue < $1.sensor.rawValue
            }
            return $0.timestamp < $1.timestamp
        }
        var csv = "sensor,timestamp,x,y,z\n"
        for sample in sortedSamples {
            let timestamp = String(format: "%.9f", locale: locale, sample.timestamp)
            let x = String(format: "%.9f", locale: locale, sample.x)
            let y = String(format: "%.9f", locale: locale, sample.y)
            let z = String(format: "%.9f", locale: locale, sample.z)
            csv += "\(sample.sensor.rawValue),\(timestamp),\(x),\(y),\(z)\n"
        }
        return Data(csv.utf8)
    }
}
