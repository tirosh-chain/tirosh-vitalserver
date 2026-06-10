import Foundation
import Contracts
import Domain

public struct RunConfigureRuntimeUseCase<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public init() {}

    public func configure(
        _ request: ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>,
        context: ConfigureRuntimeContext<VMConfig.ConfigureNetworkMode>,
        operations: ConfigureRuntimeOperations<VMConfig>
    ) throws -> ConfigureRuntimeResult {
        let useCase = ConfigureRuntimeUseCase<VMConfig>()
        let resolvedRequest = try operations.effects.resolveSecretFileChanges(request)
        let currentVMConfig = try operations.readers.loadVMConfig(context.vmConfigURL)
        let currentGuestRuntimeConfig = try operations.readers.loadGuestRuntimeConfig(context.guestRuntimeConfigURL)
        let currentVMDiskSizeGiB = try operations.readers.loadVMDiskSizeGiB()
        let plan = try useCase.plan(
            resolvedRequest,
            context: context,
            currentVMConfig: currentVMConfig,
            currentGuestRuntimeConfig: currentGuestRuntimeConfig,
            currentVMDiskSizeGiB: currentVMDiskSizeGiB
        )
        let effectPlan = useCase.effectExecutionPlan(plan.effects)

        try operations.effects.executeEffects(effectPlan.preWriteEffects)

        var vmConfig = plan.vmConfig
        operations.effects.ensureRuntimeDefaults(&vmConfig)
        try operations.writer.writeData(try operations.writer.encodeVMConfig(vmConfig), context.vmConfigURL, .atomic)
        try operations.writer.writeData(
            try operations.writer.encodeGuestRuntimeConfig(plan.guestRuntimeConfig),
            context.guestRuntimeConfigURL,
            .atomic
        )
        try operations.writer.writeData(
            try operations.writer.encodeGuestRuntimeSettings(plan.guestRuntimeSettings),
            context.guestRuntimeSettingsURL,
            .atomic
        )
        operations.effects.log(plan.logMessage)

        try operations.effects.executeEffects(effectPlan.postWriteEffects)
        return ConfigureRuntimeResult(
            restart: plan.restart,
            restartRequirement: plan.restartRequirement
        )
    }
}

public struct ConfigureRuntimeStateReaders<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var loadVMConfig: (URL) throws -> VMConfig
    public var loadGuestRuntimeConfig: (URL) throws -> GuestRuntimeConfigDocument
    public var loadVMDiskSizeGiB: () throws -> Int

    public init(
        loadVMConfig: @escaping (URL) throws -> VMConfig,
        loadGuestRuntimeConfig: @escaping (URL) throws -> GuestRuntimeConfigDocument,
        loadVMDiskSizeGiB: @escaping () throws -> Int
    ) {
        self.loadVMConfig = loadVMConfig
        self.loadGuestRuntimeConfig = loadGuestRuntimeConfig
        self.loadVMDiskSizeGiB = loadVMDiskSizeGiB
    }
}

public struct ConfigureRuntimeDocumentWriter<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
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

public struct ConfigureRuntimeEffects<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var resolveSecretFileChanges: (
        ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
    ) throws -> ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
    public var executeEffects: ([ConfigureRuntimeEffect]) throws -> Void
    public var ensureRuntimeDefaults: (inout VMConfig) -> Void
    public var log: (String) -> Void

    public init(
        resolveSecretFileChanges: @escaping (
            ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>
        ) throws -> ConfigureRuntimeRequest<VMConfig.ConfigureNetworkMode>,
        executeEffects: @escaping ([ConfigureRuntimeEffect]) throws -> Void,
        ensureRuntimeDefaults: @escaping (inout VMConfig) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.resolveSecretFileChanges = resolveSecretFileChanges
        self.executeEffects = executeEffects
        self.ensureRuntimeDefaults = ensureRuntimeDefaults
        self.log = log
    }
}

public struct ConfigureRuntimeOperations<VMConfig: ConfigureRuntimeMutableVMRuntimeConfiguration> {
    public var readers: ConfigureRuntimeStateReaders<VMConfig>
    public var writer: ConfigureRuntimeDocumentWriter<VMConfig>
    public var effects: ConfigureRuntimeEffects<VMConfig>

    public init(
        readers: ConfigureRuntimeStateReaders<VMConfig>,
        writer: ConfigureRuntimeDocumentWriter<VMConfig>,
        effects: ConfigureRuntimeEffects<VMConfig>
    ) {
        self.readers = readers
        self.writer = writer
        self.effects = effects
    }
}
