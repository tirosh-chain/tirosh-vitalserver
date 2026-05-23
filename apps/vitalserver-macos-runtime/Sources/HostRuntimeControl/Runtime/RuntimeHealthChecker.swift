import Foundation
import RuntimeCore
import RuntimeContracts
import HostRuntimeInfrastructure

struct RuntimeHealthChecker {
    private let installedPaths: InstalledRuntimePaths
    private let fileStore: RuntimeFileStore
    private let serviceManager: RuntimeServiceManager
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let guestGateway: RuntimeGuestGateway

    init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestGateway: RuntimeGuestGateway
    ) {
        self.installedPaths = installedPaths
        self.fileStore = fileStore
        self.serviceManager = serviceManager
        self.commandRunner = commandRunner
        self.httpProber = httpProber
        self.guestGateway = guestGateway
    }

    private var rootfsBase: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
    }

    private var vmDisk: URL {
        installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
    }

    func snapshot() -> RuntimeHealthSnapshot {
        let guestState = guestRuntimeState()
        let vmIP = guestState?.vmIP ?? readTrimmed(installedPaths.vmIPFile)
        let proxyPort = installedProxyPort()
        let hostProxyHTTP = httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: proxyPort))
        let redisUIHTTP = httpProber.statusCode(url: Constants.Runtime.redisUIHealthURL(port: proxyPort))
        let swaggerUIHTTP = httpProber.statusCode(url: Constants.Runtime.swaggerUIHealthURL(port: proxyPort))

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
            guestHTTP: guestHTTPStatus(guestState: guestState, vmIP: vmIP),
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
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

    private func readInstalledProxyNginxPID() -> String? {
        readTrimmed(installedPaths.proxyNginxPID)
    }
}
