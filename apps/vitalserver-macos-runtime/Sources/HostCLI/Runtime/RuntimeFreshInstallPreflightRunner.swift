import Core
import Contracts
import Foundation

struct RuntimeFreshInstallPreflightRunner {
    var settingsState: () -> RuntimeInstallSettingsState
    var artifactStates: () -> [RuntimeInstallArtifactState]
    var serviceStates: () -> [RuntimeFreshInstallServiceState]
    var packageReceiptStates: () -> [RuntimePackageReceiptState]
    var proxyPortState: (Int) -> RuntimeHostProxyPortState

    func run() -> RuntimeFreshInstallPreflightDocument {
        let settings = settingsState()
        let proxyState = settings.proxyPort.map(proxyPortState)
        return RuntimeFreshInstallPreflightPolicy.document(input: RuntimeFreshInstallPreflightInput(
            settingsState: settings,
            artifactStates: artifactStates(),
            serviceStates: serviceStates(),
            packageReceiptStates: packageReceiptStates(),
            proxyPortState: proxyState
        ))
    }
}

enum RuntimeInstallSettingsStateReader {
    static func state(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeInstallSettingsState {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .defaulted(path: path, proxyPort: InstallSettings.defaultProxyPort)
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(InstallSettingsProxyPortDocument.self, from: data)
            guard let proxyPort = document.proxyPort else {
                return .defaulted(path: path, proxyPort: InstallSettings.defaultProxyPort)
            }
            guard (1...65_535).contains(proxyPort) else {
                return .invalid(path: path, reason: "proxyPort out of range value=\(proxyPort)")
            }
            return .loaded(path: path, proxyPort: proxyPort)
        } catch let error as DecodingError {
            return .invalid(path: path, reason: decodingErrorReason(error))
        } catch {
            return .readFailed(path: path, reason: error.localizedDescription)
        }
    }

    private static func decodingErrorReason(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return context.debugDescription
        case .keyNotFound(let key, let context):
            return "key \(key.stringValue) missing: \(context.debugDescription)"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return String(describing: error)
        }
    }
}

private struct InstallSettingsProxyPortDocument: Decodable {
    let proxyPort: Int?
}

enum RuntimeInstallArtifactStateReader {
    static func states(
        paths: [String],
        attributesOfItem: (String) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0)
        }
    ) -> [RuntimeInstallArtifactState] {
        paths.map { path in
            state(path: path, attributesOfItem: attributesOfItem)
        }
    }

    static func state(
        path: String,
        attributesOfItem: (String) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0)
        }
    ) -> RuntimeInstallArtifactState {
        do {
            _ = try attributesOfItem(path)
            return .present(path: path)
        } catch {
            if isNoSuchFile(error) {
                return .absent(path: path)
            }
            return .inspectFailed(path: path, reason: error.localizedDescription)
        }
    }

    private static func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}

enum RuntimeHostProxyPortStateReader {
    static func state(
        port: Int,
        runProcess: (String, [String]) -> RuntimeProcessResult
    ) -> RuntimeHostProxyPortState {
        let result = runProcess(Constants.Commands.lsof, ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        if result.exitCode == 0 {
            let listeners = parsedListeners(result.stdout)
            return listeners.isEmpty
                ? .clear(port: port)
                : .occupied(port: port, listeners: listeners.joined(separator: ","))
        }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 1, stdout.isEmpty, stderr.isEmpty {
            return .clear(port: port)
        }
        return .inspectFailed(port: port, reason: processFailureReason(result))
    }

    private static func parsedListeners(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> String? in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else {
                    return nil
                }
                return "\(fields[0])/\(fields[1])"
            }
            .sorted()
    }

    private static func processFailureReason(_ result: RuntimeProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        return "exitCode=\(result.exitCode)"
    }
}
