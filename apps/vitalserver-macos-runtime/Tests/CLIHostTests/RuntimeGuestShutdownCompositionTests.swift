import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeGuestShutdownCompositionTests: XCTestCase {
    func testShutdownCompositionExecutesShutdownPlanThroughBootstrapEffects() throws {
        let guestRunDirectory = URL(fileURLWithPath: "/product/guest/run")
        var operationReads = [
            updateShutdownOperation(state: .completed, shutdownPhase: "poweroff-ready"),
        ]
        var events: [String] = []
        var statuses: [(RuntimeStatusLevel, RuntimeOperation, String)] = []
        var logs: [String] = []
        let composition = RuntimeGuestShutdownComposition(
            context: RuntimeGuestShutdownCompositionContext(guestRunDirectory: guestRunDirectory),
            operations: RuntimeGuestShutdownCompositionOperations(
                requireCapability: { events.append("capability") },
                prepareUpdateShutdown: { requestID, version in
                    events.append("prepare:\(requestID):\(version)")
                    return updateShutdownOperation(state: .running)
                },
                loadOperation: { operationID in
                    events.append("load-operation:\(operationID)")
                    return operationReads.removeFirst()
                },
                requestGuestPoweroff: {
                    events.append("poweroff")
                    return RuntimeGuestControlServiceOperation(
                        operationId: "guest-poweroff-1",
                        service: "guest-poweroff",
                        command: .requestGuestPoweroff,
                        state: .completed,
                        createdAt: "2026-07-01T00:00:00+00:00",
                        updatedAt: "2026-07-01T00:00:01+00:00"
                    )
                },
                writeStatus: { level, operation, message in
                    statuses.append((level, operation, message))
                },
                requestID: { "request-1" },
                sleep: { events.append("sleep") },
                log: { logs.append($0) }
            )
        )

        try composition.prepareForUpdate(manifest: manifest())

        XCTAssertTrue(events.contains("capability"))
        XCTAssertTrue(events.contains("prepare:request-1:1.2.3"))
        XCTAssertTrue(events.contains("poweroff"))
        XCTAssertEqual(events.filter { $0 == "sleep" }.count, 1)
        XCTAssertTrue(statuses.contains {
            $0.0 == .updating &&
                $0.1 == .applyBundle &&
                $0.2 == "guest update shutdown operation running"
        })
        XCTAssertTrue(logs.contains("guest update shutdown requested version=1.2.3"))
        XCTAssertTrue(logs.contains("guest update shutdown operation completed operationId=update-shutdown-1"))
        XCTAssertTrue(logs.contains("guest poweroff requested operationId=guest-poweroff-1"))
        XCTAssertTrue(logs.contains("guest update shutdown ready version=1.2.3"))
    }

    private func manifest() -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "1.2.3"],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: [],
            migrations: []
        )
    }

}

private func updateShutdownOperation(
    state: RuntimeGuestControlOperationState,
    shutdownPhase: String? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: "update-shutdown-1",
        service: "update-shutdown",
        command: .updateShutdown,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        result: shutdownPhase.map {
            RuntimeGuestControlOperationResult(shutdownPhase: $0)
        }
    )
}
