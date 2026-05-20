import Foundation

struct RuntimeStatus {
    var runtimeInstalled = false
    var vmServiceLoaded = false
    var proxyServiceLoaded = false
    var vmIP: String?
    var guestHTTP: String?
    var hostProxyHTTP: String?

    var isReady: Bool {
        runtimeInstalled
            && vmServiceLoaded
            && proxyServiceLoaded
            && vmIP != nil
            && isSuccessfulHTTPStatus(guestHTTP)
            && isSuccessfulHTTPStatus(hostProxyHTTP)
    }

    static func load(paths: RuntimePaths) -> RuntimeStatus {
        RuntimeStatus(
            runtimeInstalled: FileManager.default.isExecutableFile(atPath: paths.launcher),
            vmServiceLoaded: launchdLoaded(AppConstants.Launchd.vmService),
            proxyServiceLoaded: launchdLoaded(AppConstants.Launchd.proxyService),
            vmIP: readTrimmed(paths.vmIPFile),
            guestHTTP: nil,
            hostProxyHTTP: nil
        )
    }

    private static func launchdLoaded(_ label: String) -> Bool {
        ProcessRunner.runSync(
            AppConstants.Commands.launchctl,
            arguments: ["print", "system/\(label)"]
        ).exitCode == 0
    }

    private static func readTrimmed(_ path: String) -> String? {
        guard let value = try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 400
    }
}

struct RuntimePaths {
    let launcher = AppConstants.Paths.launcher
    let uninstaller = AppConstants.Paths.uninstaller
    let vmIPFile = AppConstants.Paths.vmIPFile
}
