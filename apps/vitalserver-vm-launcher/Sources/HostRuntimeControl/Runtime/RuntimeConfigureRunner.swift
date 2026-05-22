import Foundation
import RuntimeCore
import HostRuntimeInfrastructure

struct RuntimeConfigureActions {
    var resizeVMDiskIfNeeded: (Int) throws -> Void
    var setInstalledProxyPort: (Int) throws -> Void
    var readSecretFile: (URL) throws -> String
    var restrictSecretFile: (URL) throws -> Void
    var setStartOnBoot: (Bool) throws -> Void
    var restartRuntimeServices: () throws -> Void
}

struct RuntimeConfigureResult: Equatable {
    let restart: Bool
}

struct RuntimeConfigureRunner {
    private let installedPaths: InstalledRuntimePaths
    private let configURL: URL
    private let fileStore: RuntimeFileStore
    private let actions: RuntimeConfigureActions
    private let log: (String) -> Void

    init(
        installedPaths: InstalledRuntimePaths,
        configURL: URL,
        fileStore: RuntimeFileStore,
        actions: RuntimeConfigureActions,
        log: @escaping (String) -> Void
    ) {
        self.installedPaths = installedPaths
        self.configURL = configURL
        self.fileStore = fileStore
        self.actions = actions
        self.log = log
    }

    func configure(arguments: [String]) throws -> RuntimeConfigureResult {
        var remaining = arguments
        var restart = false
        var vmConfig = try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)
        let runtimeConfigURL = installedPaths.guestRuntimeConfig
        var guestConfig = try GuestRuntimeConfigDocument.load(from: runtimeConfigURL, fileStore: fileStore)

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            let option = RuntimeConfigureOption(rawValue: key)
            if option == .restart {
                restart = true
                continue
            }
            guard let value = remaining.first else {
                throw LauncherError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()
            try apply(option: option, value: value, vmConfig: &vmConfig, guestConfig: &guestConfig)
        }

        try validate(vmConfig)
        VMRuntimeConfig.ensureRuntimeDefaults(&vmConfig, paths: installedPaths)
        try fileStore.writeData(try JSONEncoder.pretty.encode(vmConfig), to: configURL, options: .atomic)
        try fileStore.writeData(try JSONEncoder.pretty.encode(guestConfig), to: runtimeConfigURL, options: .atomic)
        try actions.restrictSecretFile(runtimeConfigURL)
        log("runtime configuration updated restart=\(restart)")

        if restart {
            try actions.restartRuntimeServices()
        }
        return RuntimeConfigureResult(restart: restart)
    }

    private func apply(
        option: RuntimeConfigureOption,
        value: String,
        vmConfig: inout VMRuntimeConfig,
        guestConfig: inout GuestRuntimeConfigDocument
    ) throws {
        switch option {
        case .cpu:
            guard let cpu = Int(value),
                  cpu >= Constants.Defaults.minimumCPUCount,
                  cpu <= Constants.Defaults.maximumCPUCount else {
                throw LauncherError.missingArgument(
                    "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(Constants.Defaults.maximumCPUCount)"
                )
            }
            vmConfig.cpuCount = cpu
        case .memoryGiB:
            guard let memoryGiB = UInt64(value),
                  stride(
                    from: Constants.Defaults.minimumMemoryGiB,
                    through: Constants.Defaults.maximumMemoryGiB,
                    by: Constants.Defaults.memoryStepGiB
                  ).contains(Int(memoryGiB)) else {
                throw LauncherError.missingArgument(
                    "--memory-gib must be between \(Constants.Defaults.minimumMemoryGiB) and \(Constants.Defaults.maximumMemoryGiB) in \(Constants.Defaults.memoryStepGiB) GiB steps"
                )
            }
            vmConfig.memoryMiB = memoryGiB * 1024
        case .diskGiB:
            guard let diskGiB = Int(value),
                  stride(
                    from: Constants.Defaults.minimumDiskGiB,
                    through: Constants.Defaults.maximumDiskGiB,
                    by: Constants.Defaults.diskStepGiB
                  ).contains(diskGiB) else {
                throw LauncherError.missingArgument(
                    "--disk-gib must be between \(Constants.Defaults.minimumDiskGiB) and \(Constants.Defaults.maximumDiskGiB) in \(Constants.Defaults.diskStepGiB) GiB steps"
                )
            }
            try actions.resizeVMDiskIfNeeded(diskGiB)
        case .network:
            guard let mode = NetworkMode(rawValue: value) else {
                throw LauncherError.missingArgument("--network must be `shared` or `bridged`")
            }
            vmConfig.network.mode = mode
            if mode == .shared {
                vmConfig.network.bridgedInterface = nil
            }
        case .bridgedInterface:
            guard RuntimeTextValidator.isSingleLine(value), !value.isEmpty else {
                throw LauncherError.missingArgument("--bridged-interface must not be empty or contain newlines")
            }
            vmConfig.network.bridgedInterface = value
        case .proxyPort:
            guard let port = Int(value), (1...65_535).contains(port) else {
                throw LauncherError.missingArgument("--proxy-port must be between 1 and 65535")
            }
            try actions.setInstalledProxyPort(port)
        case .vitalFilesDirectory:
            guard value.hasPrefix("/") else {
                throw LauncherError.missingArgument("--vital-files-dir must be an absolute path")
            }
            try fileStore.createDirectory(at: URL(fileURLWithPath: value), withIntermediateDirectories: true)
            vmConfig.vitalFilesDirectory = SharedDirectoryConfig(
                hostPath: value,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
            guestConfig.vitalFilesDirectory = Constants.Defaults.vitalFilesDirectoryGuestMountPath
        case .publicHost:
            guard RuntimeTextValidator.isSingleLine(value) else {
                throw LauncherError.missingArgument("--public-host must not contain newlines")
            }
            guestConfig.publicHost = value
        case .publicPort:
            guard let port = Int(value), (1...65_535).contains(port) else {
                throw LauncherError.missingArgument("--public-port must be between 1 and 65535")
            }
            guestConfig.publicPort = port
        case .adminPassword:
            guard !value.isEmpty, RuntimeTextValidator.isSingleLine(value) else {
                throw LauncherError.missingArgument("--admin-password must not be empty or contain newlines")
            }
            guestConfig.adminPassword = value
        case .adminPasswordFile:
            let password = try actions.readSecretFile(URL(fileURLWithPath: value))
            guard !password.isEmpty, RuntimeTextValidator.isSingleLine(password) else {
                throw LauncherError.missingArgument("--admin-password-file must contain a non-empty single-line password")
            }
            guestConfig.adminPassword = password
        case .startOnBoot:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw LauncherError.missingArgument("--start-on-boot must be true or false")
            }
            try actions.setStartOnBoot(enabled)
        case .autoRecovery:
            guard let enabled = RuntimeBooleanParser.parse(value) else {
                throw LauncherError.missingArgument("--auto-recovery must be true or false")
            }
            vmConfig.autoRecoveryEnabled = enabled
        case .restart:
            break
        case .unknown(let key):
            throw LauncherError.missingArgument("unsupported runtime configure option: \(key)")
        }
    }

    private func validate(_ vmConfig: VMRuntimeConfig) throws {
        if vmConfig.network.mode == .bridged,
           vmConfig.network.bridgedInterface?.isEmpty != false {
            throw LauncherError.missingArgument("--bridged-interface is required when --network bridged")
        }
    }
}
