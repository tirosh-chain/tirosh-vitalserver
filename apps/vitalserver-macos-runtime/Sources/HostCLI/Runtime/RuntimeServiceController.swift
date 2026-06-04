import Foundation
import Core
import Contracts

struct RuntimeServiceController {
    private let serviceManager: RuntimeServiceManager
    private let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    private let prepareForStop: (RuntimeManagedService) throws -> Void
    private let waitUntilStopped: (RuntimeManagedService) throws -> Void
    private let waitForVMProcessExitAfterGuestPoweroff: () throws -> Void
    private let log: (String) -> Void

    init(
        serviceManager: RuntimeServiceManager,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        prepareForStop: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitUntilStopped: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitForVMProcessExitAfterGuestPoweroff: @escaping () throws -> Void = {
            throw LauncherError.runtimeOperationFailed("VM process exit wait is not configured")
        },
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.serviceState = serviceState
        self.prepareForStop = prepareForStop
        self.waitUntilStopped = waitUntilStopped
        self.waitForVMProcessExitAfterGuestPoweroff = waitForVMProcessExitAfterGuestPoweroff
        self.log = log
    }

    func stopRuntimeServices() throws {
        log("stopping runtime services")
        for service in RuntimeManagedService.stopOrder {
            if try stopIfLoaded(service) {
                log("waiting for \(service.displayName) service to stop label=\(service.label)")
                try waitUntilStopped(service)
                log("stopped \(service.displayName) service label=\(service.label)")
            }
        }
    }

    func disableRuntimeServicesForUninstall() throws {
        log("disabling runtime services before uninstall")
        for service in RuntimeManagedService.stopOrder {
            let result = serviceManager.setEnabled(service: service, enabled: false)
            guard result.exitCode == 0 else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty {
                    log("command stderr executable=\(Constants.Commands.launchctl) stderr=\(stderr)")
                }
                log("command failed executable=\(Constants.Commands.launchctl) exitCode=\(result.exitCode)")
                throw LauncherError.missingArgument(
                    "command failed: \(Constants.Commands.launchctl) disable system/\(service.label)"
                )
            }
        }
    }

    func stopRuntimeServicesAfterGuestPoweroff() throws {
        log("stopping runtime services after guest poweroff request")
        for service in [RuntimeManagedService.watchdog, .proxy] {
            if try stopIfLoaded(service) {
                log("waiting for \(service.displayName) service to stop label=\(service.label)")
                try waitUntilStopped(service)
                log("stopped \(service.displayName) service label=\(service.label)")
            }
        }

        try waitForVMProcessExitAfterGuestPoweroff()
        if try stopIfLoaded(.guestLogSync) {
            log("waiting for \(RuntimeManagedService.guestLogSync.displayName) service to stop label=\(RuntimeManagedService.guestLogSync.label)")
            try waitUntilStopped(.guestLogSync)
            log("stopped \(RuntimeManagedService.guestLogSync.displayName) service label=\(RuntimeManagedService.guestLogSync.label)")
        }
        if try unloadIfLoaded(.vm) {
            log("waiting for \(RuntimeManagedService.vm.displayName) service to stop label=\(RuntimeManagedService.vm.label)")
            try waitUntilStopped(.vm)
            log("stopped \(RuntimeManagedService.vm.displayName) service label=\(RuntimeManagedService.vm.label)")
        }
        if try stopIfLoaded(.sleepPrevention) {
            log("waiting for \(RuntimeManagedService.sleepPrevention.displayName) service to stop label=\(RuntimeManagedService.sleepPrevention.label)")
            try waitUntilStopped(.sleepPrevention)
            log("stopped \(RuntimeManagedService.sleepPrevention.displayName) service label=\(RuntimeManagedService.sleepPrevention.label)")
        }
    }

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) throws {
        try startRuntimeServices(
            restartVM: policy.restartVM,
            restartGuestLogSync: policy.restartGuestLogSync,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    func startRuntimeServices(
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

    func startLaunchdService(_ service: RuntimeManagedService) throws {
        let plist = service.launchDaemonPlist
        log("starting \(service.displayName) service label=\(service.label)")
        try setLaunchdServiceEnabled(service, enabled: true)
        log("launchd bootstrap label=\(service.label) plist=\(plist)")
        serviceManager.start(service: service, plist: plist)
        guard try isLoaded(service) else {
            let message = "launchd service failed to load label=\(service.label) plist=\(plist)"
            log(message)
            throw LauncherError.runtimeOperationFailed(message)
        }
        log("launchd service loaded label=\(service.label)")
    }

    func restartOrStartLaunchdService(_ service: RuntimeManagedService) throws {
        log("launchd restart label=\(service.label)")
        serviceManager.restart(service: service)
        if try !isLoaded(service) {
            log("launchd service not loaded after restart; starting label=\(service.label)")
            try startLaunchdService(service)
        }
    }

    func restartVMRuntimeServices() throws {
        log("safely restarting VM runtime services")
        if try stopIfLoaded(.guestLogSync) {
            log("waiting for \(RuntimeManagedService.guestLogSync.displayName) service to stop label=\(RuntimeManagedService.guestLogSync.label)")
            try waitUntilStopped(.guestLogSync)
            log("stopped \(RuntimeManagedService.guestLogSync.displayName) service label=\(RuntimeManagedService.guestLogSync.label)")
        }
        if try stopIfLoaded(.vm) {
            log("waiting for \(RuntimeManagedService.vm.displayName) service to stop label=\(RuntimeManagedService.vm.label)")
            try waitUntilStopped(.vm)
            log("stopped \(RuntimeManagedService.vm.displayName) service label=\(RuntimeManagedService.vm.label)")
        }
        try startLaunchdService(.vm)
        try startLaunchdService(.guestLogSync)
    }

    func stopLaunchdService(_ service: RuntimeManagedService) {
        do {
            _ = try stopIfLoaded(service)
        } catch {
            log("failed to stop \(service.displayName) service label=\(service.label) error=\(error)")
        }
    }

    func unloadRuntimeServicesAfterForcedVMStop() {
        for service in RuntimeManagedService.stopOrder {
            do {
                if try unloadIfLoaded(service) {
                    log("waiting for \(service.displayName) service to unload after forced VM stop label=\(service.label)")
                    try waitUntilStopped(service)
                    log("unloaded \(service.displayName) service after forced VM stop label=\(service.label)")
                }
            } catch {
                log("failed to unload \(service.displayName) service after forced VM stop label=\(service.label) error=\(error)")
            }
        }
    }

    func setStartOnBoot(_ enabled: Bool) throws {
        for service in RuntimeManagedService.startOrder {
            let result = serviceManager.setEnabled(service: service, enabled: enabled)
            guard result.exitCode == 0 else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty {
                    log("command stderr executable=\(Constants.Commands.launchctl) stderr=\(stderr)")
                }
                log("command failed executable=\(Constants.Commands.launchctl) exitCode=\(result.exitCode)")
                throw LauncherError.missingArgument(
                    "command failed: \(Constants.Commands.launchctl) \(enabled ? "enable" : "disable") system/\(service.label)"
                )
            }
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
        let result = serviceManager.setEnabled(service: service, enabled: enabled)
        guard result.exitCode == 0 else {
            let action = enabled ? "enable" : "disable"
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("command stderr executable=\(Constants.Commands.launchctl) stderr=\(stderr)")
            }
            log("command failed executable=\(Constants.Commands.launchctl) exitCode=\(result.exitCode)")
            throw LauncherError.missingArgument(
                "command failed: \(Constants.Commands.launchctl) \(action) system/\(service.label)"
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
    ) -> LauncherError {
        let message = "launchd service state \(kind) label=\(service.label) reason=\(reason)"
        log(message)
        return LauncherError.runtimeOperationFailed(message)
    }
}
