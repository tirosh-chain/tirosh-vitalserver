import Foundation

public enum RuntimeTestKitVitalFileUploadPolicy {
    public static func bedRoomName(filename: String) -> String? {
        guard filename.count > 20,
              filename.hasSuffix(".vital") else {
            return nil
        }

        let suffixStart = filename.index(filename.endIndex, offsetBy: -20)
        let bedName = String(filename[..<suffixStart])
        let suffix = String(filename[suffixStart...])

        guard !bedName.isEmpty,
              suffix.count == 20,
              suffix.first == "_",
              suffix[suffix.index(suffix.startIndex, offsetBy: 7)] == "_",
              suffix.hasSuffix(".vital") else {
            return nil
        }

        let yymmddStart = suffix.index(after: suffix.startIndex)
        let yymmddEnd = suffix.index(yymmddStart, offsetBy: 6)
        let hhmmssStart = suffix.index(after: yymmddEnd)
        let hhmmssEnd = suffix.index(hhmmssStart, offsetBy: 6)

        guard suffix[yymmddStart..<yymmddEnd].allSatisfy(\.isNumber),
              suffix[hhmmssStart..<hhmmssEnd].allSatisfy(\.isNumber) else {
            return nil
        }

        return bedName
    }

    public static func uniqueBedRoomNames(filePaths: [String]) throws -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for path in filePaths {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            guard let bedName = bedRoomName(filename: filename) else {
                throw RuntimeTestKitVitalFileUploadError.invalidFilename(filename)
            }
            if seen.insert(bedName).inserted {
                names.append(bedName)
            }
        }
        return names
    }
}

public enum RuntimeTestKitVitalFileUploadError: Error, Equatable, LocalizedError, Sendable {
    case noFilesSelected
    case invalidFilename(String)
    case missingProxyPort
    case uploadNotAvailable

    public var errorDescription: String? {
        switch self {
        case .noFilesSelected:
            return "Select at least one .vital file."
        case .invalidFilename(let filename):
            return "Invalid .vital filename: \(filename). Expected bedname_yymmdd_hhmmss.vital."
        case .missingProxyPort:
            return "VitalServer host proxy port is not available."
        case .uploadNotAvailable:
            return "Manual .vital upload is unavailable for this TestKit controller."
        }
    }
}
