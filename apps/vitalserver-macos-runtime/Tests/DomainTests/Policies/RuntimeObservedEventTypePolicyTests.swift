import Contracts
import Application
import Domain
import XCTest
import Errors

final class RuntimeObservedEventTypePolicyTests: XCTestCase {
    func testPrefersVMErrorsOverDomainErrors() {
        let snapshot = runtimeHealthSnapshot(
            vmErrors: [.missingIPAddress],
            failureReasons: [.guestHTTP("503")]
        )

        let eventType = RuntimeObservedEventTypePolicy.eventType(
            for: snapshot,
            defaultEventType: .healthObserved
        )

        XCTAssertEqual(eventType, .vmErrorObserved)
    }

    func testUsesDomainErrorWhenNoVMErrorExists() {
        let snapshot = runtimeHealthSnapshot(failureReasons: [.guestHTTP("503")])

        let eventType = RuntimeObservedEventTypePolicy.eventType(
            for: snapshot,
            defaultEventType: .healthObserved
        )

        XCTAssertEqual(eventType, .domainErrorObserved)
    }

    func testUsesDefaultEventTypeWhenSnapshotHasNoErrors() {
        let snapshot = runtimeHealthSnapshot()

        let eventType = RuntimeObservedEventTypePolicy.eventType(
            for: snapshot,
            defaultEventType: .healthObserved
        )

        XCTAssertEqual(eventType, .healthObserved)
    }

    private func runtimeHealthSnapshot(
        vmErrors: [RuntimeVMError] = [],
        failureReasons: [RuntimeFailureReason] = []
    ) -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: vmErrors,
            vmIP: "192.168.64.2",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: failureReasons
        )
    }
}
