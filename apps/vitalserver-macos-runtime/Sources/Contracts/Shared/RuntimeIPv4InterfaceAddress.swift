public struct RuntimeIPv4InterfaceAddress: Equatable, Sendable {
    public let name: String
    public let address: String
    public let netmask: String

    public init(name: String, address: String, netmask: String) {
        self.name = name
        self.address = address
        self.netmask = netmask
    }
}
