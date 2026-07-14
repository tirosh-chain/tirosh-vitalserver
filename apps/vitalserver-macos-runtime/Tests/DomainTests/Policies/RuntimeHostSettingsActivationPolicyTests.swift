import Domain
import XCTest

final class RuntimeHostSettingsActivationPolicyTests: XCTestCase {
    private let policy = RuntimeHostSettingsActivationPolicy()

    func testDesiredRevisionRequiresExactCurrentRevision() throws {
        XCTAssertEqual(try policy.importRevision(currentRevision: nil), 1)
        XCTAssertEqual(try policy.nextDesiredRevision(currentRevision: 1, expectedRevision: 1), 2)
        XCTAssertThrowsError(try policy.nextDesiredRevision(currentRevision: 2, expectedRevision: 1)) { error in
            XCTAssertEqual(
                error as? RuntimeHostSettingsActivationError,
                .staleRevision(expected: 1, actual: 2)
            )
        }
    }

    func testApplyRequiresSameMaterializedRevisionAndBootRun() throws {
        let state = RuntimeHostSettingsActivationState(
            revision: 2,
            materializedRevision: 2,
            bootRevision: 2,
            bootRunID: "run-2"
        )

        XCTAssertNoThrow(try policy.requireBoot(state: state, revision: 2, runID: "run-2"))
        XCTAssertNoThrow(try policy.requireApply(state: state, revision: 2, runID: "run-2"))
        XCTAssertThrowsError(try policy.requireApply(state: state, revision: 2, runID: "run-old")) { error in
            XCTAssertEqual(
                error as? RuntimeHostSettingsActivationError,
                .bootMismatch(
                    expectedRevision: 2,
                    actualRevision: 2,
                    expectedRunID: "run-old",
                    actualRunID: "run-2"
                )
            )
        }
    }
}
