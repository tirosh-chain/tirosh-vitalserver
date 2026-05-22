import RuntimeCore
import XCTest
@testable import ManagerApp

final class RuntimeCommandFactoryTests: XCTestCase {
    func testShellCommandQuotesArgumentsAndInjectsVMHomeForLauncher() {
        let command = RuntimeCommandFactory.shellCommand(
            executable: AppConstants.Paths.launcher,
            arguments: [
                AppConstants.RuntimeCommand.runtime,
                AppConstants.RuntimeCommand.applyBundle,
                "/tmp/bundle with 'quote'",
            ]
        )

        XCTAssertTrue(command.hasPrefix("'/usr/bin/env' VITALSERVER_VM_HOME="))
        XCTAssertTrue(command.contains("'/usr/local/bin/vitalserver-vm'"))
        XCTAssertTrue(command.contains("'/tmp/bundle with '\\''quote'\\'''"))
    }

    func testDeleteBackupCommandUsesSafeArgumentBoundary() {
        let command = RuntimeCommandFactory.deleteBackupCommand(path: "/tmp/backup before")

        XCTAssertEqual(command, "'/bin/rm' '-rf' '--' '/tmp/backup before'")
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

    func testProxyRepairCommandIncludesPortAndLaunchctlRestart() {
        let command = RuntimeCommandFactory.proxyRepairCommand(proxyPort: 18080)

        XCTAssertTrue(command.hasPrefix("/bin/bash -lc "))
        XCTAssertTrue(command.contains("port=18080"))
        XCTAssertTrue(command.contains("kickstart -k system/com.tirosh.vitalserver-proxy"))
    }

    func testRuntimeServicesCommandsUseLauncherRuntimeSubcommands() {
        let startCommand = RuntimeCommandFactory.runtimeServicesCommand(action: .start)
        let stopCommand = RuntimeCommandFactory.runtimeServicesCommand(action: .stop)

        XCTAssertTrue(startCommand.contains("'runtime' 'start-services'"))
        XCTAssertTrue(stopCommand.contains("'runtime' 'stop-services'"))
    }
}
