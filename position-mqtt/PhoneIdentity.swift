import Foundation

enum PhoneIdentity {
    /// Accepts `AA:BB:CC:DD:EE:FF`, dashes, or 12 hex digits. Returns uppercase colon form.
    static func normalize(_ raw: String) -> String? {
        var hex = ""
        for scalar in raw.uppercased().unicodeScalars {
            if CharacterSet(charactersIn: "0123456789ABCDEF").contains(scalar) {
                hex.append(Character(scalar))
            } else if scalar == ":" || scalar == "-" || scalar == " " || scalar == "\n" || scalar == "\t" {
                continue
            } else {
                return nil
            }
        }
        guard hex.count == 12 else { return nil }
        var bytes: [String] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(String(hex[index..<next]))
            index = next
        }
        return bytes.joined(separator: ":")
    }

    static func clientID(for mac: String) -> String {
        "iphone-" + mac.replacingOccurrences(of: ":", with: "")
    }
}
