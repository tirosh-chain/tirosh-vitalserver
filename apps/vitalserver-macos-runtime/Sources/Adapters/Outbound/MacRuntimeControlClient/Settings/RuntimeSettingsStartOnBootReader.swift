import RuntimeControl
import Contracts

struct RuntimeSettingsStartOnBootReader {
    private var runCommand: @Sendable (String, [String]) -> RuntimeCommandResult

    init(runCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult) {
        self.runCommand = runCommand
    }

    func startOnBootEnabled() -> RuntimeSettingsReadResult<Bool> {
        let result = runCommand(
            RuntimeControlClientConstants.Commands.launchctl,
            ["print-disabled", "system"]
        )
        guard result.exitCode == 0 else {
            return .failed(result.stderr.isEmpty ? "launchctl print-disabled failed" : result.stderr)
        }
        let output = result.stdout
        for label in [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.proxy.label,
            RuntimeManagedService.guestLogSync.label,
            RuntimeManagedService.watchdog.label,
        ] where output.contains("\"\(label)\" => true") {
            return .loaded(false)
        }
        return .loaded(true)
    }
}
