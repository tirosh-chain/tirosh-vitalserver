@testable import MacRuntimeControlApp
import XCTest

final class RuntimeSectionTests: XCTestCase {
    func testStableRuntimeSectionsHideTestTab() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: false).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionEvents,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testTestkitRuntimeSectionsIncludeTestTabAfterEvents() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: true).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionEvents,
            AppConstants.Labels.sectionTest,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
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
