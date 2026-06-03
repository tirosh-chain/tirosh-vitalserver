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
    private let now: @Sendable () -> Date

    init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestGateway: RuntimeGuestGateway,
        now: @escaping @Sendable () -> Date = Date.init
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
        let guestRuntimeState = guestRuntimeStateObservationReader().read()
        let vmLifecycle = vmLifecycleObservation()
        let guestRuntimeStateInput = guestRuntimeStateInput(guestRuntimeState)
        let proxyPortRead = installedProxyPortRead()
        let proxyPort = proxyPortRead.port
        let hostProxyHTTP = httpProber.statusCode(url: Constants.Runtime.proxyHealthURL(port: proxyPort))
        let redisUIHTTP = httpProber.statusCode(url: Constants.Runtime.redisUIHealthURL(port: proxyPort))
        let swaggerUIHTTP = httpProber.statusCode(url: Constants.Runtime.swaggerUIHealthURL(port: proxyPort))
        let containerObservation = containerObservation(proxyPort: proxyPort, guestRuntimeState: guestRuntimeState)
        let vitalDBObservation = vitalDBObservation(guestRuntimeState)

        return RuntimeHealthEvaluator.evaluate(RuntimeHealthInput(
            vmExecutable: fileStore.isExecutableFile(atPath: Constants.InstallPaths.vmBin),
            proxyExecutable: fileStore.isExecutableFile(atPath: Constants.InstallPaths.proxyRun),
            rootfsBase: fileState(url: rootfsBase),
            vmDisk: fileState(url: vmDisk),
            vmService: launchdState(.vm),
            proxyService: launchdState(.proxy),
            watchdogService: launchdState(.watchdog),
            vmLifecycle: vmLifecycle.document,
            guestRuntimeState: guestRuntimeStateInput.state,
            proxyPort: proxyPort,
            hostProxyHTTP: hostProxyHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            containerObservation: .loaded(containerObservation),
            vitalDBObservation: vitalDBObservation,
            reportedVMErrors: [],
            configurationFailureReasons: proxyPortRead.failureReasons
                + guestRuntimeState.failureReasons
                + vmLifecycle.failureReasons
                + guestRuntimeStateInput.failureReasons,
            proxyPortFailureReasons: proxyPortFailureReasons(port: proxyPort),
            guestBootstrapAssessment: guestBootstrapAssessment(guestState: guestRuntimeState.loadedState)
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

    private func guestRuntimeStateObservationReader() -> RuntimeGuestRuntimeStateObservationReader {
        RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: fileStore,
            runtimeStateURL: installedPaths.runtimeState,
            staleAfterSeconds: Constants.Runtime.runtimeStateStaleAfterSeconds,
            now: now
        )
    }

    private func vmLifecycleObservation() -> RuntimeVMLifecycleObservation {
        switch RuntimeVMLifecycleStore(
            url: installedPaths.vmLifecycle,
            fileStore: fileStore,
            now: now
        ).load() {
        case .missing:
            return RuntimeVMLifecycleObservation(document: nil, failureReasons: [])
        case .failed:
            return RuntimeVMLifecycleObservation(document: nil, failureReasons: [.vmLifecycleDocumentInvalid])
        case .loaded(let document):
            guard let deadlineAt = document.deadlineAt else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [])
            }
            guard let deadline = ISO8601DateFormatter().date(from: deadlineAt) else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [.vmLifecycleDocumentInvalid])
            }
            guard now() <= deadline || !(document.state == .starting || document.state == .bootstrapping) else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [.vmLifecycleDocumentStale])
            }
            return RuntimeVMLifecycleObservation(document: document, failureReasons: [])
        }
    }

    private func guestRuntimeStateInput(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeGuestRuntimeStateInputReadResult {
        if let guestState = observation.freshState {
            let guestHTTP = guestHTTPStatus(guestState)
            return RuntimeGuestRuntimeStateInputReadResult(
                state: .fresh(vmIP: nonEmpty(guestState.vmIP), guestHTTP: guestHTTP.status),
                failureReasons: guestHTTP.failureReasons
            )
        }
        if observation.failureReasons.contains(.guestRuntimeStateInvalid) {
            return RuntimeGuestRuntimeStateInputReadResult(state: .invalid, failureReasons: [])
        }
        if observation.loadedState != nil {
            return RuntimeGuestRuntimeStateInputReadResult(state: .stale, failureReasons: [])
        }
        return RuntimeGuestRuntimeStateInputReadResult(state: .missing, failureReasons: [])
    }

    private func guestHTTPStatus(_ guestState: GuestRuntimeStateDocument) -> RuntimeGuestHTTPReadResult {
        guard let rawValue = nonEmpty(guestState.guestHTTP) else {
            return RuntimeGuestHTTPReadResult(
                status: .missing,
                failureReasons: [.guestRuntimeStateInvalid]
            )
        }
        if isSuccessfulHTTPStatus(rawValue)
            || rawValue == RuntimeHTTPStatusText.bootstrapPending
            || rawValue == RuntimeHTTPStatusText.missingVMIP {
            return RuntimeGuestHTTPReadResult(status: .reportedStatus(rawValue), failureReasons: [])
        }
        if Int(rawValue) != nil {
            return RuntimeGuestHTTPReadResult(status: .reportedStatus(rawValue), failureReasons: [])
        }
        return RuntimeGuestHTTPReadResult(status: .probeFailed(rawValue), failureReasons: [])
    }

    private func guestBootstrapAssessment(guestState: GuestRuntimeStateDocument?) -> GuestBootstrapAssessment {
        switch guestGateway.loadBootstrapResultDocument() {
        case .missing:
            return .missing
        case .failed(let message):
            return .unavailable(message)
        case .loaded(let bootstrapResult):
            guard bootstrapResultBelongsToCurrentBoot(bootstrapResult, guestState: guestState) else {
                return .notCurrentBoot
            }
            return GuestBootstrapEvaluator.assess(bootstrapResult)
        }
    }

    private func bootstrapResultBelongsToCurrentBoot(
        _ bootstrapResult: GuestBootstrapResultDocument,
        guestState: GuestRuntimeStateDocument?
    ) -> Bool {
        guard let bootstrapBootID = nonEmpty(bootstrapResult.bootID) else {
            return false
        }
        guard let guestBootID = nonEmpty(guestState?.bootID) else {
            return isFreshBootstrapResult(bootstrapResult)
        }
        return bootstrapBootID == guestBootID
    }

    private func isFreshBootstrapResult(_ bootstrapResult: GuestBootstrapResultDocument) -> Bool {
        guard let updatedAt = bootstrapResult.updatedAt,
              let updatedAtDate = ISO8601DateFormatter().date(from: updatedAt)
        else {
            return false
        }
        return now().timeIntervalSince(updatedAtDate) <= Constants.Runtime.watchdogManagedOperationGraceSeconds
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
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
        case .missing, .empty:
            return [.hostProxyListenerMismatch(port: port, listeners: joined)]
        case .readFailed:
            return [
                .hostProxyConfigInvalid,
                .hostProxyListenerMismatch(port: port, listeners: joined),
            ]
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    func readInstalledProxyNginxPID() -> RuntimeProxyNginxPIDReadResult {
        let url = installedPaths.proxyNginxPID
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let value = try fileStore.readUTF8Text(url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return .empty
            }
            return .loaded(value)
        } catch {
            return .readFailed(String(describing: error))
        }
    }

    private func containerObservation(
        proxyPort: Int,
        guestRuntimeState: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeContainerObservation {
        let auditProxyStatus = auditProxyStatus(port: proxyPort)
        let containerLogsMetadata = containerLogsMetadata()
        let runtimeStateFileModifiedAt = runtimeStateFileModifiedAt(guestRuntimeState)
        let composeServices = composeServices(guestRuntimeState)
        return RuntimeContainerObservation(
            auditProxyHTTP: auditProxyStatus.httpStatus,
            auditProxyStatus: auditProxyStatus.document,
            auditProxyStatusReadError: auditProxyStatus.readError,
            runtimeStateUpdatedAt: guestRuntimeState.freshState?.updatedAt,
            runtimeStateFileUpdatedAt: runtimeStateFileModifiedAt.updatedAt,
            runtimeStateFileMetadataError: runtimeStateFileModifiedAt.readError,
            containerLogsPresent: containerLogsMetadata.present,
            containerLogsBytes: containerLogsMetadata.bytes,
            containerLogsUpdatedAt: containerLogsMetadata.updatedAt,
            containerLogsMetadataError: containerLogsMetadata.error,
            composeServices: composeServices.services,
            composeServicesReadError: composeServices.readError
        )
    }

    private func containerLogsMetadata() -> RuntimeContainerLogsMetadata {
        let url = installedPaths.containerLogs
        guard fileStore.fileExists(url) else {
            return RuntimeContainerLogsMetadata(present: false, bytes: nil, updatedAt: nil, error: nil)
        }

        var errorTokens: [String] = []
        let bytes: UInt64?
        do {
            bytes = try fileStore.fileSize(url)
        } catch {
            bytes = nil
            errorTokens.append("size-read-failed")
        }

        let updatedAt: String?
        do {
            updatedAt = ISO8601DateFormatter().string(from: try fileStore.modificationDate(url))
        } catch {
            updatedAt = nil
            errorTokens.append("mtime-read-failed")
        }

        return RuntimeContainerLogsMetadata(
            present: true,
            bytes: bytes,
            updatedAt: updatedAt,
            error: errorTokens.isEmpty ? nil : errorTokens.joined(separator: ",")
        )
    }

    private func fileModifiedAt(_ url: URL) -> RuntimeFileModifiedAtReadResult {
        do {
            return RuntimeFileModifiedAtReadResult(
                updatedAt: ISO8601DateFormatter().string(from: try fileStore.modificationDate(url)),
                readError: nil
            )
        } catch {
            return RuntimeFileModifiedAtReadResult(
                updatedAt: nil,
                readError: "mtime-read-failed"
            )
        }
    }

    private func runtimeStateFileModifiedAt(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeFileModifiedAtReadResult {
        guard observation.isPresent else {
            return RuntimeFileModifiedAtReadResult(updatedAt: nil, readError: nil)
        }
        return fileModifiedAt(installedPaths.runtimeState)
    }

    private func composeServices(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeComposeServicesReadResult {
        if let guestState = observation.freshState {
            guard let services = guestState.containerServices else {
                return RuntimeComposeServicesReadResult(
                    services: [],
                    readError: "container-services-missing"
                )
            }
            return RuntimeComposeServicesReadResult(
                services: services,
                readError: nil
            )
        }
        if observation.failureReasons.contains(.guestRuntimeStateInvalid) {
            return RuntimeComposeServicesReadResult(
                services: [],
                readError: "guest-runtime-state-invalid"
            )
        }
        if observation.loadedState != nil {
            return RuntimeComposeServicesReadResult(
                services: [],
                readError: "guest-runtime-state-stale"
            )
        }
        return RuntimeComposeServicesReadResult(
            services: [],
            readError: "guest-runtime-state-missing"
        )
    }

    private func vitalDBObservation(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeObservationInput<VitalDBObservationDocument> {
        guard let guestState = observation.freshState else {
            return .notReported
        }
        guard let vitalDBObservation = guestState.vitalDBObservation else {
            return .missing
        }
        return .loaded(vitalDBObservation)
    }

    private func auditProxyStatus(port: Int) -> RuntimeAuditProxyStatusReadResult {
        let result = commandRunner.run(
            Constants.Commands.curl,
            arguments: ["-fsS", "--max-time", "5", Constants.Runtime.auditProxyStatusURL(port: port)]
        )
        guard result.exitCode == 0 else {
            return RuntimeAuditProxyStatusReadResult(
                httpStatus: "failed",
                document: nil,
                readError: "command-failed-\(result.exitCode)"
            )
        }
        do {
            let document = try JSONDecoder().decode(
                RuntimeAuditProxyStatusDocument.self,
                from: Data(result.stdout.utf8)
            )
            return RuntimeAuditProxyStatusReadResult(
                httpStatus: "200",
                document: document,
                readError: nil
            )
        } catch {
            return RuntimeAuditProxyStatusReadResult(
                httpStatus: RuntimeHTTPStatusText.invalidResponse,
                document: nil,
                readError: "decode-failed"
            )
        }
    }
}

private struct RuntimeProxyPortReadResult {
    let port: Int
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeGuestHTTPReadResult {
    let status: RuntimeGuestHTTPStatusInput
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeGuestRuntimeStateInputReadResult {
    let state: RuntimeGuestRuntimeStateInput
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeAuditProxyStatusReadResult {
    let httpStatus: String
    let document: RuntimeAuditProxyStatusDocument?
    let readError: String?
}

private struct RuntimeVMLifecycleObservation {
    let document: RuntimeVMLifecycleDocument?
    let failureReasons: [RuntimeFailureReason]
}

private struct RuntimeFileModifiedAtReadResult {
    let updatedAt: String?
    let readError: String?
}

private struct RuntimeComposeServicesReadResult {
    let services: [RuntimeContainerServiceObservation]
    let readError: String?
}

private struct RuntimeContainerLogsMetadata {
    let present: Bool
    let bytes: UInt64?
    let updatedAt: String?
    let error: String?
}

enum RuntimeProxyNginxPIDReadResult: Equatable {
    case loaded(String)
    case missing
    case empty
    case readFailed(String)

    var loadedPID: String? {
        if case .loaded(let value) = self {
            return value
        }
        return nil
    }
}
