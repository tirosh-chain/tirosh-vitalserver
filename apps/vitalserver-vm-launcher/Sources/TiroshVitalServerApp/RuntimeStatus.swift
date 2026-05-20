import Foundation

struct RuntimeStatus {
    var runtimeInstalled = false
    var vmServiceLoaded = false
    var proxyServiceLoaded = false
    var vmIP: String?
    var guestHTTP: String?
    var hostProxyHTTP: String?
    var proxyPort = AppConstants.Product.defaultProxyPort

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
            hostProxyHTTP: nil,
            proxyPort: proxyPort(paths.proxyLaunchDaemon)
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

    private static func proxyPort(_ plistPath: String) -> Int {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let document = plist as? [String: Any],
              let environment = document["EnvironmentVariables"] as? [String: Any],
              let rawPort = environment["VITALSERVER_PROXY_PORT"] as? String,
              let port = Int(rawPort),
              (1...65_535).contains(port)
        else {
            return AppConstants.Product.defaultProxyPort
        }
        return port
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
    let proxyLaunchDaemon = AppConstants.Paths.proxyLaunchDaemon
}
