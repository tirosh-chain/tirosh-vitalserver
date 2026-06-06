import Application
import Foundation
import XCTest

final class ConfigureRuntimeUseCaseTests: XCTestCase {
    func testConfigureDispatchesExplicitRequestThroughPort() throws {
        let harness = Harness()
        let request = ConfigureRuntimeRequest<TestNetworkMode>(
            changes: [
                .cpu(4),
                .memoryGiB(8),
                .network(.shared),
                .vitalServerURL("https://vitaldb.tirosh.ai/"),
                .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
            ],
            restart: true
        )

        let result = try harness.useCase.configure(request)

        XCTAssertEqual(result, ConfigureRuntimeResult(restart: true))
        XCTAssertEqual(harness.requests, [request])
    }

    func testConfigureKeepsPortFailureVisible() {
        let useCase = ConfigureRuntimeUseCase<TestNetworkMode>(
            ports: ConfigureRuntimePorts(applyConfiguration: { _ in
                throw ConfigureRuntimeUseCaseTestError.invalidConfig
            })
        )

        XCTAssertThrowsError(try useCase.configure(ConfigureRuntimeRequest())) { error in
            XCTAssertEqual(error as? ConfigureRuntimeUseCaseTestError, .invalidConfig)
        }
    }

    private final class Harness {
        var requests: [ConfigureRuntimeRequest<TestNetworkMode>] = []

        lazy var useCase = ConfigureRuntimeUseCase<TestNetworkMode>(
            ports: ConfigureRuntimePorts(applyConfiguration: { [unowned self] request in
                requests.append(request)
                return ConfigureRuntimeResult(restart: request.restart)
            })
        )
    }
}

private enum TestNetworkMode: Equatable {
    case shared
}

private enum ConfigureRuntimeUseCaseTestError: Error, Equatable {
    case invalidConfig
}
