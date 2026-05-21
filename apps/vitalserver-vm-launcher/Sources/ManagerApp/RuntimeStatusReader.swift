import Foundation
import RuntimeCore

@MainActor
protocol RuntimeStatusReading {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func legacyCommandProgressLine() -> String?
}

@MainActor
struct SystemRuntimeStatusReader: RuntimeStatusReading {
    let paths: RuntimePaths
    var commandLogPath = AppConstants.Paths.commandLogFile

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        withDataStorageUsage(loadBaseStatus(), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        var next = loadBaseStatus()

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: AppConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: AppConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort))
        next.redisUIHTTP = await httpStatus(url: AppConstants.Product.redisUIURL(proxyPort: next.proxyPort))
        next.swaggerUIHTTP = await httpStatus(url: AppConstants.Product.swaggerURL(proxyPort: next.proxyPort))

        return withDataStorageUsage(next, settings: settings)
    }

    func loadBaseStatus() -> RuntimeStatus {
        let statusRepository = JSONFileRuntimeStatusRepository(url: URL(fileURLWithPath: paths.runtimeStatus))
        let document = statusRepository.load()
        let guestState = guestRuntimeStateDocument(paths.runtimeState)
        return RuntimeStatus(
            runtimeInstalled: FileManager.default.isExecutableFile(atPath: paths.launcher),
            vmServiceLoaded: loaded(document?.vmService) ?? launchdLoaded(AppConstants.Launchd.vmService),
            proxyServiceLoaded: loaded(document?.proxyService) ?? launchdLoaded(AppConstants.Launchd.proxyService),
            watchdogServiceLoaded: loaded(document?.watchdogService) ?? launchdLoaded(AppConstants.Launchd.watchdogService),
            runtimeState: document?.status.rawValue,
            operation: document?.operation.rawValue,
            statusMessage: document?.message,
            updatedAt: document?.updatedAt,
            runtimeVersion: document?.runtimeVersion,
            latestBackup: document?.latestBackup,
            vmIP: document?.vmIP ?? guestState?.vmIP ?? readTrimmed(paths.vmIPFile),
            guestHTTP: document?.guestHTTP ?? guestState?.guestHTTP,
            hostProxyHTTP: document?.hostProxyHTTP,
            redisUIHTTP: document?.redisUIHTTP ?? guestState?.redisUIHTTP,
            swaggerUIHTTP: document?.swaggerUIHTTP ?? guestState?.swaggerUIHTTP,
            cpuUsagePercent: guestState?.cpuUsagePercent,
            memory: guestState?.memory,
            systemDisk: guestState?.systemDisk,
            dataStorage: nil,
            proxyPort: document?.proxyPort ?? proxyPort(paths.proxyLaunchDaemon),
            failureReasons: document?.failureReasons ?? [],
            progress: document?.progress
        )
    }

    func legacyCommandProgressLine() -> String? {
        guard FileManager.default.fileExists(atPath: commandLogPath),
              let content = try? String(contentsOfFile: commandLogPath, encoding: .utf8)
        else {
            return nil
        }
        return LegacyCommandProgressParser.progressMessage(from: content)
    }

    private func httpStatus(url: String) async -> String {
        let result = await ProcessRunner.run(
            AppConstants.Commands.curl,
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !code.isEmpty ? code : AppConstants.StatusText.failed
    }

    private func withDataStorageUsage(_ status: RuntimeStatus, settings: RuntimeSettings) -> RuntimeStatus {
        var next = status
        next.dataStorage = storageUsage(for: settings.vitalFilesDirectory)
        return next
    }

    private func storageUsage(for path: String) -> ResourceUsage? {
        guard let volumeURL = existingStorageURL(for: path),
              let values = try? volumeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey,
            ]),
              let total = values.volumeTotalCapacity,
              total > 0 else {
            return nil
        }

        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
            ?? 0
        return ResourceUsage(
            usedBytes: max(Int64(total) - available, 0),
            totalBytes: Int64(total)
        )
    }

    private func existingStorageURL(for path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else {
                return nil
            }
            url = parent
        }
        return url
    }

    private func guestRuntimeStateDocument(_ path: String) -> GuestRuntimeStateDocument? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
    }

    private func loaded(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        return value == AppConstants.Values.launchdLoaded
    }

    private func launchdLoaded(_ label: String) -> Bool {
        ProcessRunner.runSync(
            AppConstants.Commands.launchctl,
            arguments: ["print", "system/\(label)"]
        ).exitCode == 0
    }

    private func readTrimmed(_ path: String) -> String? {
        guard let value = try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func proxyPort(_ plistPath: String) -> Int {
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
}

struct LegacyCommandProgressParser {
    static func progressMessage(from content: String) -> String? {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .reversed()

        for rawLine in lines {
            let line = normalizedProgressLine(rawLine)
            if line.isEmpty {
                continue
            }
            if let progress = commandProgressMessage(from: line) {
                return progress
            }
        }
        return nil
    }

    private static func normalizedProgressLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closing = trimmed.firstIndex(of: "]") else {
            return trimmed
        }
        let afterTimestamp = trimmed.index(after: closing)
        return String(trimmed[afterTimestamp...]).trimmingCharacters(in: .whitespaces)
    }

    private static func commandProgressMessage(from line: String) -> String? {
        if line.contains("waiting for runtime health reasons=") {
            let reasons = value(after: "reasons=", in: line) ?? line
            return "Waiting for runtime health: \(reasons)"
        }
        if line.contains("waiting for guest update activation result") {
            return "Waiting for VM update activation..."
        }
        if line.contains("guest update activation completed") {
            return "VM update activation completed."
        }
        if line.contains("runtime health ok") {
            return "Runtime health check passed."
        }
        if line.contains("bundle apply started") {
            return "Update bundle apply started."
        }
        if line.contains("bundle apply completed") {
            return "Update bundle apply completed."
        }
        if line.contains("bundle apply failed") {
            return "Update bundle apply failed."
        }
        if line.contains("running migration") {
            return line
        }
        if let step = value(after: "step=", in: line),
           let status = value(after: "status=", in: line) {
            return "\(stepStatusText(status)): \(humanizeStepName(step))"
        }
        if line.contains("error:") || line.contains("status=failed") {
            return line
        }
        return nil
    }

    private static func value(after marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else {
            return nil
        }
        let remainder = line[range.upperBound...]
        guard let token = remainder.split(separator: " ").first else {
            return nil
        }
        return String(token)
    }

    private static func stepStatusText(_ status: String) -> String {
        switch status {
        case "started":
            return "Running"
        case "completed":
            return "Completed"
        case "failed":
            return "Failed"
        default:
            return status.capitalized
        }
    }

    private static func humanizeStepName(_ step: String) -> String {
        step
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
