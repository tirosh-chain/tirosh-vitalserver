import Errors
public struct RuntimeConfigFlagValues: Equatable, Sendable {
    public let autoRecoveryEnabled: Bool?
    public let preventSystemSleep: Bool?

    public init(
        autoRecoveryEnabled: Bool?,
        preventSystemSleep: Bool?
    ) {
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
    }
}

public struct RuntimeConfigFlagReader {
    public var loadFlags: () throws -> RuntimeConfigFlagValues
    public var log: (String) -> Void

    public init(
        loadFlags: @escaping () throws -> RuntimeConfigFlagValues,
        log: @escaping (String) -> Void
    ) {
        self.loadFlags = loadFlags
        self.log = log
    }

    public func automaticRecoveryEnabled() -> Bool {
        readBoolFlag(
            name: "autoRecoveryEnabled",
            defaultValue: true,
            value: { $0.autoRecoveryEnabled }
        )
    }

    public func preventSystemSleepEnabled() -> Bool {
        readBoolFlag(
            name: "preventSystemSleep",
            defaultValue: true,
            value: { $0.preventSystemSleep }
        )
    }

    private func readBoolFlag(
        name: String,
        defaultValue: Bool,
        value: (RuntimeConfigFlagValues) -> Bool?
    ) -> Bool {
        do {
            let flags = try loadFlags()
            guard let configuredValue = value(flags) else {
                log("runtime config flag missing name=\(name) default=\(defaultValue)")
                return defaultValue
            }
            return configuredValue
        } catch {
            log("failed to read runtime config flag name=\(name) default=\(defaultValue) error=\(error)")
            return defaultValue
        }
    }
}
