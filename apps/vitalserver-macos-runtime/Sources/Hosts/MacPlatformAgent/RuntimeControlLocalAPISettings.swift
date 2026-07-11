import Application
import Foundation
import OutboundAdapters
import RuntimeControl

enum RuntimeControlLocalAPISettingsError: LocalizedError {
    case readFailed(path: String, reason: String)
    case invalidPort(path: String, port: Int)

    var errorDescription: String? {
        switch self {
        case .readFailed(let path, let reason):
            "Runtime Control API settings read failed path=\(path) reason=\(reason)"
        case .invalidPort(let path, let port):
            "Runtime Control API settings port is invalid path=\(path) port=\(port)"
        }
    }
}

struct RuntimeControlLocalAPISettingsReader {
    let documentURL: URL
    let fileStore: RuntimeFileReading

    init(
        documentURL: URL = InstalledRuntimePaths.defaultInstalled.runtimeControlSettings,
        fileStore: RuntimeFileReading = SystemRuntimeFileStore()
    ) {
        self.documentURL = documentURL
        self.fileStore = fileStore
    }

    func loadPort() throws -> Int {
        switch RuntimeControlSettingsDocument.loadResult(
            path: documentURL.path,
            fileStore: fileStore
        ) {
        case .missing:
            return RuntimeSettingsInitialValues.runtimeControlPort
        case .loaded(let settings):
            guard RuntimeSettingsReadPolicy.validRuntimeControlPort(settings.runtimeControlPort) else {
                throw RuntimeControlLocalAPISettingsError.invalidPort(
                    path: documentURL.path,
                    port: settings.runtimeControlPort
                )
            }
            return settings.runtimeControlPort
        case .failed(let reason):
            throw RuntimeControlLocalAPISettingsError.readFailed(
                path: documentURL.path,
                reason: reason
            )
        }
    }
}
