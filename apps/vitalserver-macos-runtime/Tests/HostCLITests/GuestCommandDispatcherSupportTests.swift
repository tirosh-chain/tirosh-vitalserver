import Foundation
import XCTest

final class GuestCommandDispatcherSupportTests: XCTestCase {
    func testGuestCommandPollerDispatchesAllHostWrittenRequests() throws {
        let poller = try readGuestSupportFile("bin/tirosh-vitalserver-command-poller")

        XCTAssertTrue(poller.contains("POLL_INTERVAL_SECONDS=\"${TIROSH_GUEST_COMMAND_POLL_INTERVAL_SECONDS:-3}\""))
        XCTAssertTrue(poller.contains("prepare-update-shutdown.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-prepare-update-shutdown.service"))
        XCTAssertTrue(poller.contains("activate-update.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-activate-update.service"))
        XCTAssertTrue(poller.contains("repair-datastore.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-repair-datastore.service"))
        XCTAssertTrue(poller.contains("redis-backup.request"))
        XCTAssertTrue(poller.contains("tirosh-vitalserver-redis-backup.service"))
        XCTAssertTrue(poller.contains("systemctl start --no-block"))
        XCTAssertFalse(poller.contains("PathExists="))
    }

    func testBootstrapAndActivationInstallPollerInsteadOfEnablingPathWatchers() throws {
        let bootstrap = try readGuestSupportFile("bootstrap.sh")
        let activation = try readGuestSupportFile("bin/tirosh-vitalserver-activate-update")

        for installer in [bootstrap, activation] {
            XCTAssertTrue(installer.contains("install -m 0755 \"${DEPLOY_DIR}/bin/tirosh-vitalserver-command-poller\""))
            XCTAssertTrue(installer.contains("install -m 0644 \"${DEPLOY_DIR}/systemd/tirosh-vitalserver-command-poller.service\""))
            XCTAssertTrue(installer.contains("systemctl enable --now tirosh-vitalserver-command-poller.service"))

            XCTAssertTrue(installer.contains("systemctl disable --now tirosh-vitalserver-redis-backup.path"))
            XCTAssertTrue(installer.contains("systemctl disable --now tirosh-vitalserver-repair-datastore.path"))
            XCTAssertTrue(installer.contains("systemctl disable --now tirosh-vitalserver-activate-update.path"))
            XCTAssertTrue(installer.contains("systemctl disable --now tirosh-vitalserver-prepare-update-shutdown.path"))

            XCTAssertFalse(installer.contains("systemctl enable --now tirosh-vitalserver-redis-backup.path"))
            XCTAssertFalse(installer.contains("systemctl enable --now tirosh-vitalserver-repair-datastore.path"))
            XCTAssertFalse(installer.contains("systemctl enable --now tirosh-vitalserver-activate-update.path"))
            XCTAssertFalse(installer.contains("systemctl enable --now tirosh-vitalserver-prepare-update-shutdown.path"))
        }
    }

    func testGuestCommandFailuresClearRequestFilesAfterWritingFailureResult() throws {
        let activation = try readGuestSupportFile("bin/tirosh-vitalserver-activate-update")
        let shutdown = try readGuestSupportFile("bin/tirosh-vitalserver-prepare-update-shutdown")
        let repair = try readGuestSupportFile("bin/tirosh-vitalserver-repair-datastore")

        XCTAssertTrue(activation.contains("rm -f \"${REQUEST_FILE}\"\n    write_result \"failed\""))
        XCTAssertTrue(shutdown.contains("write_result \"failed\""))
        XCTAssertTrue(shutdown.contains("rm -f \"${REQUEST_FILE}\""))
        XCTAssertTrue(repair.contains("rm -f \"${REQUEST_FILE}\"\n    write_result \"failed\""))
    }

    private func readGuestSupportFile(_ relativePath: String) throws -> String {
        let fileURL = try guestSupportDirectory().appendingPathComponent(relativePath)
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
}
