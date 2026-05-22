import Foundation
import RuntimeCore

struct LaunchdRuntimeServiceManager: RuntimeServiceManager {
    private let commandRunner: RuntimeCommandRunner

    init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    func state(label: String) -> String {
        let result = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["print", "system/\(label)"]
        )
        return result.exitCode == 0 ? "loaded" : "not loaded"
    }

    func start(label: String, plist: String) {
        let bootstrap = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["bootstrap", "system", plist]
        )
        if bootstrap.exitCode != 0 {
            _ = commandRunner.run(
                Constants.Commands.launchctl,
                arguments: ["kickstart", "-k", "system/\(label)"]
            )
        }
    }

    func restart(label: String) {
        _ = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["kickstart", "-k", "system/\(label)"]
        )
    }

    func stop(label: String) {
        _ = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["bootout", "system/\(label)"]
        )
    }

    func setEnabled(label: String, enabled: Bool) -> RuntimeProcessResult {
        let action = enabled ? "enable" : "disable"
        return commandRunner.run(
            Constants.Commands.launchctl,
            arguments: [action, "system/\(label)"]
        )
    }
}
