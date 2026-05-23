import Management
@testable import MacManagerApp
import XCTest

final class RuntimeSettingsValidatorTests: XCTestCase {
    private let validator = RuntimeSettingsValidator()

    func testAcceptsValidSettings() {
        XCTAssertEqual(validator.validate(validSettings(), installedSettings: installedSettings()), .valid)
    }

    func testRejectsBridgedNetworkMode() {
        var settings = validSettings()
        settings.networkMode = RuntimeNetworkMode.bridged

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.bridgedModeUnavailable)
        )
    }

    func testRejectsDiskDecreaseBelowInstalledDisk() {
        var settings = validSettings()
        settings.diskGiB = 63

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.diskDecreaseUnavailable)
        )
    }

    func testRejectsPortsOutsideValidRange() {
        var settings = validSettings()
        settings.proxyPort = 0

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidPort)
        )

        settings = validSettings()
        settings.publicPort = 65_536

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidPort)
        )
    }

    func testRejectsMissingOrRelativeVitalFilesDirectory() {
        var settings = validSettings()
        settings.vitalFilesDirectory = "   "

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.vitalFilesDirectoryRequired)
        )

        settings = validSettings()
        settings.vitalFilesDirectory = "relative/path"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.vitalFilesDirectoryRequired)
        )
    }

    func testRejectsInvalidAdminPasswordResetValue() {
        var settings = validSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = ""

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.adminPasswordRequired)
        )

        settings.adminPassword = "abc\n123"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.adminPasswordNewline)
        )
    }

    private func validSettings() -> RuntimeSettings {
        var settings = RuntimeSettings()
        settings.diskGiB = 64
        settings.proxyPort = 18080
        settings.publicPort = 80
        settings.vitalFilesDirectory = "/Users/test/Vital Files"
        settings.networkMode = RuntimeNetworkMode.shared
        settings.changeAdminPassword = false
        settings.adminPassword = ""
        return settings
    }

    private func installedSettings() -> RuntimeSettings {
        var settings = RuntimeSettings()
        settings.diskGiB = 64
        return settings
    }
}
