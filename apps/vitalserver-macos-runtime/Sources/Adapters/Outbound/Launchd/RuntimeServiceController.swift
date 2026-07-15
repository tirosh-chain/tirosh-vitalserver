import Application
import Contracts
import Foundation
import Errors

public struct RuntimeServiceController {
    private let serviceManager: RuntimeServiceManager
    private let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    private let prepareForStop: (RuntimeManagedService) throws -> Void
    private let waitUntilStopped: (RuntimeManagedService) throws -> Void
    private let waitForVMProcessExitAfterGuestPoweroff: (pid_t) throws -> Void
    private let launchDaemonPlist: (RuntimeManagedService) -> String
    private let launchctlPath: String
    private let log: (String) -> Void
    private var serviceOperator: RuntimeLaunchdServiceOperator {
        RuntimeLaunchdServiceOperator(
            serviceManager: serviceManager,
            serviceState: serviceState,
            prepareForStop: prepareForStop,
            launchDaemonPlist: launchDaemonPlist,
            launchctlPath: launchctlPath,
            log: log
        )
    }

    public init(
        serviceManager: RuntimeServiceManager,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        prepareForStop: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitUntilStopped: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitForVMProcessExitAfterGuestPoweroff: @escaping (pid_t) throws -> Void = { _ in
            throw RuntimeServiceControllerError.runtimeOperationFailed("VM process exit wait is not configured")
        },
        launchDaemonPlist: @escaping (RuntimeManagedService) -> String,
        launchctlPath: String,
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.serviceState = serviceState
        self.prepareForStop = prepareForStop
        self.waitUntilStopped = waitUntilStopped
        self.waitForVMProcessExitAfterGuestPoweroff = waitForVMProcessExitAfterGuestPoweroff
        self.launchDaemonPlist = launchDaemonPlist
        self.launchctlPath = launchctlPath
        self.log = log
    }

    public func stopRuntimeServices() throws {
        log("stopping runtime services")
        for service in RuntimeManagedService.stopOrder {
            try stopAndWaitIfLoaded(service)
        }
    }

    public func stopRuntimeServicesForUninstall() throws {
        log("stopping runtime services for uninstall")
        for service in RuntimeManagedService.uninstallOrder {
            try stopAndWaitIfLoaded(service)
        }
    }

    public func disableRuntimeServicesForUninstall() throws {
        log("disabling runtime services before uninstall")
        for service in RuntimeManagedService.uninstallOrder {
            try serviceOperator.setEnabledOrThrow(service, enabled: false)
        }
    }

    public func clearDisabledOverridesAfterUninstall() throws {
        log("clearing launchd disabled overrides after uninstall")
        for service in RuntimeManagedService.uninstallOrder {
            try serviceOperator.setEnabledOrThrow(service, enabled: true)
        }
    }

    public func stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: pid_t) throws {
        log("stopping runtime services after guest poweroff request")
        for service in [RuntimeManagedService.watchdog, .proxy] {
            try stopAndWaitIfLoaded(service)
        }

        _ = try unloadAndWaitIfLoaded(.vm)
        try waitForVMProcessExitAfterGuestPoweroff(expectedVMProcessID)
        try stopAndWaitIfLoaded(.guestLogSync)
        try stopAndWaitIfLoaded(.sleepPrevention)
    }

    public func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
            restartGuestLogSync: policy.restartGuestLogSync,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    public func startRuntimeServices(
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) throws {
        if restartVM {
            try startLaunchdService(.vm)
        }
        if restartGuestLogSync {
            try startLaunchdService(.guestLogSync)
        }
        if restartWatchdog {
            try startLaunchdService(.watchdog)
        }
        if restartProxy {
            try startLaunchdService(.proxy)
        }
    }

    public func startLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceOperator.startLaunchdService(service)
    }

    public func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        try serviceOperator.restartOrStartLaunchdService(service)
    }

    public func restartVMRuntimeServices() throws {
        log("safely restarting VM runtime services")
        try stopForVMRuntimeRestart(.guestLogSync)
        try stopForVMRuntimeRestart(.vm)
        try startLaunchdService(.vm)
        try startLaunchdService(.guestLogSync)
    }

    public func stopLaunchdService(_ service: RuntimeManagedService) throws {
        _ = try serviceOperator.stopIfLoaded(service)
    }

    public func unloadRuntimeServicesAfterForcedVMStop() {
        for service in RuntimeManagedService.stopOrder {
            do {
                try unloadAfterForcedVMStopIfLoaded(service)
            } catch {
                log("failed to unload \(service.runtimeServiceDisplayName) service after forced VM stop label=\(service.label) error=\(error)")
            }
        }
    }

    public func unloadRuntimeServicesForUninstallAfterForcedVMStop() {
        for service in RuntimeManagedService.uninstallOrder {
            do {
                try unloadAfterForcedVMStopIfLoaded(service)
            } catch {
                log("failed to unload \(service.runtimeServiceDisplayName) service for uninstall after forced VM stop label=\(service.label) error=\(error)")
            }
        }
    }

    public func setStartOnBoot(_ enabled: Bool) throws {
        for service in RuntimeManagedService.startOrder {
            try serviceOperator.setEnabledOrThrow(service, enabled: enabled)
        }
    }

    private func stopAndWaitIfLoaded(_ service: RuntimeManagedService) throws {
        let stopped: Bool
        if service == .vm {
            // Boot out the KeepAlive job before its process receives SIGTERM. Signalling the
            // process first allows launchd to replace it and rewrites the pid file mid-stop.
            stopped = try serviceOperator.unloadIfLoaded(service)
        } else {
            stopped = try serviceOperator.stopIfLoaded(service)
        }
        if stopped {
            try waitForStoppedService(service)
        }
    }

    private func stopForVMRuntimeRestart(_ service: RuntimeManagedService) throws {
        do {
            try stopAndWaitIfLoaded(service)
        } catch {
            throw RuntimeVMRuntimeRestartError.gracefulStopFailed(
                service: service,
                message: String(describing: error)
            )
        }
    }

    private func unloadAndWaitIfLoaded(_ service: RuntimeManagedService) throws -> Bool {
        guard try serviceOperator.unloadIfLoaded(service) else {
            return false
        }
        try waitForStoppedService(service)
        return true
    }

    private func unloadAfterForcedVMStopIfLoaded(_ service: RuntimeManagedService) throws {
        if try serviceOperator.unloadIfLoaded(service) {
            log("waiting for \(service.runtimeServiceDisplayName) service to unload after forced VM stop label=\(service.label)")
            try waitUntilStopped(service)
            log("unloaded \(service.runtimeServiceDisplayName) service after forced VM stop label=\(service.label)")
        }
    }

    private func waitForStoppedService(_ service: RuntimeManagedService) throws {
        log("waiting for \(service.runtimeServiceDisplayName) service to stop label=\(service.label)")
        try waitUntilStopped(service)
        log("stopped \(service.runtimeServiceDisplayName) service label=\(service.label)")
    }
}
