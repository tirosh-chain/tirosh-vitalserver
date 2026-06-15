import Application
import Contracts
import Errors

struct RuntimeLaunchdServiceOperator {
    private let serviceManager: RuntimeServiceManager
    private let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    private let prepareForStop: (RuntimeManagedService) throws -> Void
    private let launchDaemonPlist: (RuntimeManagedService) -> String
    private let launchctlPath: String
    private let log: (String) -> Void
    private var failureReporter: RuntimeLaunchdCommandFailureReporter {
        RuntimeLaunchdCommandFailureReporter(launchctlPath: launchctlPath, log: log)
    }

    init(
        serviceManager: RuntimeServiceManager,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        prepareForStop: @escaping (RuntimeManagedService) throws -> Void,
        launchDaemonPlist: @escaping (RuntimeManagedService) -> String,
        launchctlPath: String,
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.serviceState = serviceState
        self.prepareForStop = prepareForStop
        self.launchDaemonPlist = launchDaemonPlist
        self.launchctlPath = launchctlPath
        self.log = log
    }

    func stopIfLoaded(_ service: RuntimeManagedService) throws -> Bool {
        if try isLoaded(service) {
            try prepareForStop(service)
            return try unloadIfLoaded(service)
        }
        return false
    }

    func unloadIfLoaded(_ service: RuntimeManagedService) throws -> Bool {
        if try isLoaded(service) {
            try requireLaunchdCommandSuccess(
                serviceManager.stop(service: service),
                service: service,
                action: "bootout",
                arguments: ["bootout", "system/\(service.label)"]
            )
            return true
        }
        return false
    }

    func startLaunchdService(_ service: RuntimeManagedService) throws {
        let plist = launchDaemonPlist(service)
        log("starting \(service.runtimeServiceDisplayName) service label=\(service.label)")
        try setEnabledOrThrow(service, enabled: true)
        log("launchd bootstrap label=\(service.label) plist=\(plist)")
        try requireLaunchdCommandSuccess(
            serviceManager.start(service: service, plist: plist),
            service: service,
            action: "bootstrap",
            arguments: ["bootstrap", "system", plist]
        )
        guard try isLoaded(service) else {
            let message = "launchd service failed to load label=\(service.label) plist=\(plist)"
            log(message)
            throw RuntimeServiceControllerError.runtimeOperationFailed(message)
        }
        log("launchd service loaded label=\(service.label)")
    }

    func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        log("launchd restart label=\(service.label)")
        let restartResult = serviceManager.restart(service: service)
        if restartResult.exitCode != 0 {
            logLaunchdCommandFailure(
                restartResult,
                service: service,
                action: "kickstart",
                arguments: ["kickstart", "-k", "system/\(service.label)"]
            )
        }
        if try !isLoaded(service) {
            log("launchd service not loaded after restart; starting label=\(service.label)")
            try startLaunchdService(service)
        } else if restartResult.exitCode != 0 {
            throw launchdCommandFailure(
                restartResult,
                service: service,
                action: "kickstart",
                arguments: ["kickstart", "-k", "system/\(service.label)"]
            )
        }
    }

    func setEnabledOrThrow(_ service: RuntimeManagedService, enabled: Bool) throws {
        let action = enabled ? "enable" : "disable"
        try requireLaunchdCommandSuccess(
            serviceManager.setEnabled(service: service, enabled: enabled),
            service: service,
            action: action,
            arguments: [action, "system/\(service.label)"]
        )
    }

    private func isLoaded(_ service: RuntimeManagedService) throws -> Bool {
        let state = serviceState(service)
        switch state {
        case .loaded:
            return true
        case .notLoaded:
            return false
        case .readFailed(let reason):
            throw serviceStateFailure(service, kind: "read failed", reason: reason)
        case .permissionDenied(let reason):
            throw serviceStateFailure(service, kind: "permission denied", reason: reason)
        case .unknown(let value):
            throw serviceStateFailure(service, kind: "unknown", reason: value)
        }
    }

    private func requireLaunchdCommandSuccess(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) throws {
        try failureReporter.requireSuccess(result, service: service, action: action, arguments: arguments)
    }

    private func launchdCommandFailure(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) -> RuntimeServiceControllerError {
        failureReporter.failure(result, service: service, action: action, arguments: arguments)
    }

    private func logLaunchdCommandFailure(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) {
        failureReporter.logFailure(result, service: service, action: action, arguments: arguments)
    }

    private func serviceStateFailure(
        _ service: RuntimeManagedService,
        kind: String,
        reason: String
    ) -> RuntimeServiceControllerError {
        let message = "launchd service state \(kind) label=\(service.label) reason=\(reason)"
        log(message)
        return RuntimeServiceControllerError.runtimeOperationFailed(message)
    }
}
