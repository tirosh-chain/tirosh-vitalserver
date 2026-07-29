import Contracts
import Domain
@testable import MacPlatformAgent
import XCTest

@MainActor
final class RuntimeHostNTPControllerTests: XCTestCase {
    func testPublishesUnavailableWithoutInventingServerAddress() {
        var documents: [RuntimeTimeAuthorityDocument] = []
        let controller = RuntimeHostNTPController(
            guestAddress: { .missing("VM endpoint is not available") },
            interfaces: { [] },
            writeContract: { documents.append($0) },
            interval: 60
        )

        controller.refresh()

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].state, .unavailable)
        XCTAssertNil(documents[0].serverAddress)
        XCTAssertNil(documents[0].serverPort)
        XCTAssertEqual(
            documents[0].issue,
            "Guest address state is missing: VM endpoint is not available"
        )
    }

    func testPublishesReadyListenerFromExplicitGuestSubnet() async {
        var documents: [RuntimeTimeAuthorityDocument] = []
        let server = RuntimeHostNTPServerSpy()
        let controller = RuntimeHostNTPController(
            guestAddress: {
                .loaded(
                    address: "192.168.64.3",
                    source: .platformAgent
                )
            },
            interfaces: {
                [
                    RuntimeIPv4InterfaceAddress(
                        name: "bridge100",
                        address: "192.168.64.1",
                        netmask: "255.255.255.0"
                    )
                ]
            },
            writeContract: { documents.append($0) },
            interval: 60,
            makeServer: { configuration, _, handler in
                server.configuration = configuration
                server.stateHandler = handler
                return server
            }
        )

        controller.refresh()
        await Task.yield()

        XCTAssertEqual(server.configuration?.bindAddress, "192.168.64.1")
        XCTAssertEqual(server.configuration?.allowedClientAddress, "192.168.64.3")
        XCTAssertEqual(documents.last?.state, .hostClockOnly)
        XCTAssertEqual(documents.last?.serverAddress, "192.168.64.1")
        XCTAssertEqual(documents.last?.allowedClientAddress, "192.168.64.3")
    }
}

private final class RuntimeHostNTPServerSpy: RuntimeHostNTPServing, @unchecked Sendable {
    var configuration: RuntimeHostNTPServerConfiguration?
    var stateHandler: (@Sendable (RuntimeHostNTPServerState) -> Void)?

    func start() throws {
        guard let configuration else {
            XCTFail("server configuration was not provided")
            return
        }
        stateHandler?(.ready(
            address: configuration.bindAddress,
            port: configuration.port
        ))
    }

    func stop() {}
}
