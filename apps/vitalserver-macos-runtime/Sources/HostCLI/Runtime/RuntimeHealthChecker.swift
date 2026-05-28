import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeHealthChecker {
    private let installedPaths: InstalledRuntimePaths
    private let fileStore: RuntimeFileStore
    private let serviceManager: RuntimeServiceManager
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let guestGateway: RuntimeGuestGateway
    private let now: () -> Date

    init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestGateway: RuntimeGuestGateway,
        now: @escaping () -> Date = Date.init
    ) {
        self.installedPaths = installedPaths
        self.fileStore = fileStore
        self.serviceManager = serviceManager
        self.commandRunner = commandRunner
        self.httpProber = httpProber
        self.guestGateway = guestGateway
        self.now = now
    }

    private var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    private var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    func snapshot() -> RuntimeHealthSnapshot {
        let loadedGuestState = guestRuntimeState()
        let guestRuntimeStateFresh = isGuestRuntimeStateFresh(loadedGuestState)
        let guestState = guestRuntimeStateFresh ? loadedGuestState : nil
        let vmIP = loadedGuestState?.vmIP ?? readTrimmed(installedPaths.vmIPFile)
        let proxyPort = installedProxyPort()
        let hostProxyHTTP = httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: proxyPort))
        let redisUIHTTP = httpProber.statusCode(url: Constants.Runtime.redisUIHealthURL(port: proxyPort))
        let swaggerUIHTTP = httpProber.statusCode(url: Constants.Runtime.swaggerUIHealthURL(port: proxyPort))
        let containerObservation = containerObservation(proxyPort: proxyPort, guestState: guestState)
        let guestHTTP = guestHTTPStatus(guestState: guestState, vmIP: vmIP)

        return RuntimeHealthEvaluator.evaluate(RuntimeHealthInput(
            vmExecutable: fileStore.isExecutableFile(atPath: Constants.InstallPaths.vmBin),
            proxyExecutable: fileStore.isExecutableFile(atPath: Constants.InstallPaths.proxyRun),
            rootfsBase: fileState(url: rootfsBase),
            vmDisk: fileState(url: vmDisk),
            vmService: launchdState(.vm),
            proxyService: launchdState(.proxy),
            watchdogService: launchdState(.watchdog),
            vmIP: vmIP,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            guestHTTP: guestHTTP,
            guestRuntimeStatePresent: loadedGuestState != nil,
            guestRuntimeStateFresh: guestRuntimeStateFresh,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            containerObservation: containerObservation,
            vitalDBObservation: guestState?.vitalDBObservation,
            vmDiagnosticErrors: vmDiagnosticErrors(
                hostProxyHTTP: hostProxyHTTP,
                guestHTTP: guestHTTP,
                guestRuntimeStateFresh: guestRuntimeStateFresh
            ),
            proxyPortFailureReasons: proxyPortFailureReasons(port: proxyPort),
            guestBootstrapFailureReason: guestBootstrapFailureReason()
        ))
    }

    func isLaunchdLoaded(_ service: RuntimeManagedService) -> Bool {
        launchdState(service).isLoaded
    }

    func fileState(path: String) -> RuntimeFileState {
        if fileStore.isExecutableFile(atPath: path) {
            return .executable
        }
        if fileStore.fileExists(URL(fileURLWithPath: path)) {
            return .present
        }
        return .missing
    }

    func fileState(url: URL) -> RuntimeFileState {
        fileStore.fileExists(url) ? .present : .missing
    }

    func launchdState(_ service: RuntimeManagedService) -> RuntimeServiceState {
        serviceManager.state(service: service)
    }

    func installedProxyPort() -> Int {
        let result = commandRunner.run(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Print :EnvironmentVariables:VITALSERVER_PROXY_PORT",
                RuntimeManagedService.proxy.launchDaemonPlist,
            ]
        )
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0,
              let port = Int(value),
              (1...65_535).contains(port)
        else {
            return InstallSettings.defaultProxyPort
        }
        return port
    }

    func guestRuntimeState() -> GuestRuntimeStateDocument? {
        guestGateway.loadRuntimeState()
    }

    private func isGuestRuntimeStateFresh(_ guestState: GuestRuntimeStateDocument?) -> Bool {
        guard guestState != nil else {
            return true
        }
        guard let modifiedAt = try? fileStore.modificationDate(installedPaths.runtimeState) else {
            return false
        }
        return now().timeIntervalSince(modifiedAt) <= Constants.Runtime.runtimeStateStaleAfterSeconds
    }

    func readTrimmed(_ url: URL) -> String? {
        guard let value = try? fileStore.readUTF8Text(url)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func guestHTTPStatus(guestState: GuestRuntimeStateDocument?, vmIP: String?) -> String {
        if let guestHTTP = guestState?.guestHTTP, !guestHTTP.isEmpty {
            return guestHTTP
        }
        if guestState != nil {
            return "bootstrap-pending"
        }
        if let vmIP {
            return httpProber.statusCode(url: "http://\(vmIP)\(Constants.Runtime.readinessPath)")
        }
        return "missing-vm-ip"
    }

    private func guestBootstrapFailureReason() -> RuntimeFailureReason? {
        if let bootstrapResult = guestGateway.loadBootstrapResult() {
            return GuestBootstrapEvaluator.failureReason(bootstrapResult)
        }

        guard fileStore.fileExists(installedPaths.bootstrapLog),
              let content = try? fileStore.readUTF8Text(installedPaths.bootstrapLog) else {
            return nil
        }
        return LegacyBootstrapLogEvaluator.failureReason(logContent: content)
    }

    private func proxyPortFailureReasons(port: Int) -> [RuntimeFailureReason] {
        guard fileStore.isExecutableFile(atPath: Constants.Commands.lsof) else {
            return []
        }
        let expectedNginxPID = readInstalledProxyNginxPID()
        let result = commandRunner.run(
            Constants.Commands.lsof,
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )
        guard result.exitCode == 0 else {
            return []
        }

        let listenerFields = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> (command: String, pid: String)? in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else {
                    return nil
                }
                return (String(fields[0]), String(fields[1]))
            }
        guard !listenerFields.isEmpty else {
            return []
        }

        let hasExpectedProxyNginx = expectedNginxPID.map { expectedPID in
            listenerFields.contains { $0.command == "nginx" && $0.pid == expectedPID }
        } ?? false
        if hasExpectedProxyNginx {
            return []
        }

        let listeners = listenerFields.map { "\($0.command)-\($0.pid)" }
        let joined = Array(listeners.prefix(5))
            .joined(separator: "_")
        return [.proxyPortInUse(port: port, listeners: joined)]
    }

    private func vmDiagnosticErrors(
        hostProxyHTTP: String,
        guestHTTP: String,
        guestRuntimeStateFresh: Bool
    ) -> [RuntimeVMError] {
        guard !isSuccessfulHTTPStatus(hostProxyHTTP)
            || !isSuccessfulHTTPStatus(guestHTTP)
            || !guestRuntimeStateFresh else {
            return []
        }
        let launchdErrorLog = readRuntimeLog("launchd.err.log")
        let launchdOutputLog = readRuntimeLog("launchd.out.log")
        var errors: [RuntimeVMError] = []
        if launchdErrorLog.localizedCaseInsensitiveContains("storage device attachment is invalid") {
            errors.append(.diskAttachmentInvalid)
        }
        if launchdErrorLog.localizedCaseInsensitiveContains("failed to start VM") {
            errors.append(.launchFailed("virtualization"))
        }
        if launchdErrorLog.localizedCaseInsensitiveContains("not enough memory")
            || launchdErrorLog.localizedCaseInsensitiveContains("insufficient memory") {
            errors.append(.hostResourceUnavailable("memory"))
        }
        if launchdOutputLog.localizedCaseInsensitiveContains("EXT4-fs error")
            || launchdOutputLog.localizedCaseInsensitiveContains("Filesystem error recorded")
            || launchdOutputLog.localizedCaseInsensitiveContains("mounting fs with errors") {
            errors.append(.guestFilesystemError)
        }
        if launchdOutputLog.localizedCaseInsensitiveContains("Remounting filesystem read-only") {
            errors.append(.guestFilesystemReadOnly)
        }
        if launchdOutputLog.localizedCaseInsensitiveContains("Input/output error") {
            errors.append(.guestDiskIO)
        }
        return errors
    }

    private func readRuntimeLog(_ fileName: String) -> String {
        let content = (try? fileStore.readUTF8Text(installedPaths.centralRuntimeLogsDirectory.appendingPathComponent(fileName))) ?? ""
        return String(content.suffix(256 * 1024))
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func readInstalledProxyNginxPID() -> String? {
        readTrimmed(installedPaths.proxyNginxPID)
    }

    private func containerObservation(proxyPort: Int, guestState: GuestRuntimeStateDocument?) -> RuntimeContainerObservation {
        let auditProxyStatus = auditProxyStatus(port: proxyPort)
        let containerLogsBytes = try? fileStore.fileSize(installedPaths.containerLogs)
        return RuntimeContainerObservation(
            auditProxyHTTP: auditProxyStatus.httpStatus,
            auditProxyStatus: auditProxyStatus.document,
            runtimeStateUpdatedAt: guestState?.updatedAt,
            runtimeStateFileUpdatedAt: fileModifiedAt(installedPaths.runtimeState),
            containerLogsPresent: fileStore.fileExists(installedPaths.containerLogs),
            containerLogsBytes: containerLogsBytes,
            containerLogsUpdatedAt: fileModifiedAt(installedPaths.containerLogs),
            composeServices: guestState?.containerServices ?? []
        )
    }

    private func fileModifiedAt(_ url: URL) -> String? {
        guard let date = try? fileStore.modificationDate(url) else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }

    private func auditProxyStatus(port: Int) -> (httpStatus: String, document: RuntimeAuditProxyStatusDocument?) {
        let result = commandRunner.run(
            Constants.Commands.curl,
            arguments: ["-fsS", "--max-time", "5", Constants.Runtime.auditProxyStatusURL(port: port)]
        )
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let document = try? JSONDecoder().decode(RuntimeAuditProxyStatusDocument.self, from: data) else {
            return ("failed", nil)
        }
        return ("200", document)
    }
}
