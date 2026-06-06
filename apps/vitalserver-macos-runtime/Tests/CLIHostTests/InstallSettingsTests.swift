import Foundation
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class InstallSettingsTests: XCTestCase {
    func testLoadPreservesExplicitSSHAuthorizedKeys() throws {
        let fileStore = RuntimeFileStoreSpy()
        let settingsURL = URL(fileURLWithPath: "/tmp/install-settings.json")
        fileStore.files[settingsURL] = Data("""
        {
          "sshAuthorizedKeys": [
            "  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test  ",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQexample"
          ]
        }
        """.utf8)

        let settings = try RuntimeInstallSettings.load(
            path: settingsURL.path,
            defaultVitalFilesDirectory: "/vital-files",
            fileStore: fileStore
        )

        XCTAssertEqual(settings.sshAuthorizedKeys, [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexample operator@example.test",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQexample",
        ])
    }

    func testLoadFailsForInvalidSSHAuthorizedKey() throws {
        let fileStore = RuntimeFileStoreSpy()
        let settingsURL = URL(fileURLWithPath: "/tmp/install-settings.json")
        fileStore.files[settingsURL] = Data("""
        {
          "sshAuthorizedKeys": [
            "not-a-public-key"
          ]
        }
        """.utf8)

        XCTAssertThrowsError(
            try RuntimeInstallSettings.load(
                path: settingsURL.path,
                defaultVitalFilesDirectory: "/vital-files",
                fileStore: fileStore
            )
        ) { error in
            guard case LauncherError.missingArgument(let message) = error else {
                return XCTFail("expected missingArgument, got \(error)")
            }
            XCTAssertEqual(message, "install settings sshAuthorizedKeys[0] must be an OpenSSH public key")
        }
    }
}
