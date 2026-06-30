import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimeViewModelSnapshotReading: Sendable {
    func loadSettings() async -> RuntimeSettings
    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() async -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderSummaries() async -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery) async -> RuntimeVitalRecorderActivityWindow
    func loadVitalDBRelationships() async -> RuntimeVitalRelationshipHistory
    func loadBackups(latestBackupPath: String?) async throws -> [RuntimeBackup]
    func loadRedisBackups() async throws -> [RuntimeBackup]
    func loadRuntimeDataBackups() async throws -> [RuntimeBackup]
}

public extension RuntimeViewModelSnapshotReading {
    func loadVitalDBRecorderSummaries() async -> RuntimeVitalRecorderHistory {
        await loadVitalDBRecorders()
    }
}

@MainActor
public protocol RuntimeControlLocalAPISettingsApplying: AnyObject {
    var runtimeControlPort: Int { get }
    func settingsWithLocalAPIPort(_ settings: RuntimeSettings) -> RuntimeSettings
    func apply(settings: RuntimeSettings)
    func apply(port: Int)
}

@MainActor
public protocol RuntimeNativeShell {
    func chooseDirectory(prompt: String) -> URL?
    func chooseUpdateBundle(prompt: String) -> URL?
    func chooseRedisBackupArchive(prompt: String) -> URL?
    func chooseVitalFiles(prompt: String, directoryURL: URL?) -> [URL]
    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL?
    func logExportDestinationValidationMessage(for url: URL) -> String?
    func pathState(_ url: URL) -> RuntimePathState
    func confirmCreateDirectory(path: String) -> Bool
    func createDirectory(_ url: URL) throws
    func copyFile(_ source: URL, to destination: URL) throws
    func copyDirectory(_ source: URL, to destination: URL) throws
    func openFileURL(_ url: URL)
    func openWebURL(_ url: URL)
    func relaunchHelper()
    func terminate()
}

@MainActor
public struct NoopRuntimeNativeShell: RuntimeNativeShell {
    public init() {}
    public func chooseDirectory(prompt: String) -> URL? { nil }
    public func chooseUpdateBundle(prompt: String) -> URL? { nil }
    public func chooseRedisBackupArchive(prompt: String) -> URL? { nil }
    public func chooseVitalFiles(prompt: String, directoryURL: URL?) -> [URL] { [] }
    public func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? { nil }
    public func logExportDestinationValidationMessage(for url: URL) -> String? { nil }
    public func pathState(_ url: URL) -> RuntimePathState { .inspectFailed("native shell is not configured") }
    public func confirmCreateDirectory(path: String) -> Bool { false }
    public func createDirectory(_ url: URL) throws {}
    public func copyFile(_ source: URL, to destination: URL) throws {
        throw NSError(
            domain: "NoopRuntimeNativeShell",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "native shell is not configured"]
        )
    }
    public func copyDirectory(_ source: URL, to destination: URL) throws {
        throw NSError(
            domain: "NoopRuntimeNativeShell",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "native shell is not configured"]
        )
    }
    public func openFileURL(_ url: URL) {}
    public func openWebURL(_ url: URL) {}
    public func relaunchHelper() {}
    public func terminate() {}
}

public protocol HealthNotifying {
    func configure()
    func notify(title: String, body: String)
}

public struct NoopHealthNotifier: HealthNotifying {
    public init() {}
    public func configure() {}
    public func notify(title: String, body: String) {}
}

public protocol RuntimeHelperMessageLogging: Sendable {
    func append(_ message: String)
}

public struct NoopRuntimeHelperMessageLog: RuntimeHelperMessageLogging {
    public init() {}
    public func append(_ message: String) {}
}
