import Application
import Contracts
import Foundation
import Errors

public enum RuntimeInstallSettingsStateReader {
    public static func state(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeInstallSettingsState {
        let url = URL(fileURLWithPath: path)
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing(path: path)
        case .inspectFailed(let reason):
            return .readFailed(path: path, reason: "settings path inspection failed: \(reason)")
        case .directory, .other, .unknown:
            return .readFailed(path: path, reason: "settings path state is unexpected: \(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(InstallSettingsProxyPortDocument.self, from: data)
            guard let proxyPort = document.proxyPort else {
                return .proxyPortMissing(path: path)
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

public enum RuntimeInstallArtifactStateReader {
    public static func states(
        paths: [String],
        fileStore: RuntimeFileReading
    ) -> [RuntimeInstallArtifactState] {
        paths.map { path in
            state(path: path, fileStore: fileStore)
        }
    }

    public static func state(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeInstallArtifactState {
        let state = fileStore.pathState(at: URL(fileURLWithPath: path))
        switch state {
        case .file, .directory, .other:
            return .present(path: path)
        case .missing:
            return .absent(path: path)
        case .inspectFailed(let reason):
            return .inspectFailed(path: path, reason: reason)
        case .unknown(let value):
            return .inspectFailed(path: path, reason: "unexpected path state: \(value)")
        }
    }
}
