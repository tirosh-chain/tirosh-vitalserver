import Contracts
import Application
import Bootstrap
@testable import CLIHost
import XCTest

final class RuntimeGuestCapabilityCheckerTests: XCTestCase {
    func testRequirePassesWhenCapabilityIsSupported() throws {
        try RuntimeGuestCapabilityCheckerComposition.require(
            .prepareUpdateShutdown,
            guestControlGateway: RuntimeGuestCapabilityGatewaySpy(result: .loaded(supportedCapabilities()))
        )
    }

    func testRequireFailsWhenCapabilityIsMissingFromGuestControlCapabilities() {
        let gateway = RuntimeGuestCapabilityGatewaySpy(
            result: .loaded(RuntimeGuestControlCapabilities(
                schemaVersion: 1,
                capabilities: ["services:list"]
            ))
        )

        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .prepareUpdateShutdown,
            guestControlGateway: gateway
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenGuestControlCapabilitiesCannotBeLoaded() {
        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .activateUpdate,
            guestControlGateway: RuntimeGuestCapabilityGatewaySpy(result: .failed("permission denied"))
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest capabilities for activate-update: permission denied"
            )
        }
    }
}

private func supportedCapabilities() -> RuntimeGuestControlCapabilities {
    RuntimeGuestControlCapabilities(
        schemaVersion: 1,
        capabilities: [
            "maintenance:update-shutdown:create",
            "maintenance:update-activation:create",
            "maintenance:redis-backup:create",
            "maintenance:redis-restore:create",
            "maintenance:datastore-repair:create",
        ]
    )
}

private final class RuntimeGuestCapabilityGatewaySpy: RuntimeGuestControlGateway {
    let result: RuntimeGuestCapabilityReadResult

    init(result: RuntimeGuestCapabilityReadResult) {
        self.result = result
    }

    func capabilities() throws -> RuntimeGuestControlCapabilities {
        switch result {
        case .loaded(let capabilities):
            return capabilities
        case .failed(let message):
            throw RuntimeGuestCapabilityGatewayError(message)
        }
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        throw RuntimeGuestCapabilityGatewayError("unexpected listServices")
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        throw RuntimeGuestCapabilityGatewayError("unexpected stackStatus")
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        throw RuntimeGuestCapabilityGatewayError("unexpected serviceStatus \(service)")
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestCapabilityGatewayError("unexpected startService \(service)")
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestCapabilityGatewayError("unexpected stopService \(service)")
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestCapabilityGatewayError("unexpected restartService \(service)")
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestCapabilityGatewayError("unexpected reconcileServices")
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeGuestCapabilityGatewayError("unexpected operation \(operationId)")
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        throw RuntimeGuestCapabilityGatewayError("unexpected latestVitalDBObservation")
    }
}

private struct RuntimeGuestCapabilityGatewayError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
