import Foundation
import RuntimeControl
import RuntimeCore
import HostRuntimeInfrastructure

@MainActor
public protocol RuntimeStatusReading {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func legacyCommandProgressLine() -> String?
}

@MainActor
public struct SystemRuntimeStatusReader: RuntimeStatusReading {
    public let paths: RuntimePaths
    public var commandLogPath = RuntimeAdapterConstants.Paths.commandLogFile
    private let fileStore: RuntimeFileStore
    private let storageUsageProvider: RuntimeStorageUsageProviding

    public init(
        paths: RuntimePaths,
        commandLogPath: String = RuntimeAdapterConstants.Paths.commandLogFile,
        fileStore: RuntimeFileStore = LocalRuntimeFileStore(),
        storageUsageProvider: RuntimeStorageUsageProviding? = nil
    ) {
        self.paths = paths
        self.commandLogPath = commandLogPath
        self.fileStore = fileStore
        self.storageUsageProvider = storageUsageProvider ?? LocalRuntimeStorageUsageProvider(fileStore: fileStore)
    }

    public func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        withDataStorageUsage(loadBaseStatus(), settings: settings)
    }

    public func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        var next = loadBaseStatus()

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort))
        next.redisUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.redisUIURL(proxyPort: next.proxyPort))
        next.swaggerUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.swaggerURL(proxyPort: next.proxyPort))

        return withDataStorageUsage(next, settings: settings)
    }

    public func loadBaseStatus() -> RuntimeStatus {
        let statusRepository = JSONFileRuntimeStatusRepository(url: URL(fileURLWithPath: paths.runtimeStatus))
        let document = statusRepository.load()
        let guestState = guestRuntimeStateDocument(paths.runtimeState)
        return RuntimeStatus(
            runtimeInstalled: fileStore.isExecutableFile(atPath: paths.launcher),
            vmServiceLoaded: loaded(document?.vmService) ?? launchdLoaded(.vm),
            proxyServiceLoaded: loaded(document?.proxyService) ?? launchdLoaded(.proxy),
            watchdogServiceLoaded: loaded(document?.watchdogService) ?? launchdLoaded(.watchdog),
            runtimeState: document.map { RuntimeState(rawValue: $0.status.rawValue) },
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

    public func legacyCommandProgressLine() -> String? {
        let url = URL(fileURLWithPath: commandLogPath)
        guard fileStore.fileExists(url),
              let content = try? fileStore.readUTF8Text(url)
        else {
            return nil
        }
        return LegacyCommandProgressParser.progressMessage(from: content)
    }

    private func httpStatus(url: String) async -> String {
        let result = await ProcessRunner.run(
            RuntimeAdapterConstants.Commands.curl,
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !code.isEmpty ? code : RuntimeAdapterConstants.StatusText.failed
    }

    private func withDataStorageUsage(_ status: RuntimeStatus, settings: RuntimeSettings) -> RuntimeStatus {
        var next = status
        next.dataStorage = storageUsageProvider.storageUsage(for: settings.vitalFilesDirectory)
        return next
    }

    private func guestRuntimeStateDocument(_ path: String) -> GuestRuntimeStateDocument? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
    }

    private func loaded(_ value: RuntimeServiceState?) -> Bool? {
        guard let value else {
            return nil
        }
        return value.isLoaded
    }

    private func launchdLoaded(_ service: RuntimeManagedService) -> Bool {
        ProcessRunner.runSync(
            RuntimeAdapterConstants.Commands.launchctl,
            arguments: ["print", "system/\(service.label)"]
        ).exitCode == 0
    }

    private func readTrimmed(_ path: String) -> String? {
        guard let value = try? fileStore.readUTF8Text(URL(fileURLWithPath: path))
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func proxyPort(_ plistPath: String) -> Int {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: plistPath)),
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
            return RuntimeAdapterConstants.Product.defaultProxyPort
        }
        return port
    }

}

public struct LegacyCommandProgressParser {
    public static func progressMessage(from content: String) -> String? {
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
