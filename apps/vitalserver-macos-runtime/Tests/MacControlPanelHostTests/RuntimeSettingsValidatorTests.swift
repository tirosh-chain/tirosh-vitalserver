import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

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

        settings = validSettings()
        settings.runtimeControlPort = 65_536

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidPort)
        )
    }

    func testRejectsMissingAdvertisedServiceURLs() {
        var settings = validSettings()
        settings.vitalServerURL = ""

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        )

        settings = validSettings()
        settings.remoteConsoleURL = ""

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        )
    }

    func testRejectsInvalidAdvertisedServiceURLs() {
        var settings = validSettings()
        settings.vitalServerURL = "vitaldb.tirosh.ai"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        )

        settings = validSettings()
        settings.remoteConsoleURL = "ftp://console.tirosh.ai/"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        )

        settings = validSettings()
        settings.vitalServerURL = " https://vitaldb.tirosh.ai/ "

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        )
    }

    func testRejectsRedisBackupRetentionOutsideRange() {
        var settings = validSettings()
        settings.backupRetentionCount = 31

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidRedisBackupRetention)
        )
    }

    func testRejectsInvalidAndDuplicateBackupScheduleTimes() {
        var settings = validSettings()
        settings.backupScheduleTimes = ["26:15"]

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidBackupScheduleTimes)
        )

        settings = validSettings()
        settings.backupScheduleTimes = ["03:15", "03:15"]

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.duplicateBackupScheduleTimes)
        )
    }

    func testRejectsLogArchiveSettingsOutsideRange() {
        var settings = validSettings()
        settings.logArchiveRetentionDays = 31

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidLogArchiveRetention)
        )

        settings = validSettings()
        settings.logArchiveMaximumGiB = 21

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidLogArchiveMaximum)
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

    func testRejectsMacOSProtectedVitalFilesDirectories() {
        for path in [
            "/Users/test/Desktop",
            "/Users/test/Desktop/Vital Files",
            "/Users/test/Documents/Vital Files",
            "/Users/test/Downloads/Vital Files",
            "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Vital Files",
        ] {
            var settings = validSettings()
            settings.vitalFilesDirectory = path

            XCTAssertEqual(
                validator.validate(settings, installedSettings: installedSettings()),
                .invalid(AppConstants.StatusText.vitalFilesDirectoryProtected),
                path
            )
        }
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

    func testRejectsEnabledContainerMemoryLimitsOutsideAllowedRanges() {
        var settings = validSettings()
        settings.memoryGiB = 4
        settings.containerMemoryLimitsEnabled = true
        settings.vitalServerContainerMemoryLimitMiB = 8192

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid("Container memory limits must be within the allowed MiB ranges and total no more than 70% of the VM memory allocation.")
        )

        settings = validSettings()
        settings.containerMemoryLimitsEnabled = true
        settings.recorderIngressContainerMemoryLimitMiB = 64

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid("Container memory limits must be within the allowed MiB ranges and total no more than 70% of the VM memory allocation.")
        )
    }

    func testAllowsContainerMemoryLimitTotalAtDisplayedMaximumPercent() {
        var settings = validSettings()
        settings.memoryGiB = 8
        settings.containerMemoryLimitsEnabled = true
        settings.vitalServerContainerMemoryLimitMiB = 2048
        settings.recorderIngressContainerMemoryLimitMiB = 410
        settings.redisContainerMemoryLimitMiB = 3277

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .valid
        )
    }

    func testAllowsRedisContainerMemoryLimitAboveFormerEightGiBCap() {
        var settings = validSettings()
        settings.memoryGiB = 48
        settings.containerMemoryLimitsEnabled = true
        settings.vitalServerContainerMemoryLimitMiB = 8192
        settings.recorderIngressContainerMemoryLimitMiB = 4096
        settings.redisContainerMemoryLimitMiB = 16_384

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .valid
        )
    }

    func testRejectsInvalidRedisRelayTargetWhenRelayIsEnabled() {
        var settings = validSettings()
        settings.redisRelay.enabled = true
        settings.redisRelay.target.url = ""

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
        )

        settings = validSettings()
        settings.redisRelay.enabled = true
        settings.redisRelay.target.url = "redis://10.0.0.12:0/0"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
        )

        settings = validSettings()
        settings.redisRelay.enabled = true
        settings.redisRelay.target.url = "redis://10.0.0.12:6379/0"
        settings.redisRelay.target.password = "abc\n123"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
        )
    }

    func testAcceptsValidRedisRelayTargetWhenRelayIsEnabled() {
        var settings = validSettings()
        settings.redisRelay.enabled = true
        settings.redisRelay.target.url = "redis://10.0.0.12:6379/0"
        settings.redisRelay.target.username = "default"
        settings.redisRelay.target.password = "secret"

        XCTAssertEqual(
            validator.validate(settings, installedSettings: installedSettings()),
            .valid
        )
    }

    private func validSettings() -> RuntimeSettings {
        var settings = RuntimeSettings()
        settings.diskGiB = 64
        settings.proxyPort = 18080
        settings.publicPort = 80
        settings.vitalFilesDirectory = "/Users/test/Vital Files"
        settings.vitalServerURL = "http://127.0.0.1:18080/"
        settings.remoteConsoleURL = "http://127.0.0.1:18321/"
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
