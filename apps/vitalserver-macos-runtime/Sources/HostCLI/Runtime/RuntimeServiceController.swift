import Foundation
import Core
import Contracts

struct RuntimeServiceController {
    private let serviceManager: RuntimeServiceManager
    private let isLoaded: (RuntimeManagedService) -> Bool
    private let prepareForStop: (RuntimeManagedService) throws -> Void
    private let waitUntilStopped: (RuntimeManagedService) throws -> Void
    private let waitForVMProcessExitAfterGuestPoweroff: () throws -> Void
    private let log: (String) -> Void

    init(
        serviceManager: RuntimeServiceManager,
        isLoaded: @escaping (RuntimeManagedService) -> Bool,
        prepareForStop: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitUntilStopped: @escaping (RuntimeManagedService) throws -> Void = { _ in },
        waitForVMProcessExitAfterGuestPoweroff: @escaping () throws -> Void = {
            throw LauncherError.runtimeOperationFailed("VM process exit wait is not configured")
        },
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.isLoaded = isLoaded
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
        if unloadIfLoaded(.vm) {
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

    func startRuntimeServices(_ policy: RuntimeServiceRestartPolicy) {
        startRuntimeServices(
            restartVM: policy.restartVM,
            restartProxy: policy.restartProxy,
            restartWatchdog: policy.restartWatchdog
        )
    }

    func startRuntimeServices(
        restartVM: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) {
        if restartVM {
            startLaunchdService(.vm)
            startLaunchdService(.guestLogSync)
        }
        if restartProxy {
            startLaunchdService(.proxy)
        }
        if restartWatchdog {
            startLaunchdService(.watchdog)
        }
    }

    func startLaunchdService(_ service: RuntimeManagedService) {
        let plist = service.launchDaemonPlist
        log("starting \(service.displayName) service label=\(service.label)")
        log("launchd bootstrap label=\(service.label) plist=\(plist)")
        serviceManager.start(service: service, plist: plist)
    }

    func restartOrStartLaunchdService(_ service: RuntimeManagedService) {
        log("launchd restart label=\(service.label)")
        serviceManager.restart(service: service)
        if !isLoaded(service) {
            log("launchd service not loaded after restart; starting label=\(service.label)")
            startLaunchdService(service)
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
        startLaunchdService(.vm)
        startLaunchdService(.guestLogSync)
    }

    func stopLaunchdService(_ service: RuntimeManagedService) {
        do {
            _ = try stopIfLoaded(service)
        } catch {
            log("failed to stop \(service.displayName) service label=\(service.label) error=\(error)")
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
        if isLoaded(service) {
            try prepareForStop(service)
            return unloadIfLoaded(service)
        }
        return false
    }

    private func unloadIfLoaded(_ service: RuntimeManagedService) -> Bool {
        if isLoaded(service) {
            serviceManager.stop(service: service)
            return true
        }
        return false
    }
}
