import Contracts
import Foundation
import Errors

public enum RuntimePackageReceiptStateReader {
    public static func states(
        identifiers: [String],
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> [RuntimePackageReceiptState] {
        identifiers.map { identifier in
            state(identifier: identifier, runProcess: runProcess)
        }
    }

    public static func state(
        identifier: String,
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> RuntimePackageReceiptState {
        let catalogResult = runProcess("/usr/sbin/pkgutil", ["--pkgs"])
        guard catalogResult.exitCode == 0,
              catalogResult.executionIssue == nil,
              catalogResult.outputIssues.isEmpty
        else {
            return .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt catalog read failed \(processFailureReason(catalogResult))"
            )
        }

        let catalogIdentifiers = catalogResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let matchingIdentifiers = catalogIdentifiers.filter { $0 == identifier }
        guard matchingIdentifiers.count <= 1 else {
            return .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt catalog contains duplicate package-id value=\(identifier)"
            )
        }
        guard matchingIdentifiers.count == 1 else {
            return .absent(identifier: identifier)
        }

        let infoResult = runProcess(
            "/usr/sbin/pkgutil",
            ["--pkg-info-plist", identifier]
        )
        guard infoResult.exitCode == 0,
              infoResult.executionIssue == nil,
              infoResult.outputIssues.isEmpty
        else {
            return .readFailed(
                identifier: identifier,
                reason: "pkgutil receipt info read failed \(processFailureReason(infoResult))"
            )
        }
        return successfulReceiptState(
            expectedIdentifier: identifier,
            output: infoResult.stdout
        )
    }

    public static func processFailureReason(_ result: RuntimeProcessResult) -> String {
        RuntimeProcessFailureMessageFormatter.message(result)
    }

    private static func successfulReceiptState(
        expectedIdentifier: String,
        output: String
    ) -> RuntimePackageReceiptState {
        let data = Data(output.utf8)
        let duplicateKeys = duplicateRequiredKeys(in: data)
        guard duplicateKeys.isEmpty else {
            return .readFailed(
                identifier: expectedIdentifier,
                reason: "pkgutil receipt plist contains duplicate key=\(duplicateKeys[0])"
            )
        }
        let info: PackageInfoPlist
        do {
            info = try PropertyListDecoder().decode(PackageInfoPlist.self, from: data)
        } catch {
            return .readFailed(
                identifier: expectedIdentifier,
                reason: "pkgutil receipt plist decode failed \(String(describing: error))"
            )
        }
        guard info.packageIdentifier == expectedIdentifier else {
            return .readFailed(
                identifier: expectedIdentifier,
                reason: "pkgutil receipt identifier mismatch actual=\(info.packageIdentifier) expected=\(expectedIdentifier)"
            )
        }
        guard let version = RuntimePackageVersion(rawValue: info.version) else {
            return .readFailed(
                identifier: expectedIdentifier,
                reason: "pkgutil receipt version is invalid value=\(info.version)"
            )
        }
        return .present(identifier: expectedIdentifier, version: version)
    }

    private static func duplicateRequiredKeys(in data: Data) -> [String] {
        let counter = RequiredPlistKeyCounter()
        let parser = XMLParser(data: data)
        parser.delegate = counter
        guard parser.parse() else {
            return []
        }
        return ["pkgid", "pkg-version"].filter { key in
            counter.keys.filter { $0 == key }.count > 1
        }
    }

    private struct PackageInfoPlist: Decodable {
        let packageIdentifier: String
        let version: String

        private enum CodingKeys: String, CodingKey {
            case packageIdentifier = "pkgid"
            case version = "pkg-version"
        }
    }
}

private final class RequiredPlistKeyCounter: NSObject, XMLParserDelegate {
    var keys: [String] = []
    private var keyCharacters: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "key" {
            keyCharacters = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard keyCharacters != nil else {
            return
        }
        keyCharacters?.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "key", let keyCharacters else {
            return
        }
        keys.append(keyCharacters.trimmingCharacters(in: .whitespacesAndNewlines))
        self.keyCharacters = nil
    }
}
