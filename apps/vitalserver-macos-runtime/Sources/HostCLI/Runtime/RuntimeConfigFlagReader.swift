struct RuntimeConfigFlagReader {
    var loadConfig: () throws -> VMRuntimeConfig
    var log: (String) -> Void

    func automaticRecoveryEnabled() -> Bool {
        readBoolFlag(
            name: "autoRecoveryEnabled",
            defaultValue: true,
            value: { $0.autoRecoveryEnabled }
        )
    }

    func preventSystemSleepEnabled() -> Bool {
        readBoolFlag(
            name: "preventSystemSleep",
            defaultValue: true,
            value: { $0.preventSystemSleep }
        )
    }

    private func readBoolFlag(
        name: String,
        defaultValue: Bool,
        value: (VMRuntimeConfig) -> Bool?
    ) -> Bool {
        do {
            let config = try loadConfig()
            guard let configuredValue = value(config) else {
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
