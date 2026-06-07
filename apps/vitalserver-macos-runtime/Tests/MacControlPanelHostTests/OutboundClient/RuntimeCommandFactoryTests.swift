import Contracts
@testable import OutboundAdapters
import XCTest
import Errors
@testable import MacControlPanelHost
@testable import InboundAdapters

final class RuntimeCommandFactoryTests: XCTestCase {
    func testShellCommandQuotesArgumentsAndInjectsVMHomeForLauncher() {
        let command = RuntimeCommandFactory.shellCommand(
            executable: RuntimeControlClientConstants.Paths.launcher,
            arguments: [
                RuntimeControlClientConstants.RuntimeCommand.runtime,
                RuntimeControlClientConstants.RuntimeCommand.applyBundle,
                "/tmp/bundle with 'quote'",
            ]
        )

        XCTAssertTrue(command.hasPrefix("'/usr/bin/env' VITALSERVER_VM_HOME="))
        XCTAssertTrue(command.contains("'/usr/local/bin/vitalserver-vm'"))
        XCTAssertTrue(command.contains("'/tmp/bundle with '\\''quote'\\'''"))
    }

    func testDeleteBackupCommandUsesSafeArgumentBoundary() {
        let command = RuntimeCommandFactory.deleteBackupCommand(url: URL(fileURLWithPath: "/tmp/backup before"))

        XCTAssertEqual(command, "'/bin/rm' '-rf' '--' '/tmp/backup before'")
    }

    func testUninstallCommandStartsBackgroundUninstaller() {
        let command = RuntimeCommandFactory.uninstallCommand(
            uninstaller: "/usr/local/bin/tirosh-vitalserver-uninstall",
            clean: true
        )

        XCTAssertTrue(command.hasPrefix("/bin/bash -lc "))
        XCTAssertFalse(command.contains("nohup"))
        XCTAssertTrue(command.contains("previous_log_file='\\''/private/tmp/tirosh-vitalserver-uninstall.log.previous'\\''"))
        XCTAssertTrue(command.contains(": > \"${log_file}\""))
        XCTAssertTrue(command.contains("viewer_script='\\''/private/tmp/tirosh-vitalserver-uninstall-progress.command'\\''"))
        XCTAssertTrue(command.contains("open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("if ! open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("echo \"\(RuntimeUninstallProgressScript.terminalOpenFailedMessage)\" >> \"${log_file}\""))
        XCTAssertTrue(command.contains("tail -n 0 -F"))
        XCTAssertTrue(command.contains("'\\''/usr/local/bin/tirosh-vitalserver-uninstall'\\'' '\\''--clean'\\''"))
        XCTAssertTrue(command.contains("background_status=$?"))
        XCTAssertTrue(command.contains("echo \"\(RuntimeUninstallProgressScript.completedMarker)\""))
        XCTAssertTrue(command.contains("echo \"\(RuntimeUninstallProgressScript.failedMarkerPrefix)${background_status}\""))
        XCTAssertTrue(command.contains("} < /dev/null >> \"${log_file}\" 2>&1 &"))
        XCTAssertTrue(command.contains("background_pid=$!"))
        XCTAssertTrue(command.contains("kill -0"))
        XCTAssertFalse(command.contains("&;"))
        XCTAssertFalse(command.contains("open -a Terminal \"${viewer_script}\" >/dev/null 2>&1 || true"))
        XCTAssertFalse(command.contains("uninstall completed log="))
        XCTAssertTrue(command.contains("Background uninstaller started."))
    }

    func testCommandWithLogCapturesExitStatus() {
        let command = RuntimeCommandFactory.commandWithLog("echo hello")

        XCTAssertTrue(command.hasPrefix("/bin/bash -lc "))
        XCTAssertTrue(command.contains("rm -f"))
        XCTAssertTrue(command.contains("/private/tmp/\(RuntimeFileNames.managerCommandLog)"))
        XCTAssertTrue(command.contains("{ echo hello; }"))
        XCTAssertTrue(command.contains("2>&1"))
        XCTAssertTrue(command.contains("exit $status"))
    }

    func testProxyRepairCommandDelegatesToLauncherRepairProxySubcommand() {
        let command = RuntimeCommandFactory.proxyRepairCommand()

        XCTAssertTrue(command.hasPrefix("'/usr/bin/env' VITALSERVER_VM_HOME="))
        XCTAssertTrue(command.contains("'/usr/local/bin/vitalserver-vm'"))
        XCTAssertTrue(command.contains("'runtime' 'repair-proxy'"))
        XCTAssertFalse(command.contains("lsof"))
        XCTAssertFalse(command.contains("kill -TERM"))
    }

    func testRuntimeServicesCommandsUseLauncherRuntimeSubcommands() {
        let startCommand = RuntimeCommandFactory.runtimeServicesCommand(action: .start)
        let stopCommand = RuntimeCommandFactory.runtimeServicesCommand(action: .stop)

        XCTAssertTrue(startCommand.contains("'runtime' 'start-services'"))
        XCTAssertTrue(stopCommand.contains("'runtime' 'stop-services'"))
    }
}
