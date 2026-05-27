@testable import MacRuntimeControlApp
import XCTest

final class RuntimeSectionTests: XCTestCase {
    func testStableRuntimeSectionsHideTestTab() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: false).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
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
            .observability,
            .log,
            .settings,
            .update,
        ])
        XCTAssertEqual(RuntimeSection.utilitySections(testEnabled: true), [.advanced])
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: true), [.info, .test, .dangerZone])
    }

    func testStableRuntimeSectionOverflowHidesTestTab() {
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: false), [.info, .dangerZone])
        XCTAssertTrue(RuntimeSection.sectionIsInOverflow(.dangerZone, testEnabled: false))
        XCTAssertFalse(RuntimeSection.sectionIsInOverflow(.advanced, testEnabled: false))
    }

    func testRuntimeControlDevConsoleURLUsesLocalAPI() {
        XCTAssertEqual(
            AppConstants.RuntimeControlAPI.devConsoleURL,
            "http://127.0.0.1:18321/dev/runtime-control"
        )
    }

    @MainActor
    func testRuntimeControlAPIServerStartsOnlyForDevBuilds() {
        XCTAssertFalse(MacRuntimeControlEnvironment.shouldStartDevelopmentAPIServer(testEnabled: false))
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldStartDevelopmentAPIServer(testEnabled: true))
    }
}
