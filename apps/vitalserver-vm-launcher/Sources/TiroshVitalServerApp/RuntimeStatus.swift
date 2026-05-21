import Foundation

struct RuntimeStatus {
    var runtimeInstalled = false
    var vmServiceLoaded = false
    var proxyServiceLoaded = false
    var watchdogServiceLoaded = false
    var runtimeState: String?
    var operation: String?
    var statusMessage: String?
    var updatedAt: String?
    var runtimeVersion: String?
    var latestBackup: String?
    var vmIP: String?
    var guestHTTP: String?
    var hostProxyHTTP: String?
    var proxyPort = AppConstants.Product.defaultProxyPort
    var failureReasons: [String] = []

    var isReady: Bool {
        runtimeInstalled
            && vmServiceLoaded
            && proxyServiceLoaded
            && watchdogServiceLoaded
            && runtimeState == AppConstants.Values.stateHealthy
            && vmIP != nil
            && isSuccessfulHTTPStatus(guestHTTP)
            && isSuccessfulHTTPStatus(hostProxyHTTP)
    }

    var displayMessage: String? {
        var lines: [String] = []
        if let statusMessage, !statusMessage.isEmpty {
            lines.append(statusMessage)
        }
        if !failureReasons.isEmpty {
            lines.append("\(AppConstants.Labels.failureReasons): \(failureReasons.joined(separator: ", "))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func load(paths: RuntimePaths) -> RuntimeStatus {
        let document = runtimeStatusDocument(paths.runtimeStatus)
        let guestState = guestRuntimeStateDocument(paths.runtimeState)
        return RuntimeStatus(
            runtimeInstalled: FileManager.default.isExecutableFile(atPath: paths.launcher),
            vmServiceLoaded: loaded(document?.vmService) ?? launchdLoaded(AppConstants.Launchd.vmService),
            proxyServiceLoaded: loaded(document?.proxyService) ?? launchdLoaded(AppConstants.Launchd.proxyService),
            watchdogServiceLoaded: loaded(document?.watchdogService) ?? launchdLoaded(AppConstants.Launchd.watchdogService),
            runtimeState: document?.status,
            operation: document?.operation,
            statusMessage: document?.message,
            updatedAt: document?.updatedAt,
            runtimeVersion: document?.runtimeVersion,
            latestBackup: document?.latestBackup,
            vmIP: document?.vmIP ?? guestState?.vmIP ?? readTrimmed(paths.vmIPFile),
            guestHTTP: document?.guestHTTP,
            hostProxyHTTP: document?.hostProxyHTTP,
            proxyPort: document?.proxyPort ?? proxyPort(paths.proxyLaunchDaemon),
            failureReasons: document?.failureReasons ?? []
        )
    }

    private static func runtimeStatusDocument(_ path: String) -> RuntimeStatusDocument? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(RuntimeStatusDocument.self, from: data)
    }

    private static func guestRuntimeStateDocument(_ path: String) -> GuestRuntimeStateDocument? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
    }

    private static func loaded(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        return value == AppConstants.Values.launchdLoaded
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
    let runtimeState = AppConstants.Paths.runtimeState
    let runtimeStatus = AppConstants.Paths.runtimeStatus
    let proxyLaunchDaemon = AppConstants.Paths.proxyLaunchDaemon
}

private struct GuestRuntimeStateDocument: Decodable {
    let vmIP: String
}

private struct RuntimeStatusDocument: Decodable {
    let status: String
    let operation: String
    let message: String
    let updatedAt: String
    let runtimeVersion: String
    let vmService: String
    let proxyService: String
    let watchdogService: String
    let vmIP: String?
    let proxyPort: Int
    let hostProxyHTTP: String
    let guestHTTP: String
    let failureReasons: [String]
    let latestBackup: String?
}
