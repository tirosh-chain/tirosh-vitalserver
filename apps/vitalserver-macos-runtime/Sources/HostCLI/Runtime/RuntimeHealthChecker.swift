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
        let guestRuntimeStateFreshness = guestRuntimeStateFreshness(loadedGuestState)
        let guestRuntimeStateFresh = guestRuntimeStateFreshness.isFresh
        let guestState = guestRuntimeStateFresh ? loadedGuestState : nil
        let vmIP = guestState?.vmIP
        let proxyPortRead = installedProxyPortRead()
        let proxyPort = proxyPortRead.port
        let hostProxyHTTP = httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: proxyPort))
        let redisUIHTTP = httpProber.statusCode(url: Constants.Runtime.redisUIHealthURL(port: proxyPort))
        let swaggerUIHTTP = httpProber.statusCode(url: Constants.Runtime.swaggerUIHealthURL(port: proxyPort))
        let containerObservation = containerObservation(proxyPort: proxyPort, guestState: guestState)
        let guestHTTPRead = guestHTTPStatus(guestState: guestState)

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
            guestHTTP: guestHTTPRead.status,
            guestRuntimeStatePresent: loadedGuestState != nil,
            guestRuntimeStateFresh: guestRuntimeStateFresh,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            containerObservation: containerObservation,
            vitalDBObservation: guestState?.vitalDBObservation,
            reportedVMErrors: [],
            configurationFailureReasons: proxyPortRead.failureReasons
                + guestRuntimeStateFreshness.failureReasons
                + guestHTTPRead.failureReasons,
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
        installedProxyPortRead().port
    }

    private func installedProxyPortRead() -> RuntimeProxyPortReadResult {
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
            return RuntimeProxyPortReadResult(
                port: InstallSettings.defaultProxyPort,
                failureReasons: [.hostProxyConfigInvalid]
            )
        }
        return RuntimeProxyPortReadResult(port: port, failureReasons: [])
    }

    func guestRuntimeState() -> GuestRuntimeStateDocument? {
        guestGateway.loadRuntimeState()
    }

    private func guestRuntimeStateFreshness(_ guestState: GuestRuntimeStateDocument?) -> RuntimeGuestStateFreshness {
        guard guestState != nil else {
            return RuntimeGuestStateFreshness(isFresh: true, failureReasons: [])
        }
        do {
            let modifiedAt = try fileStore.modificationDate(installedPaths.runtimeState)
            return RuntimeGuestStateFreshness(
                isFresh: now().timeIntervalSince(modifiedAt) <= Constants.Runtime.runtimeStateStaleAfterSeconds,
                failureReasons: []
            )
        } catch {
            return RuntimeGuestStateFreshness(isFresh: false, failureReasons: [.guestRuntimeStateInvalid])
        }
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

    private func guestHTTPStatus(guestState: GuestRuntimeStateDocument?) -> RuntimeGuestHTTPReadResult {
        if let guestHTTP = guestState?.guestHTTP, !guestHTTP.isEmpty {
            return RuntimeGuestHTTPReadResult(status: guestHTTP, failureReasons: [])
        }
        if guestState != nil {
            return RuntimeGuestHTTPReadResult(
                status: RuntimeHTTPStatusText.missingGuestHTTP,
                failureReasons: [.guestRuntimeStateInvalid]
            )
        }
        return RuntimeGuestHTTPReadResult(status: RuntimeHTTPStatusText.missingVMIP, failureReasons: [])
    }

    private func guestBootstrapFailureReason() -> RuntimeFailureReason? {
        if let bootstrapResult = guestGateway.loadBootstrapResult() {
            return GuestBootstrapEvaluator.failureReason(bootstrapResult)
        }
        return nil
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
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stdout.isEmpty && stderr.isEmpty {
                return []
            }
            return [.hostProxyListenerScanFailed(port: port, exitCode: Int(result.exitCode))]
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

        let listeners = listenerFields.map { "\($0.command)-\($0.pid)" }
        let joined = Array(listeners.prefix(5))
            .joined(separator: "_")
        switch expectedNginxPID {
        case .loaded(let expectedPID):
            let hasExpectedProxyNginx = listenerFields.contains { $0.command == "nginx" && $0.pid == expectedPID }
            if hasExpectedProxyNginx {
                return []
            }
            return [.proxyPortInUse(port: port, listeners: joined)]
        case .unavailable:
            return [.hostProxyListenerMismatch(port: port, listeners: joined)]
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func readInstalledProxyNginxPID() -> RuntimeProxyNginxPIDReadResult {
        guard let pid = readTrimmed(installedPaths.proxyNginxPID) else {
            return .unavailable
        }
        return .loaded(pid)
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
        guard result.exitCode == 0 else {
            return ("failed", nil)
        }
        guard let data = result.stdout.data(using: .utf8),
              let document = try? JSONDecoder().decode(RuntimeAuditProxyStatusDocument.self, from: data) else {
            return (RuntimeHTTPStatusText.invalidResponse, nil)
        }
        return ("200", document)
    }
}

private struct RuntimeProxyPortReadResult {
    let port: Int
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeGuestHTTPReadResult {
    let status: String
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeGuestStateFreshness {
    let isFresh: Bool
    let failureReasons: [RuntimeFailureReason]
}

private enum RuntimeProxyNginxPIDReadResult {
    case loaded(String)
    case unavailable
}
