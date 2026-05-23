import Foundation
import RuntimeControl
import RuntimeCore
import HostRuntimeInfrastructure

@MainActor
public protocol RuntimeActionEnvironment {
    func isExecutable(atPath path: String) -> Bool
    func createDirectory(at url: URL)
    func writeAdminPasswordFile(_ password: String) throws -> URL
    func removeItem(at url: URL)
    func verifyBundle(launcher: String, bundleURL: URL) async -> ProcessResult
}

@MainActor
public struct SystemRuntimeActionEnvironment: RuntimeActionEnvironment {
    private let fileStore: RuntimeFileStore

    public init(fileStore: RuntimeFileStore = LocalRuntimeFileStore()) {
        self.fileStore = fileStore
    }

    public func isExecutable(atPath path: String) -> Bool {
        fileStore.isExecutableFile(atPath: path)
    }

    public func createDirectory(at url: URL) {
        try? fileStore.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func writeAdminPasswordFile(_ password: String) throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("tirosh-vitalserver-admin-password-\(UUID().uuidString)")
        guard let data = password.data(using: .utf8) else {
            throw RuntimeActionEnvironmentError.invalidAdminPassword
        }
        do {
            try fileStore.writeData(data, to: url, options: [], posixPermissions: 0o600)
        } catch {
            throw RuntimeActionEnvironmentError.adminPasswordFileCreateFailed
        }
        return url
    }

    public func removeItem(at url: URL) {
        try? fileStore.removeItem(at: url)
    }

    public func verifyBundle(launcher: String, bundleURL: URL) async -> ProcessResult {
        await ProcessRunner.run(
            launcher,
            arguments: [
                RuntimeAdapterConstants.RuntimeCommand.runtime,
                RuntimeAdapterConstants.RuntimeCommand.verifyBundle,
                bundleURL.path,
            ]
        )
    }
}

enum RuntimeActionEnvironmentError: LocalizedError {
    case invalidAdminPassword
    case adminPasswordFileCreateFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password must be UTF-8."
        case .adminPasswordFileCreateFailed:
            return "Failed to prepare the admin password file."
        }
    }
}
