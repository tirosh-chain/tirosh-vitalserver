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

public enum RuntimeConfigFlagReadResult: Equatable, Sendable {
    case configured(name: String, value: Bool)
    case defaulted(name: String, value: Bool, reason: String)
    case failed(name: String, reason: String)
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

    public func automaticRecoveryFlag() -> RuntimeConfigFlagReadResult {
        readBoolFlag(
            name: "autoRecoveryEnabled",
            defaultValue: true,
            value: { $0.autoRecoveryEnabled }
        )
    }

    public func preventSystemSleepFlag() -> RuntimeConfigFlagReadResult {
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
    ) -> RuntimeConfigFlagReadResult {
        do {
            let flags = try loadFlags()
            guard let configuredValue = value(flags) else {
                log("runtime config flag missing name=\(name) default=\(defaultValue)")
                return .defaulted(name: name, value: defaultValue, reason: "missing")
            }
            return .configured(name: name, value: configuredValue)
        } catch {
            let reason = String(describing: error)
            log("failed to read runtime config flag name=\(name) error=\(reason)")
            return .failed(name: name, reason: reason)
        }
    }
}
