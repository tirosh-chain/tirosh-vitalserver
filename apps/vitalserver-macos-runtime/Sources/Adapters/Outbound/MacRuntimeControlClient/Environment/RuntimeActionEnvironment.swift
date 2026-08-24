import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeActionEnvironment: Sendable {
    func executableState(atPath path: String) -> RuntimeFileState
    func writeAdminPasswordFile(_ password: String) throws -> URL
    func writeRecorderIngressSettingsFile(_ settings: RuntimeRecorderIngressSettings) throws -> URL
    func removeItem(at url: URL) throws
    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult
}

struct SystemRuntimeActionEnvironment: RuntimeActionEnvironment, @unchecked Sendable {
    private let fileStore: RuntimeFileStore
    private let temporaryDirectory: URL
    private let adminPasswordFileID: @Sendable () -> String
    private let recorderIngressSettingsFileID: @Sendable () -> String

    init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        temporaryDirectory: URL = URL(fileURLWithPath: "/private/tmp", isDirectory: true),
        adminPasswordFileID: @escaping @Sendable () -> String = { UUID().uuidString },
        recorderIngressSettingsFileID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.fileStore = fileStore
        self.temporaryDirectory = temporaryDirectory
        self.adminPasswordFileID = adminPasswordFileID
        self.recorderIngressSettingsFileID = recorderIngressSettingsFileID
    }

    func executableState(atPath path: String) -> RuntimeFileState {
        fileStore.fileState(atPath: path)
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
        let url = temporaryDirectory
            .appendingPathComponent("tirosh-vitalserver-admin-password-\(adminPasswordFileID())")
        try writeSecretText(password, to: url, failure: RuntimeActionEnvironmentError.adminPasswordFileCreateFailed)
        return url
    }

    func writeRecorderIngressSettingsFile(_ settings: RuntimeRecorderIngressSettings) throws -> URL {
        let url = temporaryDirectory
            .appendingPathComponent("tirosh-vitalserver-recorder-ingress-settings-\(recorderIngressSettingsFileID()).json")
        do {
            let data = try JSONEncoder().encode(settings)
            try fileStore.writeData(data, to: url, options: [], posixPermissions: 0o600)
        } catch {
            throw RuntimeActionEnvironmentError.recorderIngressSettingsFileCreateFailed(
                path: url.path,
                reason: error.localizedDescription
            )
        }
        return url
    }

    private func writeSecretText(
        _ text: String,
        to url: URL,
        failure: (String, String) -> RuntimeActionEnvironmentError
    ) throws {
        let password = text
        guard let data = password.data(using: .utf8) else {
            throw RuntimeActionEnvironmentError.invalidAdminPassword
        }
        do {
            try fileStore.writeData(data, to: url, options: [], posixPermissions: 0o600)
        } catch {
            throw failure(url.path, error.localizedDescription)
        }
    }

    func removeItem(at url: URL) throws {
        try fileStore.removeItem(at: url)
    }

    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult {
        await ProcessRunner.run(
            launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.verifyUpdateBootstrap,
                bundleURL.path,
            ],
            environment: [
                RuntimeControlClientConstants.Environment.vmHome:
                    RuntimeControlClientConstants.Paths.vmHome,
            ]
        )
    }
}
