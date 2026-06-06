import Foundation
import RuntimeControl
import Application
import Contracts
import Domain
import Errors

protocol RuntimeActionEnvironment: Sendable {
    func isExecutable(atPath path: String) -> Bool
    func writeAdminPasswordFile(_ password: String) throws -> URL
    func removeItem(at url: URL)
    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult
}

struct SystemRuntimeActionEnvironment: RuntimeActionEnvironment, @unchecked Sendable {
    private let fileStore: RuntimeFileStore

    init(fileStore: RuntimeFileStore = SystemRuntimeFileStore()) {
        self.fileStore = fileStore
    }

    func isExecutable(atPath path: String) -> Bool {
        fileStore.isExecutableFile(atPath: path)
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
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

    func removeItem(at url: URL) {
        try? fileStore.removeItem(at: url)
    }

    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult {
        await ProcessRunner.run(
            launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.verifyBundle,
                bundleURL.path,
            ]
        )
    }
}

