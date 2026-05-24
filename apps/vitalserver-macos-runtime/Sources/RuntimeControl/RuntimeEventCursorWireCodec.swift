import Core
import Foundation

public enum RuntimeEventCursorWireCodec {
    public static func encode(_ cursor: RuntimeEventCursor) -> String {
        let payload = "\(cursor.timestamp)\n\(cursor.id)"
        return Data(payload.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    public static func decode(_ rawValue: String) -> RuntimeEventCursor? {
        guard !rawValue.isEmpty else {
            return nil
        }

        var encoded = rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: encoded),
              let payload = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return RuntimeEventCursor(timestamp: String(parts[0]), id: String(parts[1]))
    }
}
