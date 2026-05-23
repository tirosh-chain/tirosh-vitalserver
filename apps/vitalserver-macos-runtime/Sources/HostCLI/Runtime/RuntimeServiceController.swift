import Foundation
import Core
import Contracts

struct RuntimeServiceController {
    private let serviceManager: RuntimeServiceManager
    private let isLoaded: (RuntimeManagedService) -> Bool
    private let log: (String) -> Void

    init(
        serviceManager: RuntimeServiceManager,
        isLoaded: @escaping (RuntimeManagedService) -> Bool,
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.isLoaded = isLoaded
        self.log = log
    }

    func stopRuntimeServices() {
        log("stopping runtime services")
        for service in RuntimeManagedService.stopOrder {
            stopIfLoaded(service)
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

    func restartLaunchdService(_ service: RuntimeManagedService) {
        log("launchd restart label=\(service.label)")
        serviceManager.restart(service: service)
        if !isLoaded(service) {
            startLaunchdService(service)
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

    private func stopIfLoaded(_ service: RuntimeManagedService) {
        if isLoaded(service) {
            serviceManager.stop(service: service)
        }
    }
}
