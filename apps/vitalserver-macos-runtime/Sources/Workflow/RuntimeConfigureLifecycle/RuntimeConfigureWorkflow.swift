import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeConfigureStateReaders<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var loadVMConfig: (URL) throws -> VMConfig
    public var loadGuestRuntimeConfig: (URL) throws -> GuestRuntimeConfigDocument

    public init(
        loadVMConfig: @escaping (URL) throws -> VMConfig,
        loadGuestRuntimeConfig: @escaping (URL) throws -> GuestRuntimeConfigDocument
    ) {
        self.loadVMConfig = loadVMConfig
        self.loadGuestRuntimeConfig = loadGuestRuntimeConfig
    }
}

public struct RuntimeConfigureDocumentWriter<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var encodeVMConfig: (VMConfig) throws -> Data
    public var encodeGuestRuntimeConfig: (GuestRuntimeConfigDocument) throws -> Data
    public var encodeGuestRuntimeSettings: (GuestRuntimeSettingsDocument) throws -> Data
    public var writeData: (Data, URL, Data.WritingOptions) throws -> Void

    public init(
        encodeVMConfig: @escaping (VMConfig) throws -> Data,
        encodeGuestRuntimeConfig: @escaping (GuestRuntimeConfigDocument) throws -> Data,
        encodeGuestRuntimeSettings: @escaping (GuestRuntimeSettingsDocument) throws -> Data,
        writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void
    ) {
        self.encodeVMConfig = encodeVMConfig
        self.encodeGuestRuntimeConfig = encodeGuestRuntimeConfig
        self.encodeGuestRuntimeSettings = encodeGuestRuntimeSettings
        self.writeData = writeData
    }
}

public struct RuntimeConfigureEffects<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var createDirectory: (URL, Bool) throws -> Void
    public var resizeVMDiskIfNeeded: (Int) throws -> Void
    public var setInstalledProxyPort: (Int) throws -> Void
    public var readSecretFile: (URL) throws -> String
    public var restrictSecretFile: (URL) throws -> Void
    public var setStartOnBoot: (Bool) throws -> Void
    public var setSystemSleepPrevention: (Bool) throws -> Void
    public var restartRuntimeServices: () throws -> Void
    public var ensureRuntimeDefaults: (inout VMConfig) -> Void
    public var log: (String) -> Void

    public init(
        createDirectory: @escaping (URL, Bool) throws -> Void,
        resizeVMDiskIfNeeded: @escaping (Int) throws -> Void,
        setInstalledProxyPort: @escaping (Int) throws -> Void,
        readSecretFile: @escaping (URL) throws -> String,
        restrictSecretFile: @escaping (URL) throws -> Void,
        setStartOnBoot: @escaping (Bool) throws -> Void,
        setSystemSleepPrevention: @escaping (Bool) throws -> Void,
        restartRuntimeServices: @escaping () throws -> Void,
        ensureRuntimeDefaults: @escaping (inout VMConfig) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.createDirectory = createDirectory
        self.resizeVMDiskIfNeeded = resizeVMDiskIfNeeded
        self.setInstalledProxyPort = setInstalledProxyPort
        self.readSecretFile = readSecretFile
        self.restrictSecretFile = restrictSecretFile
        self.setStartOnBoot = setStartOnBoot
        self.setSystemSleepPrevention = setSystemSleepPrevention
        self.restartRuntimeServices = restartRuntimeServices
        self.ensureRuntimeDefaults = ensureRuntimeDefaults
        self.log = log
    }
}

public struct RuntimeConfigureWorkflow<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var readers: RuntimeConfigureStateReaders<VMConfig>
    public var writer: RuntimeConfigureDocumentWriter<VMConfig>
    public var effects: RuntimeConfigureEffects<VMConfig>
    private var useCase: ConfigureRuntimeUseCase<VMConfig> {
        ConfigureRuntimeUseCase()
    }

    public init(
        readers: RuntimeConfigureStateReaders<VMConfig>,
        writer: RuntimeConfigureDocumentWriter<VMConfig>,
        effects: RuntimeConfigureEffects<VMConfig>
    ) {
        self.readers = readers
        self.writer = writer
        self.effects = effects
    }

    public func configure(
        _ request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>
    ) throws -> ConfigureRuntimeResult {
        let resolvedRequest = try resolveSecretFileChanges(in: request)
        let currentVMConfig = try readers.loadVMConfig(context.vmConfigURL)
        let currentGuestRuntimeConfig = try readers.loadGuestRuntimeConfig(context.guestRuntimeConfigURL)
        let plan = try useCase.plan(
            resolvedRequest,
            context: context,
            currentVMConfig: currentVMConfig,
            currentGuestRuntimeConfig: currentGuestRuntimeConfig
        )

        try executePreWriteEffects(plan.effects)

        var vmConfig = plan.vmConfig
        effects.ensureRuntimeDefaults(&vmConfig)
        try writer.writeData(try writer.encodeVMConfig(vmConfig), context.vmConfigURL, .atomic)
        try writer.writeData(
            try writer.encodeGuestRuntimeConfig(plan.guestRuntimeConfig),
            context.guestRuntimeConfigURL,
            .atomic
        )
        try writer.writeData(
            try writer.encodeGuestRuntimeSettings(plan.guestRuntimeSettings),
            context.guestRuntimeSettingsURL,
            .atomic
        )
        effects.log(plan.logMessage)

        try executePostWriteEffects(plan.effects)
        return ConfigureRuntimeResult(restart: plan.restart)
    }

    private func resolveSecretFileChanges(
        in request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
    ) throws -> ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode> {
        let changes = try request.changes.map { change in
            switch change {
            case .adminPasswordFile(let url):
                let password = try effects.readSecretFile(url)
                guard !password.isEmpty, RuntimeTextValidator.isSingleLine(password) else {
                    throw ConfigureRuntimeError.invalidArgument(
                        "--admin-password-file must contain a non-empty single-line password"
                    )
                }
                return ConfigureRuntimeChange<VMConfig.ConfigureNetworkMode>.adminPassword(password)
            default:
                return change
            }
        }
        return ConfigureRuntimeRequest(changes: changes, restart: request.restart)
    }

    private func executePreWriteEffects(_ plannedEffects: [ConfigureRuntimeEffect]) throws {
        for effect in plannedEffects {
            switch effect {
            case .createDirectory(let url, let withIntermediateDirectories):
                try effects.createDirectory(url, withIntermediateDirectories)
            case .resizeVMDiskIfNeeded(let diskGiB):
                try effects.resizeVMDiskIfNeeded(diskGiB)
            case .setInstalledProxyPort(let port):
                try effects.setInstalledProxyPort(port)
            case .setStartOnBoot(let enabled):
                try effects.setStartOnBoot(enabled)
            case .setSystemSleepPrevention(let enabled):
                try effects.setSystemSleepPrevention(enabled)
            case .restrictSecretFile, .restartRuntimeServices:
                continue
            }
        }
    }

    private func executePostWriteEffects(_ plannedEffects: [ConfigureRuntimeEffect]) throws {
        for effect in plannedEffects {
            switch effect {
            case .restrictSecretFile(let url):
                try effects.restrictSecretFile(url)
            case .restartRuntimeServices:
                try effects.restartRuntimeServices()
            case .createDirectory,
                 .resizeVMDiskIfNeeded,
                 .setInstalledProxyPort,
                 .setStartOnBoot,
                 .setSystemSleepPrevention:
                continue
            }
        }
    }
}
