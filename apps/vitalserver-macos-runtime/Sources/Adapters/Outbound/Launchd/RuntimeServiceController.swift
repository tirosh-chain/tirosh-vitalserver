import Application
import Contracts
import Domain
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
            if try stopIfLoaded(service) {
                log("waiting for \(displayName(service)) service to stop label=\(service.label)")
                try waitUntilStopped(service)
                log("stopped \(displayName(service)) service label=\(service.label)")
            }
        }
    }

    public func disableRuntimeServicesForUninstall() throws {
        log("disabling runtime services before uninstall")
        for service in RuntimeManagedService.stopOrder {
            try setEnabledOrThrow(service, enabled: false)
        }
    }

    public func stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID: pid_t) throws {
        log("stopping runtime services after guest poweroff request")
        for service in [RuntimeManagedService.watchdog, .proxy] {
            if try stopIfLoaded(service) {
                log("waiting for \(displayName(service)) service to stop label=\(service.label)")
                try waitUntilStopped(service)
                log("stopped \(displayName(service)) service label=\(service.label)")
            }
        }

        try waitForVMProcessExitAfterGuestPoweroff(expectedVMProcessID)
        if try stopIfLoaded(.guestLogSync) {
            log("waiting for \(displayName(.guestLogSync)) service to stop label=\(RuntimeManagedService.guestLogSync.label)")
            try waitUntilStopped(.guestLogSync)
            log("stopped \(displayName(.guestLogSync)) service label=\(RuntimeManagedService.guestLogSync.label)")
        }
        if try unloadIfLoaded(.vm) {
            log("waiting for \(displayName(.vm)) service to stop label=\(RuntimeManagedService.vm.label)")
            try waitUntilStopped(.vm)
            log("stopped \(displayName(.vm)) service label=\(RuntimeManagedService.vm.label)")
        }
        if try stopIfLoaded(.sleepPrevention) {
            log("waiting for \(displayName(.sleepPrevention)) service to stop label=\(RuntimeManagedService.sleepPrevention.label)")
            try waitUntilStopped(.sleepPrevention)
            log("stopped \(displayName(.sleepPrevention)) service label=\(RuntimeManagedService.sleepPrevention.label)")
        }
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
        if restartProxy {
            try startLaunchdService(.proxy)
        }
        if restartWatchdog {
            try startLaunchdService(.watchdog)
        }
    }

    public func startLaunchdService(_ service: RuntimeManagedService) throws {
        let plist = launchDaemonPlist(service)
        log("starting \(displayName(service)) service label=\(service.label)")
        try setLaunchdServiceEnabled(service, enabled: true)
        log("launchd bootstrap label=\(service.label) plist=\(plist)")
        serviceManager.start(service: service, plist: plist)
        guard try isLoaded(service) else {
            let message = "launchd service failed to load label=\(service.label) plist=\(plist)"
            log(message)
            throw RuntimeServiceControllerError.runtimeOperationFailed(message)
        }
        log("launchd service loaded label=\(service.label)")
    }

    public func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        log("launchd restart label=\(service.label)")
        serviceManager.restart(service: service)
        if try !isLoaded(service) {
            log("launchd service not loaded after restart; starting label=\(service.label)")
            try startLaunchdService(service)
        }
    }

    public func restartVMRuntimeServices() throws {
        log("safely restarting VM runtime services")
        if try stopIfLoaded(.guestLogSync) {
            log("waiting for \(displayName(.guestLogSync)) service to stop label=\(RuntimeManagedService.guestLogSync.label)")
            try waitUntilStopped(.guestLogSync)
            log("stopped \(displayName(.guestLogSync)) service label=\(RuntimeManagedService.guestLogSync.label)")
        }
        if try stopIfLoaded(.vm) {
            log("waiting for \(displayName(.vm)) service to stop label=\(RuntimeManagedService.vm.label)")
            try waitUntilStopped(.vm)
            log("stopped \(displayName(.vm)) service label=\(RuntimeManagedService.vm.label)")
        }
        try startLaunchdService(.vm)
        try startLaunchdService(.guestLogSync)
    }

    public func stopLaunchdService(_ service: RuntimeManagedService) {
        do {
            _ = try stopIfLoaded(service)
        } catch {
            log("failed to stop \(displayName(service)) service label=\(service.label) error=\(error)")
        }
    }

    public func unloadRuntimeServicesAfterForcedVMStop() {
        for service in RuntimeManagedService.stopOrder {
            do {
                if try unloadIfLoaded(service) {
                    log("waiting for \(displayName(service)) service to unload after forced VM stop label=\(service.label)")
                    try waitUntilStopped(service)
                    log("unloaded \(displayName(service)) service after forced VM stop label=\(service.label)")
                }
            } catch {
                log("failed to unload \(displayName(service)) service after forced VM stop label=\(service.label) error=\(error)")
            }
        }
    }

    public func setStartOnBoot(_ enabled: Bool) throws {
        for service in RuntimeManagedService.startOrder {
            try setEnabledOrThrow(service, enabled: enabled)
        }
    }

    private func stopIfLoaded(_ service: RuntimeManagedService) throws -> Bool {
        if try isLoaded(service) {
            try prepareForStop(service)
            return try unloadIfLoaded(service)
        }
        return false
    }

    private func unloadIfLoaded(_ service: RuntimeManagedService) throws -> Bool {
        if try isLoaded(service) {
            serviceManager.stop(service: service)
            return true
        }
        return false
    }

    private func setLaunchdServiceEnabled(_ service: RuntimeManagedService, enabled: Bool) throws {
        try setEnabledOrThrow(service, enabled: enabled)
    }

    private func setEnabledOrThrow(_ service: RuntimeManagedService, enabled: Bool) throws {
        let result = serviceManager.setEnabled(service: service, enabled: enabled)
        guard result.exitCode == 0 else {
            let action = enabled ? "enable" : "disable"
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("command stderr executable=\(launchctlPath) stderr=\(stderr)")
            }
            log("command failed executable=\(launchctlPath) exitCode=\(result.exitCode)")
            throw RuntimeServiceControllerError.missingArgument(
                "command failed: \(launchctlPath) \(action) system/\(service.label)"
            )
        }
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

    private func serviceStateFailure(
        _ service: RuntimeManagedService,
        kind: String,
        reason: String
    ) -> RuntimeServiceControllerError {
        let message = "launchd service state \(kind) label=\(service.label) reason=\(reason)"
        log(message)
        return RuntimeServiceControllerError.runtimeOperationFailed(message)
    }

    private func displayName(_ service: RuntimeManagedService) -> String {
        switch service {
        case .vm:
            "VM"
        case .proxy:
            "proxy"
        case .guestLogSync:
            "guest log sync"
        case .sleepPrevention:
            "sleep prevention"
        case .watchdog:
            "watchdog"
        }
    }
}
