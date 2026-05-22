import Foundation
import RuntimeCore

struct RuntimeServiceController {
    private let serviceManager: RuntimeServiceManager
    private let isLoaded: (String) -> Bool
    private let log: (String) -> Void

    init(
        serviceManager: RuntimeServiceManager,
        isLoaded: @escaping (String) -> Bool,
        log: @escaping (String) -> Void
    ) {
        self.serviceManager = serviceManager
        self.isLoaded = isLoaded
        self.log = log
    }

    func stopRuntimeServices() {
        log("stopping runtime services")
        stopIfLoaded(Constants.Launchd.watchdogService)
        stopIfLoaded(Constants.Launchd.proxyService)
        stopIfLoaded(Constants.Launchd.vmService)
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
            log("starting VM service label=\(Constants.Launchd.vmService)")
            startLaunchdService(Constants.Launchd.vmService)
        }
        if restartProxy {
            log("starting proxy service label=\(Constants.Launchd.proxyService)")
            startLaunchdService(Constants.Launchd.proxyService)
        }
        if restartWatchdog {
            log("starting watchdog service label=\(Constants.Launchd.watchdogService)")
            startLaunchdService(Constants.Launchd.watchdogService)
        }
    }

    func startLaunchdService(_ label: String) {
        let plist = launchDaemonPlist(label)
        log("launchd bootstrap label=\(label) plist=\(plist)")
        serviceManager.start(label: label, plist: plist)
    }

    func restartLaunchdService(_ label: String) {
        log("launchd restart label=\(label)")
        serviceManager.restart(label: label)
        if !isLoaded(label) {
            startLaunchdService(label)
        }
    }

    func setStartOnBoot(_ enabled: Bool) throws {
        for label in Constants.Launchd.runtimeServices {
            let result = serviceManager.setEnabled(label: label, enabled: enabled)
            guard result.exitCode == 0 else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stderr.isEmpty {
                    log("command stderr executable=\(Constants.Commands.launchctl) stderr=\(stderr)")
                }
                log("command failed executable=\(Constants.Commands.launchctl) exitCode=\(result.exitCode)")
                throw LauncherError.missingArgument(
                    "command failed: \(Constants.Commands.launchctl) \(enabled ? "enable" : "disable") system/\(label)"
                )
            }
        }
    }

    private func stopIfLoaded(_ label: String) {
        if isLoaded(label) {
            serviceManager.stop(label: label)
        }
    }

    private func launchDaemonPlist(_ label: String) -> String {
        "\(Constants.InstallPaths.launchDaemons)/\(label).plist"
    }
}
