public struct RuntimeUninstallCommand: Equatable {
    public let clean: Bool

    public init(clean: Bool) {
        self.clean = clean
    }
}
