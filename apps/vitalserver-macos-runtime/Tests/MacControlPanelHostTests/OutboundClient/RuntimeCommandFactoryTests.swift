import Contracts
import Foundation
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
            clean: true,
            forceClean: true
        )

        XCTAssertTrue(command.hasPrefix("/bin/bash -lc "))
        XCTAssertTrue(command.contains("/bin/bash \"${worker_script}\" </dev/null >> \"${log_file}\" 2>&1 &"))
        XCTAssertFalse(command.contains("nohup"))
        XCTAssertTrue(command.contains("previous_log_file='\\''/private/tmp/tirosh-vitalserver-uninstall.log.previous'\\''"))
        XCTAssertTrue(command.contains(": > \"${log_file}\""))
        XCTAssertTrue(command.contains("chmod 0644 \"${log_file}\""))
        XCTAssertTrue(command.contains("viewer_script='\\''/private/tmp/tirosh-vitalserver-uninstall-progress.command'\\''"))
        XCTAssertTrue(command.contains("worker_script='\\''/private/tmp/tirosh-vitalserver-uninstall-progress.command.worker'\\''"))
        XCTAssertTrue(command.contains("worker_pid_file='\\''/private/tmp/tirosh-vitalserver-uninstall-progress.command.pid'\\''"))
        XCTAssertTrue(command.contains("open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("if ! open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("echo \"\(RuntimeUninstallProgressScript.terminalOpenFailedMessage)\" >> \"${log_file}\""))
        XCTAssertTrue(command.contains("tail -n 0 -F"))
        XCTAssertTrue(command.contains("worker_pid_file="))
        XCTAssertTrue(command.contains("/usr/local/bin/tirosh-vitalserver-uninstall"))
        XCTAssertTrue(command.contains("--force-clean-uninstaller"))
        XCTAssertFalse(command.contains("'--clean'"))
        XCTAssertTrue(command.contains("background_status=$?"))
        XCTAssertTrue(command.contains("marker_run_id="))
        XCTAssertTrue(command.contains("\(RuntimeUninstallProgressScript.startedMarker)"))
        XCTAssertTrue(command.contains("started_marker="))
        XCTAssertTrue(command.contains("echo \"${started_marker}\""))
        XCTAssertTrue(command.contains("echo \"${completed_marker}\""))
        XCTAssertTrue(command.contains("echo \"${failed_marker_prefix}${background_status} ${marker_run_id}\""))
        XCTAssertTrue(command.contains("echo \"${background_pid}\" > \"${worker_pid_file}\""))
        XCTAssertTrue(command.contains("chmod 0644 \"${worker_pid_file}\""))
        XCTAssertTrue(command.contains("background_pid=$!"))
        XCTAssertTrue(command.contains("kill -0"))
        XCTAssertTrue(command.contains("\(RuntimeUninstallProgressScript.failedMarkerPrefix)\(RuntimeUninstallProgressScript.missingMarkerStatus)"))
        XCTAssertFalse(command.contains("&;"))
        XCTAssertFalse(command.contains("} < /dev/null >> \"${log_file}\" 2>&1 &"))
        XCTAssertFalse(command.contains("open -a Terminal \"${viewer_script}\" >/dev/null 2>&1 || true"))
        XCTAssertFalse(command.contains("uninstall completed log="))
        XCTAssertTrue(command.contains("Background uninstaller started."))
    }

    func testUninstallProgressScriptPlanPreservesQuotedPathsAndViewerFailure() {
        let script = RuntimeUninstallProgressScript.startScript(
            plan: RuntimeUninstallProgressScriptPlan(
                command: "'/bin/uninstall tool' '--clean'",
                logPath: "/tmp/uninstall log's/current.log",
                previousLogPath: "/tmp/uninstall log's/current.log.previous",
                viewerScriptPath: "/tmp/viewer script's.command",
                runID: "test-run"
            ),
            shellQuote: RuntimeShellCommandFactory.shellQuote
        )

        XCTAssertTrue(script.contains("log_file='/tmp/uninstall log'\\''s/current.log'"))
        XCTAssertTrue(script.contains("previous_log_file='/tmp/uninstall log'\\''s/current.log.previous'"))
        XCTAssertTrue(script.contains("viewer_script='/tmp/viewer script'\\''s.command'"))
        XCTAssertTrue(script.contains("worker_script='/tmp/viewer script'\\''s.command.worker'"))
        XCTAssertTrue(script.contains("worker_pid_file='/tmp/viewer script'\\''s.command.pid'"))
        XCTAssertTrue(script.contains("marker_run_id='runID=test-run'"))
        XCTAssertTrue(script.contains("\(RuntimeUninstallProgressScript.startedMarker) runID=test-run"))
        XCTAssertTrue(script.contains("\(RuntimeUninstallProgressScript.completedMarker) runID=test-run"))
        XCTAssertTrue(script.contains("if ! open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(script.contains("echo \"\(RuntimeUninstallProgressScript.terminalOpenFailedMessage)\" >> \"${log_file}\""))
        XCTAssertTrue(script.contains("/bin/uninstall tool"))
        XCTAssertTrue(script.contains("--clean"))
        XCTAssertTrue(script.contains("/bin/bash \"${worker_script}\" </dev/null >> \"${log_file}\" 2>&1 &"))
        XCTAssertTrue(script.contains("chmod 0644 \"${log_file}\""))
        XCTAssertTrue(script.contains("chmod 0644 \"${worker_pid_file}\""))
        XCTAssertFalse(script.contains("nohup"))
        XCTAssertTrue(script.contains("echo \"${background_pid}\" > \"${worker_pid_file}\""))
        XCTAssertFalse(script.contains("&;"))
        XCTAssertFalse(script.contains("} < /dev/null >> \"${log_file}\" 2>&1 &"))
    }

    func testUninstallProgressViewerFailsWhenWorkerPidDisappearsWithoutTerminalMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            runID: "viewer-test",
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: viewerURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [viewerURL.path]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try process.run()
        input.fileHandleForWriting.write(Data("\n".utf8))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            usleep(100_000)
        }

        XCTAssertFalse(process.isRunning)
        let log = try String(contentsOf: logURL)
        let terminalOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertFalse(log.contains(
            "\(RuntimeUninstallProgressScript.failedMarkerPrefix)\(RuntimeUninstallProgressScript.missingMarkerStatus)"
        ))
        XCTAssertTrue(terminalOutput.contains(RuntimeUninstallProgressScript.terminalFailedMessage))
    }

    func testUninstallProgressViewerDoesNotTreatDifferentRunWorkerExitAsFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=other-run\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            runID: "viewer-test",
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: viewerURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [viewerURL.path]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            let completedLine = "\(RuntimeUninstallProgressScript.completedMarker) runID=viewer-test\n"
            if let data = completedLine.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
        input.fileHandleForWriting.write(Data("\n".utf8))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            usleep(100_000)
        }

        XCTAssertFalse(process.isRunning)
        let terminalOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(terminalOutput.contains(RuntimeUninstallProgressScript.terminalCompletedMessage))
        XCTAssertFalse(terminalOutput.contains(RuntimeUninstallProgressScript.terminalFailedMessage))
    }

    func testUninstallProgressViewerWaitsForTerminalMarkerAfterOwnedWorkerExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            runID: "viewer-test",
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: viewerURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [viewerURL.path]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            let completedLine = "\(RuntimeUninstallProgressScript.completedMarker) runID=viewer-test\n"
            if let data = completedLine.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
        input.fileHandleForWriting.write(Data("\n".utf8))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            usleep(100_000)
        }

        XCTAssertFalse(process.isRunning)
        let terminalOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(terminalOutput.contains(RuntimeUninstallProgressScript.terminalCompletedMessage))
        XCTAssertFalse(terminalOutput.contains(RuntimeUninstallProgressScript.terminalFailedMessage))
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
        let repairCommand = RuntimeCommandFactory.runtimeServicesCommand(action: .repair)

        XCTAssertTrue(startCommand.contains("'runtime' 'start-services'"))
        XCTAssertTrue(stopCommand.contains("'runtime' 'stop-services'"))
        XCTAssertTrue(repairCommand.contains("'runtime' 'repair-services'"))
    }
}
