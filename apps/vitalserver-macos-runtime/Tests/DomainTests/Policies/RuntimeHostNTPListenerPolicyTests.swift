import Contracts
import XCTest
@testable import Domain

final class RuntimeHostNTPListenerPolicyTests: XCTestCase {
    func testSelectsOnlyHostInterfaceOnExplicitGuestSubnet() {
        let result = RuntimeHostNTPListenerPolicy.select(
            guestAddress: "192.168.64.3",
            interfaces: [
                .init(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0"),
                .init(name: "en0", address: "192.168.219.140", netmask: "255.255.255.0"),
                .init(name: "bridge100", address: "192.168.64.1", netmask: "255.255.255.0"),
            ]
        )

        XCTAssertEqual(
            result,
            .selected(.init(
                interfaceName: "bridge100",
                hostAddress: "192.168.64.1",
                allowedGuestAddress: "192.168.64.3"
            ))
        )
    }

    func testDoesNotGuessWhenGuestAddressIsInvalidOrSubnetIsAmbiguous() {
        XCTAssertEqual(
            RuntimeHostNTPListenerPolicy.select(
                guestAddress: "not-an-ip",
                interfaces: []
            ),
            .unavailable(reason: "Guest address is not valid IPv4: not-an-ip")
        )

        let ambiguous = RuntimeHostNTPListenerPolicy.select(
            guestAddress: "192.168.64.3",
            interfaces: [
                .init(name: "bridge100", address: "192.168.64.1", netmask: "255.255.255.0"),
                .init(name: "bridge101", address: "192.168.64.2", netmask: "255.255.255.0"),
            ]
        )
        XCTAssertEqual(
            ambiguous,
            .unavailable(reason: "Multiple Host interfaces share the explicit Guest subnet")
        )
    }

    func testReportsUnavailableWhenNoHostInterfaceOwnsGuestSubnet() {
        XCTAssertEqual(
            RuntimeHostNTPListenerPolicy.select(
                guestAddress: "192.168.64.3",
                interfaces: [
                    .init(name: "en0", address: "192.168.219.140", netmask: "255.255.255.0")
                ]
            ),
            .unavailable(reason: "No Host interface shares the explicit Guest subnet")
        )
    }
}
