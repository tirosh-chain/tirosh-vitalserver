import Foundation
import Network
import XCTest
@testable import MacPlatformAgent

final class RuntimeHostNTPServerTests: XCTestCase {
    func testServesNTPOnlyOnConfiguredAddressAndPort() throws {
        let ready = expectation(description: "NTP server ready")
        let responseReceived = expectation(description: "NTP response received")
        let state = LockedNTPServerState()
        let server = RuntimeHostNTPServer(
            configuration: .init(
                bindAddress: "127.0.0.1",
                port: 0,
                allowedClientAddress: "127.0.0.1"
            ),
            stateHandler: { value in
                state.set(value)
                if case .ready = value {
                    ready.fulfill()
                }
            }
        )
        try server.start()
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(server.activePort)

        let client = NWConnection(
            host: "127.0.0.1",
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: port)),
            using: .udp
        )
        let queue = DispatchQueue(label: "tirosh.runtime.host-ntp.test-client")
        client.stateUpdateHandler = { connectionState in
            guard case .ready = connectionState else {
                return
            }
            var request = [UInt8](repeating: 0, count: 48)
            request[0] = (4 << 3) | 3
            request[40] = 1
            client.send(content: Data(request), completion: .contentProcessed { error in
                XCTAssertNil(error)
                client.receiveMessage { data, _, _, receiveError in
                    XCTAssertNil(receiveError)
                    let response = data.map([UInt8].init)
                    XCTAssertEqual(response?.count, 48)
                    XCTAssertEqual(response.map { $0[0] & 0b111 }, 4)
                    XCTAssertEqual(response?[1], 10)
                    XCTAssertEqual(response?[24], 1)
                    responseReceived.fulfill()
                }
            })
        }
        client.start(queue: queue)

        wait(for: [responseReceived], timeout: 3)
        client.cancel()
        server.stop()
        XCTAssertNotNil(state.value)
    }
}

private final class LockedNTPServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RuntimeHostNTPServerState?

    var value: RuntimeHostNTPServerState? {
        lock.withLock { stored }
    }

    func set(_ value: RuntimeHostNTPServerState) {
        lock.withLock {
            stored = value
        }
    }
}
