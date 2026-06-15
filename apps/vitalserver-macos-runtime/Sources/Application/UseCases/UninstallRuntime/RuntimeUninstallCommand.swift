public struct RuntimeUninstallCommand: Equatable {
    public let clean: Bool
    public let forceClean: Bool

    public init(clean: Bool, forceClean: Bool = false) {
        self.clean = clean || forceClean
        self.forceClean = forceClean
    }
}
