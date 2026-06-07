import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func setInstalledProxyPort(_ port: Int) throws {
        try runRequired(
            Constants.Commands.plistBuddy,
            arguments: [
                "-c",
                "Set :EnvironmentVariables:VITALSERVER_PROXY_PORT \(port)",
                launchDaemonPlist(.proxy),
            ]
        )
    }

    func readSecretFile(_ url: URL) throws -> String {
        guard url.path.hasPrefix("/private/tmp/") || url.path.hasPrefix("/tmp/") else {
            throw LauncherError.missingArgument("--admin-password-file must be under /private/tmp")
        }
        let data = try fileStore.readData(url)
        guard let value = String(data: data, encoding: .utf8) else {
            throw LauncherError.missingArgument("--admin-password-file must be UTF-8")
        }
        return value
    }

    func restrictSecretFile(_ url: URL) throws {
        try runRequired(Constants.Commands.chmod, arguments: ["0600", url.path])
    }

    func setStartOnBoot(_ enabled: Bool) throws {
        try serviceController.setStartOnBoot(enabled)
    }

    func setSystemSleepPrevention(_ enabled: Bool) throws {
        let plist = URL(fileURLWithPath: RuntimeManagedService.sleepPrevention.launchDaemonPlist)
        let plistState = fileStore.pathState(at: plist)
        switch plistState {
        case .file:
            break
        case .missing:
            log("system sleep prevention service is not installed; setting recorded only")
            return
        case .inspectFailed(let reason):
            throw LauncherError.runtimeOperationFailed(
                "system sleep prevention service inspection failed path=\(plist.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            throw LauncherError.runtimeOperationFailed(
                "system sleep prevention service path state is unexpected path=\(plist.path) state=\(plistState.rawValue)"
            )
        }
        let action = enabled ? "enable" : "disable"
        try runRequired(Constants.Commands.launchctl, arguments: [
            action,
            "system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
        if enabled {
            try startLaunchdService(.sleepPrevention)
        } else {
            try stopLaunchdService(.sleepPrevention)
        }
        log("system sleep prevention \(enabled ? "enabled" : "disabled")")
    }

    func preventSystemSleepEnabled() throws -> Bool {
        switch runtimeConfigFlagReader().preventSystemSleepFlag() {
        case .configured(_, let value), .defaulted(_, let value, _):
            return value
        case .failed(let name, let reason):
            throw LauncherError.runtimeOperationFailed(
                "runtime config flag read failed name=\(name) reason=\(reason)"
            )
        }
    }

    func runtimeConfigFlagReader() -> RuntimeConfigFlagReader {
        RuntimeConfigFlagReader(
            loadFlags: {
                let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
                return RuntimeConfigFlagValues(
                    autoRecoveryEnabled: config.autoRecoveryEnabled,
                    preventSystemSleep: config.preventSystemSleep
                )
            },
            log: log
        )
    }

    func configuredExternalVitalFilesDirectory() -> RuntimeConfiguredExternalVitalFilesDirectoryRead {
        do {
            let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
            if let hostPath = config.vitalFilesDirectory?.hostPath, hostPath.hasPrefix("/") {
                let url = URL(fileURLWithPath: hostPath)
                guard url.path != installedPaths.vitalFilesDirectory.path else {
                    return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
                }
                return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: url, failure: nil)
            }
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
        } catch {
            let reason = error.localizedDescription
            log("failed to read configured vital files directory error=\(reason)")
            return RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: reason)
        }
    }

    func runtimeCommandExecutor() -> RuntimeCommandExecutor {
        RuntimeCommandExecutor(
            commandRunner: commandRunner,
            log: log,
            recordCommandEvent: { eventType, executable, arguments, result in
                runtimeEventPublisher().recordCommandEventBestEffort(
                    eventType,
                    executable: executable,
                    arguments: arguments,
                    result: result
                )
            }
        )
    }

    func runProcess(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        runtimeCommandExecutor().run(executable, arguments)
    }

    func runRequired(_ executable: String, arguments: [String]) throws {
        try runtimeCommandExecutor().runRequired(executable, arguments)
    }

    func runProcessToFile(_ executable: String, arguments: [String], output: URL) throws {
        try runtimeCommandExecutor().runWritingOutput(executable, arguments, output: output)
    }

    func fileExists(_ url: URL) -> Bool {
        fileStore.fileExists(url)
    }

    func directoryExists(_ url: URL) -> Bool {
        fileStore.directoryExists(url)
    }
}
