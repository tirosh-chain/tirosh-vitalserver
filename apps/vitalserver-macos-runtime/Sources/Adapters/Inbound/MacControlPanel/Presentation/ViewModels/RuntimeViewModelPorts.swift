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
    func loadVitalDBRelationships() async -> RuntimeVitalRelationshipHistory
    func loadBackups(latestBackupPath: String?) async throws -> [RuntimeBackup]
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
    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL?
    func logExportDestinationValidationMessage(for url: URL) -> String?
    func directoryExists(_ url: URL) -> Bool
    func confirmCreateDirectory(path: String) -> Bool
    func createDirectory(_ url: URL) throws
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
    public func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? { nil }
    public func logExportDestinationValidationMessage(for url: URL) -> String? { nil }
    public func directoryExists(_ url: URL) -> Bool { false }
    public func confirmCreateDirectory(path: String) -> Bool { false }
    public func createDirectory(_ url: URL) throws {}
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
