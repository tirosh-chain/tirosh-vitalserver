import Foundation
import Application
import Contracts
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors
import RuntimeControl

final class RuntimeLifecycleCommandTests: XCTestCase {
    func testParsesCommandsWithoutArguments() throws {
        XCTAssertEqual(try RuntimeLifecycleCommand.parse([]), .help)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["install"]), .install)
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "install-provision",
                "--package-install-contract",
                "/tmp/package-install-contract.json",
            ]),
            .installProvision(URL(fileURLWithPath: "/tmp/package-install-contract.json"))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "preinstall-check",
                "--package-install-contract",
                "/tmp/package-install-contract.json",
            ]),
            .preinstallCheck(URL(fileURLWithPath: "/tmp/package-install-contract.json"))
        )
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["status"]), .status)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["health"]), .health)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["guest-log-sync"]), .guestLogSync)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["watchdog"]), .watchdog)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["redis-backup"]), .redisBackup)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["automatic-backup"]), .automaticBackup)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-datastore"]), .repairDatastore)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-vm-disk"]), .repairVMDisk)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-proxy"]), .repairProxy)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-services"]), .repairServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["start-services"]), .startServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["stop-services"]), .stopServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["stop-package-services"]), .stopPackageServices)
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["guest-stack-status"]),
            .guestStackStatus(RuntimeGuestControlReadCommand())
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["guest-service-start", "app"]),
            .guestServiceStart(RuntimeGuestServiceControlCommand(service: "app"))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["guest-service-stop", "app"]),
            .guestServiceStop(RuntimeGuestServiceControlCommand(service: "app"))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["guest-service-restart", "app"]),
            .guestServiceRestart(RuntimeGuestServiceControlCommand(service: "app"))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["vitaldb-observation"]),
            .vitalDB(RuntimeVitalDBReadCommand(action: .observation))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["vitaldb-recorders"]),
            .vitalDB(RuntimeVitalDBReadCommand(action: .recorders))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["vitaldb-recorder-activity", "VR-001"]),
            .vitalDB(RuntimeVitalDBReadCommand(action: .recorderActivity("VR-001")))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["vitaldb-beds"]),
            .vitalDB(RuntimeVitalDBReadCommand(action: .beds))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["vitaldb-relationships"]),
            .vitalDB(RuntimeVitalDBReadCommand(action: .relationships))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-scenarios"]),
            .lab(RuntimeLabControlCommand(action: .scenarios))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-beds"]),
            .lab(RuntimeLabControlCommand(action: .beds))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-recorders"]),
            .lab(RuntimeLabControlCommand(action: .recorders))
        )
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["uninstall"]), .uninstall(RuntimeUninstallCommand(clean: false)))
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["--help"]), .help)
    }

    func testPackageInstallCommandsRequireExplicitContractPath() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["install-provision"]))
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["preinstall-check"]))
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse([
            "install-provision",
            "--package-install-contract",
        ]))
    }

    func testLegacyTestKitAliasesAreNotRuntimeCommands() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["testkit-start"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.unsupportedCommand("runtime testkit-start"))
            )
        }
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["testkit-stop"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.unsupportedCommand("runtime testkit-stop"))
            )
        }
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["testkit-restart"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.unsupportedCommand("runtime testkit-restart"))
            )
        }
    }

    func testParsesCleanUninstallCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["uninstall", "--clean"]),
            .uninstall(RuntimeUninstallCommand(clean: true))
        )
    }

    func testParsesForceCleanUninstallCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["uninstall", "--force-clean"]),
            .uninstall(RuntimeUninstallCommand(clean: true, forceClean: true))
        )
    }

    func testParsesForceCleanUninstallerUninstallCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["uninstall", "--force-clean-uninstaller"]),
            .uninstall(RuntimeUninstallCommand(clean: true, forceClean: true))
        )
    }

    func testParsesConfigureArgumentsIntoTypedCommand() throws {
        let command = try RuntimeLifecycleCommand.parse([
            "configure",
            "--cpu",
            "8",
            "--network",
            "shared",
            "--runtime-control-port",
            "18444",
            "--start-on-boot",
            "false",
            "--log-archive-retention-days",
            "10",
            "--log-archive-maximum-gib",
            "3",
            "--recorder-ingress-send-data-mode",
            "mirror_spool",
            "--recorder-ingress-send-data-replay-batch-size",
            "8",
            "--recorder-ingress-send-data-replay-max-mib-per-second",
            "12",
            "--recorder-ingress-settings-file",
            "/tmp/recorder-ingress-settings.json",
            "--restart",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            changes: [
                .cpu(8),
                .network(.shared),
                .runtimeControlPort(18444),
                .startOnBoot(false),
                .logArchiveRetentionDays(10),
                .logArchiveMaximumGiB(3),
                .recorderIngressSendDataMode(.mirrorSpool),
                .recorderIngressSendDataReplayBatchSize(8),
                .recorderIngressSendDataReplayMaxMiBPerSecond(12),
                .recorderIngressSettingsFile(URL(fileURLWithPath: "/tmp/recorder-ingress-settings.json")),
            ],
            restart: true
        )))
    }

    func testParsesBundleCommands() throws {
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")

        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["verify-bundle", bundleURL.path]),
            .verifyBundle(bundleURL)
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["stage-bundle", bundleURL.path]),
            .stageBundle(bundleURL)
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["apply-bundle", bundleURL.path]),
            .applyBundle(bundleURL)
        )
    }

    func testParsesOptionalRollbackPath() throws {
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["rollback"]), .rollback(.latestBackup))
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["rollback", "/backups/latest"]),
            .rollback(.specificBackup(URL(fileURLWithPath: "/backups/latest")))
        )
    }

    func testParsesGuestServiceControlWithExplicitGuestControlURL() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "guest-stack-status",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .guestStackStatus(RuntimeGuestControlReadCommand(
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "guest-service-start",
                "recorder-ingress",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .guestServiceStart(RuntimeGuestServiceControlCommand(
                service: "recorder-ingress",
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
    }

    func testParsesVitalDBReadCommandsWithExplicitGuestControlURL() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "vitaldb-observation",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .vitalDB(RuntimeVitalDBReadCommand(
                action: .observation,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "vitaldb-recorders",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .vitalDB(RuntimeVitalDBReadCommand(
                action: .recorders,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "vitaldb-recorder-activity",
                "VR-001",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .vitalDB(RuntimeVitalDBReadCommand(
                action: .recorderActivity("VR-001"),
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "vitaldb-beds",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .vitalDB(RuntimeVitalDBReadCommand(
                action: .beds,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "vitaldb-relationships",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .vitalDB(RuntimeVitalDBReadCommand(
                action: .relationships,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
    }

    func testParsesLabSessionCreateCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "lab-beds",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .lab(RuntimeLabControlCommand(
                action: .beds,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "lab-recorders",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .lab(RuntimeLabControlCommand(
                action: .recorders,
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "lab-session-create",
                "routine-case",
                "--name",
                "Morning lab run",
                "--recorder-count",
                "3",
                "--target-url",
                "http://edge/",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .lab(RuntimeLabControlCommand(
                action: .createSession(RuntimeLabSessionCreateRequest(
                    scenarioId: "routine-case",
                    name: "Morning lab run",
                    recorderCount: 3,
                    targetURL: "http://edge/"
                )),
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
    }

    func testParsesLabSessionCommandsWithExplicitGuestControlURL() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "lab-session-get",
                "session-1",
                "--guest-control-url",
                "http://192.168.64.2:18330",
            ]),
            .lab(RuntimeLabControlCommand(
                action: .getSession("session-1"),
                guestControlBaseURL: "http://192.168.64.2:18330"
            ))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-session-start", "session-1"]),
            .lab(RuntimeLabControlCommand(action: .startSession("session-1")))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-session-stop", "session-1"]),
            .lab(RuntimeLabControlCommand(action: .stopSession("session-1")))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["lab-session-finish", "session-1"]),
            .lab(RuntimeLabControlCommand(action: .finishSession("session-1")))
        )
    }

    func testParsesLabVitalReplayCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse([
                "lab-vital-replay",
                "sample.vital",
                "--session-name",
                "Replay run",
                "--target-url",
                "http://edge/",
            ]),
            .lab(RuntimeLabControlCommand(
                action: .replayVitalFile(RuntimeLabVitalFileReplayRequest(
                    vitalFileRelativePath: "sample.vital",
                    sessionName: "Replay run",
                    targetURL: "http://edge/",
                    resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
                    repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
                ))
            ))
        )
    }

    func testBundleCommandsRequirePath() {
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["verify-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime verify-bundle <bundle.tar.gz>"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["stage-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["apply-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz>"
        )
    }

    func testLabCommandsRequireExplicitInputs() {
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["lab-session-create"]),
            expectedMessage: "usage: vitalserver-vm runtime lab-session-create <scenario-id> [--name <name>] [--recorder-count <count>] [--target-url <url>] [--guest-control-url <url>]"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["lab-session-get"]),
            expectedMessage: "usage: vitalserver-vm runtime lab-session-get <session-id> [--guest-control-url <url>]"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["lab-vital-replay"]),
            expectedMessage: "usage: vitalserver-vm runtime lab-vital-replay <vital-file-relative-path> [--session-name <name>] [--target-url <url>] [--guest-control-url <url>]"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["lab-session-create", "routine-case", "--recorder-count", "0"]),
            expectedMessage: "--recorder-count must be a positive integer"
        )
    }

    func testConfigureRejectsMissingValueAndInvalidClosedChoice() {
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--cpu"]),
            expectedMessage: "missing value for --cpu"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--network", "host"]),
            expectedMessage: "--network must be `shared` or `bridged`"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--start-on-boot", "sometimes"]),
            expectedMessage: "--start-on-boot must be true or false"
        )
    }

    func testUnsupportedCommandIncludesRuntimePrefix() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["unknown"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.unsupportedCommand("runtime unknown"))
            )
        }
    }

    func testUsageListsRuntimeCommands() {
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime install"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime install-provision"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime preinstall-check"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime apply-bundle <bundle.tar.gz>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime redis-backup"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime repair-vm-disk"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime repair-proxy"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime repair-services"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime stop-services"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime guest-stack-status"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime guest-service-start <service>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime guest-service-stop <service>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime guest-service-restart <service>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime vitaldb-observation"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime vitaldb-recorders"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime vitaldb-recorder-activity <vrcode>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime vitaldb-beds"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime vitaldb-relationships"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime lab-scenarios"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime lab-beds"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime lab-recorders"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime lab-session-create <scenario-id>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime lab-vital-replay <vital-file-path>"))
        XCTAssertTrue(
            RuntimeLifecycleCommand.usage.contains(
                "vitalserver-vm runtime uninstall [--clean|--force-clean|--force-clean-uninstaller]"
            )
        )
    }

    private func assertMissingArgument(
        _ expression: @autoclosure () throws -> RuntimeLifecycleCommand,
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.missingArgument(expectedMessage)),
                file: file,
                line: line
            )
        }
    }
}
