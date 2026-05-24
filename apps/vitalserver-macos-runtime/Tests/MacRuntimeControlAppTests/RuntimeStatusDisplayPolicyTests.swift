import Contracts
import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeStatusDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeStatusDisplayPolicy()

    func testHealthDetailsOwnServiceUptimeMappingAndFormatting() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200",
            redisUIHTTP: "503"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 3_661),
                RuntimeContainerServiceObservation(service: "edge", uptimeSeconds: 60),
                RuntimeContainerServiceObservation(service: "redis", state: "running", health: "healthy", uptimeSeconds: 5),
            ]
        )

        let items = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "1h 1m 1s")
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.value.uptimeText, "0h 1m 0s")
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.text, "healthy")
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.severity, .healthy)
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.uptimeText, "0h 0m 5s")
    }

    func testAdvancedServiceHealthOwnsLabelsActionsAndHTTPStatusDisplay() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "503",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 1),
                RuntimeContainerServiceObservation(service: "edge", uptimeSeconds: 2),
                RuntimeContainerServiceObservation(service: "redis-ui", uptimeSeconds: 3),
                RuntimeContainerServiceObservation(service: "swagger-ui", uptimeSeconds: 4),
            ]
        )

        let items = policy.advancedServiceHealth(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.action, .openVitalServer)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "0h 0m 1s")
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.httpStatus, "503")
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: items)?.action, .openRedisUI)
        XCTAssertEqual(item(GeneratedRelease.swaggerUIName, in: items)?.action, .openSwagger)
    }

    func testRecorderSummaryOwnsRecorderDisplayText() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(
                activeRecorderConnections: 2,
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_OLD",
                        activeConnections: 1,
                        selectedIp: nil,
                        lastSeenAt: "2026-05-24T00:00:00Z"
                    ),
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_NEW",
                        activeConnections: 1,
                        selectedIp: "192.168.64.10",
                        lastSeenAt: "2026-05-24T01:00:00Z"
                    ),
                ]
            ),
            containerLogsPresent: true,
            containerLogsBytes: 1
        )

        let summary = policy.recorderSummary(observation: observation)

        XCTAssertEqual(summary.activeConnections, "2")
        XCTAssertEqual(summary.knownRecorders, "2")
        XCTAssertEqual(summary.latestRecorder, "VR_NEW 192.168.64.10")
    }

    private func item(
        _ label: String,
        in items: [RuntimeStatusDisplayPolicy.HealthItem]
    ) -> RuntimeStatusDisplayPolicy.HealthItem? {
        items.first { $0.label == label }
    }

    private func item(
        _ label: String,
        in items: [RuntimeStatusDisplayPolicy.ServiceHealthItem]
    ) -> RuntimeStatusDisplayPolicy.ServiceHealthItem? {
        items.first { $0.label == label }
    }
}
