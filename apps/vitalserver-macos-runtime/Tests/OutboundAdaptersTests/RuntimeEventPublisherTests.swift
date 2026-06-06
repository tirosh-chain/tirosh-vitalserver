import Contracts
import Application
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeEventPublisherTests: XCTestCase {
    func testRecordObservedEventWritesFactoryEvent() throws {
        let harness = RuntimeEventPublisherHarness()
        let snapshot = RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: [],
            vmIP: "192.168.64.2",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: []
        )

        try harness.publisher.recordObservedEvent(
            .healthy,
            previousStatus: .degraded,
            operation: .watchdog,
            message: "runtime recovered",
            healthSnapshot: snapshot,
            eventType: .statusChanged
        )

        XCTAssertEqual(harness.events.count, 1)
        XCTAssertEqual(harness.events.first?.eventType, .statusChanged)
        XCTAssertEqual(harness.events.first?.status, .healthy)
        XCTAssertEqual(harness.events.first?.previousStatus, .degraded)
        XCTAssertEqual(harness.events.first?.vmState, .running)
    }

    func testRecordCommandEventBestEffortFormatsCommandContext() {
        let harness = RuntimeEventPublisherHarness()

        harness.publisher.recordCommandEventBestEffort(
            .runtimeCommandCompleted,
            executable: "/bin/launchctl",
            arguments: ["kickstart", "system/ai.tirosh.vitalserver.helper"],
            result: RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
        )

        XCTAssertEqual(harness.events.count, 1)
        XCTAssertEqual(harness.events.first?.source, "host-command")
        XCTAssertEqual(harness.events.first?.eventType, .runtimeCommandCompleted)
        XCTAssertEqual(
            harness.events.first?.message,
            "command runtime-command-completed executable=/bin/launchctl arguments=kickstart system/ai.tirosh.vitalserver.helper exitCode=0"
        )
    }

    func testRecordProgressEventBestEffortCarriesProgressDocument() {
        let harness = RuntimeEventPublisherHarness()
        let progress = RuntimeProgressDocument(
            operation: .applyBundle,
            phase: .running,
            step: .stopRuntimeServices,
            stepStatus: .started,
            message: "stopping services",
            reasonCodes: [],
            startedAt: nil,
            updatedAt: "2026-05-30T00:00:02Z"
        )

        harness.publisher.recordProgressEventBestEffort(
            status: .updating,
            message: "stopping services",
            progress: progress
        )

        XCTAssertEqual(harness.events.count, 1)
        XCTAssertEqual(harness.events.first?.eventType, .progressUpdated)
        XCTAssertEqual(harness.events.first?.timestamp, "2026-05-30T00:00:02Z")
        XCTAssertEqual(harness.events.first?.status, .updating)
        XCTAssertEqual(harness.events.first?.progress?.step, .stopRuntimeServices)
    }
}

private final class RuntimeEventPublisherHarness {
    private let repository = InMemoryRuntimeEventRecorder()

    var events: [RuntimeEventDocument] {
        repository.events
    }

    var publisher: RuntimeEventPublisher {
        RuntimeEventPublisher(
            factory: RuntimeEventFactory(
                id: { "event-\(self.repository.events.count + 1)" },
                timestamp: { "2026-05-30T00:00:01Z" },
                product: "VitalServerHelper",
                runtimeVersion: { "1.2.3" }
            ),
            recorder: RuntimeObservationRecorder(
                eventRepository: repository,
                log: { _ in }
            )
        )
    }
}

private final class InMemoryRuntimeEventRecorder: RuntimeEventRecording {
    var events: [RuntimeEventDocument] = []

    func append(_ event: RuntimeEventDocument) throws {
        events.append(event)
    }
}
