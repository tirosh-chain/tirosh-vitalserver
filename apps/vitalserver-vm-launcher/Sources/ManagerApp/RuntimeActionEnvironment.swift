import Foundation

@MainActor
protocol RuntimeActionEnvironment {
    func isExecutable(atPath path: String) -> Bool
    func createDirectory(at url: URL)
    func writeAdminPasswordFile(_ password: String) throws -> URL
    func removeItem(at url: URL)
    func verifyBundle(launcher: String, bundlePath: String) async -> ProcessResult
}

@MainActor
struct SystemRuntimeActionEnvironment: RuntimeActionEnvironment {
    func isExecutable(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    func createDirectory(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("tirosh-vitalserver-admin-password-\(UUID().uuidString)")
        guard let data = password.data(using: .utf8) else {
            throw RuntimeControllerError.invalidAdminPassword
        }
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw RuntimeControllerError.adminPasswordFileCreateFailed
        }
        return url
    }

    func removeItem(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func verifyBundle(launcher: String, bundlePath: String) async -> ProcessResult {
        await ProcessRunner.run(
            launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.verifyBundle,
                bundlePath,
            ]
        )
    }
}
