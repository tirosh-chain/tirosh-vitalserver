import Darwin
import Contracts

public struct SystemRuntimeIPv4InterfaceProvider: Sendable {
    public init() {}

    public func read() throws -> [RuntimeIPv4InterfaceAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else {
            throw SystemRuntimeIPv4InterfaceProviderError.readFailed(errno)
        }
        defer {
            freeifaddrs(first)
        }

        var interfaces: [RuntimeIPv4InterfaceAddress] = []
        var current = first
        while let entry = current?.pointee {
            defer {
                current = entry.ifa_next
            }
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = entry.ifa_netmask,
                  let addressText = numericHost(address),
                  let netmaskText = numericHost(netmask) else {
                continue
            }
            interfaces.append(RuntimeIPv4InterfaceAddress(
                name: decodeCString(entry.ifa_name),
                address: addressText,
                netmask: netmaskText
            ))
        }
        return interfaces
    }

    private func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else {
            return nil
        }
        return decodeCString(buffer)
    }

    private func decodeCString(
        _ value: UnsafePointer<CChar>
    ) -> String {
        String(decoding: UnsafeBufferPointer(
            start: value,
            count: strlen(value)
        ).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func decodeCString(
        _ value: [CChar]
    ) -> String {
        String(
            decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}

public enum SystemRuntimeIPv4InterfaceProviderError: Error, Equatable {
    case readFailed(Int32)
}
