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

    func testCleanUninstallCommandUsesCleanArgumentWithoutForceCleanRecoveryArgument() {
        let command = RuntimeCommandFactory.uninstallCommand(
            uninstaller: "/usr/local/bin/tirosh-vitalserver-uninstall",
            clean: true,
            forceClean: false
        )

        XCTAssertTrue(command.contains("'--clean'"))
        XCTAssertFalse(command.contains("--force-clean-uninstaller"))
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
        XCTAssertTrue(command.contains("result_file='\\''/private/tmp/tirosh-vitalserver-uninstall-progress.command.result.json'\\''"))
        XCTAssertTrue(command.contains("open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("VITALSERVER_UNINSTALL_PROGRESS_OPEN"))
        XCTAssertTrue(command.contains("if ! open -a Terminal \"${viewer_script}\""))
        XCTAssertTrue(command.contains("echo \"\(RuntimeUninstallProgressScript.terminalOpenFailedMessage)\" >> \"${log_file}\""))
        XCTAssertTrue(command.contains("write_result \"running\""))
        XCTAssertTrue(command.contains("write_result \"completed\" 0 true \"uninstall completed\" \"not-checked\""))
        XCTAssertTrue(command.contains("\"freshInstallReadiness\""))
        XCTAssertTrue(command.contains("tail -n 0 -F"))
        XCTAssertTrue(command.contains("read -r -t \(RuntimeUninstallProgressScript.terminalCloseDelaySeconds) _ || true"))
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
        XCTAssertTrue(command.contains("mark_missing_terminal_failure()"))
        XCTAssertTrue(command.contains("uninstall worker exited before terminal marker"))
        XCTAssertTrue(command.contains("echo \"${marker_run_id}\""))
        XCTAssertTrue(command.contains("echo \"${background_pid}\""))
        XCTAssertTrue(command.contains("> \"${worker_pid_file}\""))
        XCTAssertTrue(command.contains("chmod 0644 \"${worker_pid_file}\""))
        XCTAssertTrue(command.contains("background_pid=$!"))
        XCTAssertTrue(command.contains("kill -0"))
        XCTAssertTrue(command.contains("ps -p \"${worker_pid}\" -o pid="))
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
        XCTAssertTrue(script.contains("result_file='/tmp/viewer script'\\''s.command.result.json'"))
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
        XCTAssertTrue(script.contains("mark_missing_terminal_failure()"))
        XCTAssertTrue(script.contains("uninstall worker exited before terminal marker"))
        XCTAssertFalse(script.contains("nohup"))
        XCTAssertTrue(script.contains("echo \"${marker_run_id}\""))
        XCTAssertTrue(script.contains("echo \"${background_pid}\""))
        XCTAssertTrue(script.contains("> \"${worker_pid_file}\""))
        XCTAssertTrue(script.contains("ps -p \"${worker_pid}\" -o pid="))
        XCTAssertFalse(script.contains("&;"))
        XCTAssertFalse(script.contains("} < /dev/null >> \"${log_file}\" 2>&1 &"))
    }

    func testUninstallWorkerMarksMissingTerminalOnUnexpectedExit() {
        let script = RuntimeUninstallProgressScript.workerScript(
            plan: RuntimeUninstallProgressScriptPlan(
                command: "'/bin/uninstall-tool' '--clean'",
                logPath: "/tmp/uninstall.log",
                previousLogPath: "/tmp/uninstall.log.previous",
                viewerScriptPath: "/tmp/uninstall.command",
                runID: "worker-test"
            ),
            shellQuote: RuntimeShellCommandFactory.shellQuote
        )

        XCTAssertTrue(script.contains("mark_missing_terminal_failure()"))
        XCTAssertTrue(script.contains("echo \"${failed_marker_prefix}missing-marker ${marker_run_id}\""))
        XCTAssertTrue(script.contains("write_result \"failed\" 1 false \"uninstall worker exited before terminal marker\" \"not-checked\""))
        XCTAssertTrue(script.contains("trap 'mark_missing_terminal_failure' EXIT"))
    }

    func testUninstallProgressViewerDoesNotUseSignalPermissionAsWorkerState() {
        let viewer = RuntimeUninstallProgressScript.viewerScript(
            logPath: "/tmp/uninstall.log",
            workerPIDPath: "/tmp/uninstall.pid",
            resultPath: "/tmp/uninstall-result.json",
            runID: "viewer-test",
            shellQuote: RuntimeShellCommandFactory.shellQuote
        )

        XCTAssertTrue(viewer.contains("worker_process_exited()"))
        XCTAssertTrue(viewer.contains("ps -p \"${worker_pid}\" -o pid="))
        XCTAssertTrue(viewer.contains("read -r -t \(RuntimeUninstallProgressScript.terminalCloseDelaySeconds) _ || true"))
        XCTAssertFalse(viewer.contains("kill -0 \"${worker_pid}\""))
    }

    func testUninstallProgressViewerFailsWhenWorkerPidDisappearsWithoutTerminalMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "runID=viewer-test\n99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
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
        XCTAssertTrue(terminalOutput.contains(RuntimeUninstallProgressScript.terminalResultMissingMessage))
    }

    func testUninstallProgressViewerDoesNotTreatDifferentRunWorkerExitAsFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=other-run\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "runID=other-run\n99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
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

    func testUninstallProgressViewerIgnoresLegacyPidFileWithoutRunID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
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
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "runID=viewer-test\n99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
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

    func testUninstallProgressViewerWaitsForResultDocumentAfterOwnedWorkerExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.startedMarker) runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try "runID=viewer-test\n99999999\n".write(to: pidURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
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
            let result = """
            {"schemaVersion":1,"runID":"viewer-test","state":"completed","exitCode":0,"uninstallCompleted":true,"freshInstallReadiness":{"state":"not-checked","blockers":[]},"message":"uninstall completed"}

            """
            try? result.write(to: resultURL, atomically: true, encoding: .utf8)
        }
        input.fileHandleForWriting.write(Data("\n".utf8))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            usleep(100_000)
        }

        XCTAssertFalse(process.isRunning)
        let terminalOutput = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(terminalOutput.contains(RuntimeUninstallProgressScript.terminalCompletedMessage), terminalOutput)
        XCTAssertFalse(terminalOutput.contains(RuntimeUninstallProgressScript.terminalResultMissingMessage), terminalOutput)
        XCTAssertFalse(terminalOutput.contains(RuntimeUninstallProgressScript.terminalFailedMessage), terminalOutput)
    }

    func testUninstallProgressViewerUsesResultDocumentBeforeConflictingLogMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("uninstall.log")
        let pidURL = directory.appendingPathComponent("uninstall.pid")
        let resultURL = directory.appendingPathComponent("uninstall-result.json")
        let viewerURL = directory.appendingPathComponent("viewer.command")
        try "\(RuntimeUninstallProgressScript.failedMarkerPrefix)1 runID=viewer-test\n"
            .write(to: logURL, atomically: true, encoding: .utf8)
        try """
        {"schemaVersion":1,"runID":"viewer-test","state":"completed","exitCode":0,"uninstallCompleted":true,"freshInstallReadiness":{"state":"not-checked","blockers":[]},"message":"uninstall completed"}
        """.write(to: resultURL, atomically: true, encoding: .utf8)
        try RuntimeUninstallProgressScript.viewerScript(
            logPath: logURL.path,
            workerPIDPath: pidURL.path,
            resultPath: resultURL.path,
            runID: "viewer-test",
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: viewerURL, atomically: true, encoding: .utf8)

        let output = try runViewerScript(viewerURL)

        XCTAssertTrue(output.contains(RuntimeUninstallProgressScript.terminalCompletedMessage), output)
        XCTAssertTrue(output.contains(RuntimeUninstallProgressScript.terminalFreshInstallReadinessNotCheckedMessage), output)
        XCTAssertFalse(output.contains(RuntimeUninstallProgressScript.terminalFailedMessage), output)
    }

    func testUninstallStartScriptWritesCompletedResultDocumentInDryRun() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let startURL = directory.appendingPathComponent("start.sh")
        let plan = progressPlan(directory: directory, command: "/usr/bin/true", runID: "dry-run-success")
        try RuntimeUninstallProgressScript.startScript(
            plan: plan,
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: startURL, atomically: true, encoding: .utf8)

        let output = try runStartScript(startURL)
        let result = try waitForResult(at: URL(fileURLWithPath: plan.resultPath))

        XCTAssertTrue(output.contains("Background uninstaller started."))
        XCTAssertTrue(result.contains("\"runID\":\"dry-run-success\""))
        XCTAssertTrue(result.contains("\"state\":\"completed\""))
        XCTAssertTrue(result.contains("\"uninstallCompleted\":true"))
        XCTAssertTrue(result.contains("\"freshInstallReadiness\":{\"state\":\"not-checked\",\"blockers\":[]}"))
    }

    func testUninstallStartScriptWritesFailedResultDocumentInDryRun() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitalserver-uninstall-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let startURL = directory.appendingPathComponent("start.sh")
        let plan = progressPlan(directory: directory, command: "/bin/sh -c 'exit 7'", runID: "dry-run-failure")
        try RuntimeUninstallProgressScript.startScript(
            plan: plan,
            shellQuote: RuntimeShellCommandFactory.shellQuote
        ).write(to: startURL, atomically: true, encoding: .utf8)

        _ = try runStartScript(startURL)
        let result = try waitForResult(at: URL(fileURLWithPath: plan.resultPath))

        XCTAssertTrue(result.contains("\"runID\":\"dry-run-failure\""))
        XCTAssertTrue(result.contains("\"state\":\"failed\""))
        XCTAssertTrue(result.contains("\"exitCode\":7"))
        XCTAssertTrue(result.contains("\"uninstallCompleted\":false"))
        XCTAssertTrue(result.contains("\"freshInstallReadiness\":{\"state\":\"not-checked\",\"blockers\":[]}"))
    }

    func testCommandWithLogCapturesExitStatus() {
        let command = RuntimeCommandFactory.commandWithLog("echo hello")

        XCTAssertTrue(command.hasPrefix("/bin/bash -lc "))
        XCTAssertTrue(command.contains("rm -f"))
        XCTAssertTrue(command.contains("/private/tmp/\(RuntimeLogArtifactFileNames.managerCommandLog)"))
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

    func testRuntimeProviderRestartStopsBeforeStarting() {
        let command = RuntimeCommandFactory.runtimeProviderCommand(action: .restart)

        let stopRange = try! XCTUnwrap(command.range(of: "'runtime' 'stop-services'"))
        let startRange = try! XCTUnwrap(command.range(of: "'runtime' 'start-services'"))
        XCTAssertLessThan(stopRange.lowerBound, startRange.lowerBound)
        XCTAssertTrue(command.contains(" && "))
    }
}

private func progressPlan(
    directory: URL,
    command: String,
    runID: String
) -> RuntimeUninstallProgressScriptPlan {
    RuntimeUninstallProgressScriptPlan(
        command: command,
        logPath: directory.appendingPathComponent("uninstall.log").path,
        previousLogPath: directory.appendingPathComponent("uninstall.log.previous").path,
        viewerScriptPath: directory.appendingPathComponent("viewer.command").path,
        resultPath: directory.appendingPathComponent("uninstall-result.json").path,
        runID: runID
    )
}

private func runStartScript(_ url: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [url.path]
    var environment = ProcessInfo.processInfo.environment
    environment["VITALSERVER_UNINSTALL_PROGRESS_OPEN"] = "0"
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func runViewerScript(_ url: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [url.path]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    try process.run()
    input.fileHandleForWriting.write(Data("\n".utf8))
    input.fileHandleForWriting.closeFile()

    let deadline = Date().addingTimeInterval(5)
    while process.isRunning && Date() < deadline {
        usleep(100_000)
    }
    if process.isRunning {
        process.terminate()
    }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func waitForResult(at url: URL) throws -> String {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let result = try? String(contentsOf: url), !result.isEmpty {
            if result.contains("\"state\":\"completed\"") || result.contains("\"state\":\"failed\"") {
                return result
            }
        }
        usleep(100_000)
    }
    return try String(contentsOf: url)
}
