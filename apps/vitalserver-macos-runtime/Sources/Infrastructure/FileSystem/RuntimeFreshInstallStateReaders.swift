import Application
import Contracts
import Foundation

public enum RuntimeInstallSettingsStateReader {
    public static func state(
        path: String,
        defaultProxyPort: Int,
        fileStore: RuntimeFileReading
    ) -> RuntimeInstallSettingsState {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return .defaulted(path: path, proxyPort: defaultProxyPort)
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(InstallSettingsProxyPortDocument.self, from: data)
            guard let proxyPort = document.proxyPort else {
                return .defaulted(path: path, proxyPort: defaultProxyPort)
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
        attributesOfItem: (String) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0)
        }
    ) -> [RuntimeInstallArtifactState] {
        paths.map { path in
            state(path: path, attributesOfItem: attributesOfItem)
        }
    }

    public static func state(
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
