public struct RuntimeSharedDirectoryConfiguration: Equatable, Sendable {
    public let hostPath: String
    public let tag: String
    public let guestMountPath: String
    public let readOnly: Bool

    public init(
        hostPath: String,
        tag: String,
        guestMountPath: String,
        readOnly: Bool
    ) {
        self.hostPath = hostPath
        self.tag = tag
        self.guestMountPath = guestMountPath
        self.readOnly = readOnly
    }
}
