import Contracts

public struct RuntimeHostNTPListenerSelection: Equatable, Sendable {
    public let interfaceName: String
    public let hostAddress: String
    public let allowedGuestAddress: String

    public init(
        interfaceName: String,
        hostAddress: String,
        allowedGuestAddress: String
    ) {
        self.interfaceName = interfaceName
        self.hostAddress = hostAddress
        self.allowedGuestAddress = allowedGuestAddress
    }
}

public enum RuntimeHostNTPListenerSelectionResult: Equatable, Sendable {
    case selected(RuntimeHostNTPListenerSelection)
    case unavailable(reason: String)
}

public enum RuntimeHostNTPListenerPolicy {
    public static func select(
        guestAddress: String,
        interfaces: [RuntimeIPv4InterfaceAddress]
    ) -> RuntimeHostNTPListenerSelectionResult {
        guard let guest = ipv4(guestAddress) else {
            return .unavailable(reason: "Guest address is not valid IPv4: \(guestAddress)")
        }
        let matches = interfaces.compactMap { interface -> RuntimeHostNTPListenerSelection? in
            guard interface.name != "lo0",
                  let host = ipv4(interface.address),
                  let netmask = ipv4(interface.netmask),
                  host != guest,
                  host & netmask == guest & netmask else {
                return nil
            }
            return RuntimeHostNTPListenerSelection(
                interfaceName: interface.name,
                hostAddress: interface.address,
                allowedGuestAddress: guestAddress
            )
        }
        guard matches.count == 1, let match = matches.first else {
            let reason = matches.isEmpty
                ? "No Host interface shares the explicit Guest subnet"
                : "Multiple Host interfaces share the explicit Guest subnet"
            return .unavailable(reason: reason)
        }
        return .selected(match)
    }

    private static func ipv4(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }
        var address: UInt32 = 0
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let octet = UInt8(part) else {
                return nil
            }
            address = (address << 8) | UInt32(octet)
        }
        return address
    }
}
