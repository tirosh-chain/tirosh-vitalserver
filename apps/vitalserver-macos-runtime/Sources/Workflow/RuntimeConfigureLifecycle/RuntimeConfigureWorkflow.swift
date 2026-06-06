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
        let resolvedRequest = try effects.resolveSecretFileChanges(request)
        let currentVMConfig = try readers.loadVMConfig(context.vmConfigURL)
        let currentGuestRuntimeConfig = try readers.loadGuestRuntimeConfig(context.guestRuntimeConfigURL)
        let plan = try useCase.plan(
            resolvedRequest,
            context: context,
            currentVMConfig: currentVMConfig,
            currentGuestRuntimeConfig: currentGuestRuntimeConfig
        )
        let effectPlan = useCase.effectExecutionPlan(plan.effects)

        try effects.executeEffects(effectPlan.preWriteEffects)

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

        try effects.executeEffects(effectPlan.postWriteEffects)
        return ConfigureRuntimeResult(restart: plan.restart)
    }
}
