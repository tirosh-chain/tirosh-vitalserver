import Foundation

public enum UpdateBundleChecksumFileParser {
    public static func parse(_ text: String) -> [String: String] {
        var checksums: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else {
                continue
            }
            checksums[String(parts[1]).trimmingCharacters(in: .whitespaces)] = String(parts[0])
        }
        return checksums
    }
}
