import Foundation
import XCTest

final class GuestCommandDispatcherSupportTests: XCTestCase {
    func testGuestCommandPollerDispatchesAllHostWrittenRequests() throws {
        let poller = try readGuestToolsFile("operations/command_poller.py")

        XCTAssertTrue(poller.contains("SETTINGS.intervals.command_poll_seconds"))
        XCTAssertTrue(poller.contains("prepare-update-shutdown.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-prepare-update-shutdown.service"))
        XCTAssertTrue(poller.contains("activate-update.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-activate-update.service"))
        XCTAssertTrue(poller.contains("repair-datastore.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-repair-datastore.service"))
        XCTAssertTrue(poller.contains("redis-backup.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-redis-backup.service"))
        XCTAssertTrue(poller.contains("\"start\", \"--no-block\""))
        XCTAssertFalse(poller.contains("PathExists="))
    }

    func testBootstrapInstallsWrappersAndExplicitSystemdFiles() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")

        XCTAssertTrue(bootstrap.contains("install_guest_tools"))
        XCTAssertTrue(bootstrap.contains("install -m 0644 \"${DEPLOY_DIR}/guest-tools.toml\""))
        XCTAssertFalse(bootstrap.contains("tirosh-guest-tools-install-systemd"))
        XCTAssertTrue(bootstrap.contains("systemctl enable --now tirosh-vitalserver-command-poller.service"))
        XCTAssertTrue(bootstrap.contains("install -m 0755 \"${DEPLOY_DIR}/bin/tirosh-vitalserver-command-poller\""))
        XCTAssertTrue(bootstrap.contains("install -m 0644 \"${DEPLOY_DIR}/systemd/tirosh-vitalserver-command-poller.service\""))
        let observabilityUnit = try readGuestSupportFile(
            "systemd/tirosh-guest-observability.service"
        )
        let removedInstaller = try guestToolsDirectory()
            .appendingPathComponent("observability/systemd_installer.py")
        XCTAssertTrue(observabilityUnit.contains("tirosh-guest-observed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedInstaller.path))
    }

    func testGuestCommandFailuresClearRequestFilesAfterWritingFailureResult() throws {
        let activation = try readGuestToolsFile("application/update_activation.py")
        let shutdown = try readGuestToolsFile("application/update_shutdown.py")
        let repair = try readGuestToolsFile("application/redis_repair.py")

        XCTAssertTrue(activation.contains("REQUEST_FILE.unlink(missing_ok=True)"))
        XCTAssertTrue(shutdown.contains("write_result"))
        XCTAssertTrue(shutdown.contains("REQUEST_FILE.unlink(missing_ok=True)"))
        XCTAssertTrue(repair.contains("REQUEST_FILE.unlink(missing_ok=True)"))
    }

    func testGuestToolsBackThinWrappersAndSystemdFiles() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let guestSupport = try guestSupportDirectory()

        XCTAssertTrue(bootstrap.contains("python3 -m venv --clear \"${GUEST_TOOLS_VENV}\""))
        XCTAssertTrue(
            bootstrap.contains(
                "\"${GUEST_TOOLS_VENV}/bin/pip\" install --no-index --no-deps \"${wheel}\""
            )
        )
        XCTAssertTrue(bootstrap.contains("tirosh-guest-observed"))
        XCTAssertTrue(bootstrap.contains("tirosh-runtime-state"))
        XCTAssertTrue(bootstrap.contains("tirosh-vitalserver-activate-update"))
        let activationUseCase = try readGuestToolsFile("application/update_activation.py")
        let shutdownUseCase = try readGuestToolsFile("application/update_shutdown.py")
        XCTAssertTrue(activationUseCase.contains("activation-pre"))
        XCTAssertTrue(activationUseCase.contains("activation-post"))
        XCTAssertTrue(activationUseCase.contains("activation-failure"))
        XCTAssertTrue(shutdownUseCase.contains("shutdown-pre-stop"))
        XCTAssertTrue(shutdownUseCase.contains("shutdown-post-sync"))
        XCTAssertTrue(shutdownUseCase.contains("shutdown-failure"))
        let wrapper = try readGuestSupportFile("bin/tirosh-vitalserver-compose")
        let service = try readGuestSupportFile("systemd/tirosh-vitalserver-compose.service")
        XCTAssertTrue(wrapper.contains("exec /opt/tirosh/guest-tools/venv/bin/"))
        XCTAssertTrue(service.contains("ExecStart=/usr/local/bin/tirosh-vitalserver-compose up"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("guest-tools.toml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: guestSupport.appendingPathComponent("systemd").path))
    }

    private func readGuestSupportFile(_ relativePath: String) throws -> String {
        let fileURL = try guestSupportDirectory().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func readGuestToolsFile(_ relativePath: String) throws -> String {
        let fileURL = try guestToolsDirectory().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func guestSupportDirectory() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("apps/vitalserver-macos-runtime/Support/Guest")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "GuestCommandDispatcherSupportTests", code: 1)
    }

    private func guestToolsDirectory() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("packages/vitalserver-guest-tools/src/tirosh_guest_tools")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "GuestCommandDispatcherSupportTests", code: 2)
    }
}
