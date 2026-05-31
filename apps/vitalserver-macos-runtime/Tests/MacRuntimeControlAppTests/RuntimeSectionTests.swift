@testable import MacRuntimeControlApp
import RuntimeControl
import XCTest

final class RuntimeSectionTests: XCTestCase {
    func testStableRuntimeSectionsHideTestTab() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: false).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testTestkitRuntimeSectionsIncludeTestTabBeforeDangerZone() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: true).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionTest,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testRuntimeSectionsExposePrimaryUtilityAndOverflowGroups() {
        XCTAssertEqual(RuntimeSection.primarySections(testEnabled: true), [
            .status,
            .recorders,
            .beds,
            .observability,
            .log,
            .settings,
            .update,
        ])
        XCTAssertEqual(RuntimeSection.utilitySections(testEnabled: true), [.advanced])
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: true), [.info, .dangerZone, .test])
    }

    func testStableRuntimeSectionOverflowHidesTestTab() {
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: false), [.info, .dangerZone])
        XCTAssertTrue(RuntimeSection.sectionIsInOverflow(.dangerZone, testEnabled: false))
        XCTAssertFalse(RuntimeSection.sectionIsInOverflow(.advanced, testEnabled: false))
    }

    @MainActor
    func testRuntimeControlDevConsoleURLUsesLocalAPI() {
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.devConsoleURL,
            "http://127.0.0.1:18321/dev/runtime-control"
        )
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.pwaURL,
            "http://127.0.0.1:18321/"
        )
    }

    @MainActor
    func testRuntimeControlLocalAPISettingsPersistConfiguredPort() {
        let store = InMemoryRuntimeControlLocalAPISettingsStore()
        let coordinator = RuntimeControlLocalAPISettingsCoordinator(store: store)
        var changedPorts: [Int] = []
        coordinator.onPortChanged = { changedPorts.append($0) }

        coordinator.apply(port: 18_444)
        let settings = coordinator.settingsWithLocalAPIPort(RuntimeSettings())

        XCTAssertEqual(store.runtimeControlPort, 18_444)
        XCTAssertEqual(settings.runtimeControlPort, 18_444)
        XCTAssertEqual(changedPorts, [18_444])
    }

    @MainActor
    func testRuntimeControlAPIServerIsIndependentFromTestTools() {
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldStartRuntimeControlAPIServer())
        XCTAssertFalse(MacRuntimeControlEnvironment.shouldServeRuntimeControlTestTools(testEnabled: false))
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldServeRuntimeControlTestTools(testEnabled: true))
    }
}
