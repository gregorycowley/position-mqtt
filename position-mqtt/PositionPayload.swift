import Foundation

enum PayloadFormat: String, Equatable {
    case json
    case xy
    case region
    case xyRegion = "xy_region"
}

enum PositionPayload {
    static func make(mac: String, x: Double, y: Double, region: String, format: PayloadFormat) -> String {
        let xs = meters(x)
        let ys = meters(y)
        switch format {
        case .json:
            return #"{"mac":"\#(mac)","x":\#(xs),"y":\#(ys),"region":"\#(region)"}"#
        case .xy:
            return "\(xs),\(ys)"
        case .region:
            return region
        case .xyRegion:
            return "\(xs),\(ys),\(region)"
        }
    }

    static func meters(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
