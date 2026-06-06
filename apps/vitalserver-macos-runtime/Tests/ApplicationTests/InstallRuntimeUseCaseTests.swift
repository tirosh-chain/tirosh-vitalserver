import Application
import Contracts
import XCTest

final class InstallRuntimeUseCaseTests: XCTestCase {
    func testInstallDispatchesExplicitRequestThroughPort() throws {
        let harness = Harness()
        let request = InstallRuntimeRequest(
            mode: .full
        )

        try harness.useCase.install(request)

        XCTAssertEqual(harness.requests, [request])
    }

    func testInstallKeepsPortFailureVisible() {
        let useCase = InstallRuntimeUseCase(
            ports: InstallRuntimePorts(runInstall: { _ in
                throw InstallRuntimeUseCaseTestError.installFailed
            })
        )

        XCTAssertThrowsError(try useCase.install(InstallRuntimeRequest(mode: .provision))) { error in
            XCTAssertEqual(error as? InstallRuntimeUseCaseTestError, .installFailed)
        }
    }

    private final class Harness {
        var requests: [InstallRuntimeRequest] = []

        lazy var useCase = InstallRuntimeUseCase(
            ports: InstallRuntimePorts(runInstall: { [unowned self] request in
                requests.append(request)
            })
        )
    }
}

private enum InstallRuntimeUseCaseTestError: Error, Equatable {
    case installFailed
}
