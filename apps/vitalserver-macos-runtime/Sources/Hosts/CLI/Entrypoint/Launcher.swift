import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Virtualization
import Errors

struct Launcher {
    // Keep command routing here so `main.swift` stays as the process entry only.
    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        let paths = LauncherPaths.resolve(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            vmHomeEnvironmentKey: Constants.Environment.vmHome,
            defaultHomePathComponents: Constants.Paths.defaultHomePathComponents
        )
        switch Command.parse(command) {
        case .initialize:
            try initialize(paths: paths)
        case .start:
            try start(paths: paths)
        case .status:
            try ProcessState.status(pidFile: paths.pidFile, fileStore: SystemRuntimeFileStore())
        case .stop:
            try ProcessState.stop(pidFile: paths.pidFile, fileStore: SystemRuntimeFileStore())
        case .network:
            try configureNetwork(paths: paths, arguments: Array(arguments.dropFirst()))
        case .interfaces:
            listInterfaces()
        case .configure:
            try configureRuntime(paths: paths, arguments: Array(arguments.dropFirst()))
        case .runtime:
            try RuntimeLifecycle(paths: paths).run(arguments: Array(arguments.dropFirst()))
        case .clean:
            try clean(paths: paths)
        case .version:
            print(Constants.launcherVersion)
        case .help:
            printUsage()
        case .none:
            throw LauncherError.unsupportedCommand(command)
        }
    }

    // Initialize the runtime directory without requiring VM entitlements.
    func initialize(paths: LauncherPaths) throws {
        let fileStore = SystemRuntimeFileStore()
        let installedPaths = paths.installed
        try fileStore.createDirectory(
            at: installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.vitalFilesDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.vrReleaseDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.hostRunDirectory,
            withIntermediateDirectories: true
        )
        try fileStore.createDirectory(
            at: installedPaths.centralRuntimeLogsDirectory,
            withIntermediateDirectories: true
        )

        if !fileStore.fileExists(paths.config) {
            var config = VMRuntimeConfig.default(paths: installedPaths)
            VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: installedPaths)
            let data = try JSONEncoder.pretty.encode(config)
            try fileStore.writeData(data, to: paths.config, options: [])
            print("created \(paths.config.path)")
        } else {
            var config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
            let previous = config
            VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: installedPaths)
            if config.network.macAddress != previous.network.macAddress
                || config.cloudInitPath != previous.cloudInitPath
                || config.kernelCommandLine != previous.kernelCommandLine {
                let data = try JSONEncoder.pretty.encode(config)
                try fileStore.writeData(data, to: paths.config, options: [])
                print("updated \(paths.config.path) with missing runtime defaults")
            } else {
                print("exists \(paths.config.path)")
            }
        }

        print("place Linux runtime assets under \(installedPaths.runtimeDirectory.path)")
        print("shared data directory: \(installedPaths.dataDirectory.path)")
    }

    // Remove disposable VM runtime state while preserving host-bound data.
    func clean(paths: LauncherPaths) throws {
        let fileStore = SystemRuntimeFileStore()
        try ProcessState.stop(pidFile: paths.pidFile, fileStore: fileStore)

        for url in paths.cleanableRuntimePaths {
            if fileStore.fileExists(url) || fileStore.directoryExists(url) {
                try fileStore.removeItem(at: url)
                print("removed \(url.path)")
            }
        }

        print("preserved shared data directory: \(paths.installed.dataDirectory.path)")
    }

    // Build the VM configuration, start it, then keep the process alive.
    func start(paths: LauncherPaths) throws {
        let fileStore = SystemRuntimeFileStore()
        let settingsRepository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: paths.installed.runtimeStateDatabase,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        let settings: RuntimeHostSettingsRecord
        switch settingsRepository.loadHostSettings() {
        case .loaded(let record):
            settings = record
        case .missing:
            throw LauncherError.runtimeOperationFailed("Host settings SQLite state is missing")
        case .failed(let reason):
            throw LauncherError.runtimeOperationFailed(reason)
        }
        guard settings.materializedRevision == settings.revision else {
            let materializedRevisionText = settings.materializedRevision.map(String.init) ?? "missing"
            throw LauncherError.runtimeOperationFailed(
                "Host settings revision is not materialized revision=\(settings.revision) materializedRevision=\(materializedRevisionText)"
            )
        }
        let materializedPayload = RuntimeHostSettingsPayload(
            vmConfigJSON: try fileStore.readData(paths.config),
            guestRuntimeConfigJSON: try fileStore.readData(paths.installed.guestRuntimeConfig),
            guestRuntimeSettingsJSON: try fileStore.readData(paths.installed.guestRuntimeSettings)
        )
        guard materializedPayload == settings.payload else {
            throw LauncherError.runtimeOperationFailed(
                "Host settings boot materialization does not match SQLite revision=\(settings.revision)"
            )
        }
        let config = try JSONDecoder().decode(VMRuntimeConfig.self, from: settings.payload.vmConfigJSON)
        try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore)
        try RuntimeVMLifecycleProcessExitReconciler.reconcileBeforeServiceStart(
            paths: paths,
            fileStore: fileStore,
            log: { print($0) }
        )
        try RuntimeHostTimeContractWriter(
            destination: paths.installed.hostTime,
            fileStore: fileStore,
            now: Date.init,
            log: { print($0) }
        ).write()
        let lifecycleWriter = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: paths.installed.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let lifecycleState = try lifecycleWriter.writeVMLifecycleResource(
            state: .starting,
            operation: .startServices,
            terminalReason: nil,
            message: "VM process start requested",
            bootWindowSeconds: Constants.Runtime.vmBootLifecycleDeadlineSeconds
        )
        guard lifecycleState.state == .loaded,
              let lifecycle = lifecycleState.document,
              let runID = lifecycle.bootID,
              !runID.isEmpty else {
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle start did not return an explicit run ID"
            )
        }
        _ = try settingsRepository.recordHostSettingsBoot(
            revision: settings.revision,
            runID: runID,
            startedAt: lifecycle.startedAt
        )
        try removeStaleGuestBootstrapArtifacts(paths: paths, fileStore: fileStore)
        try ProcessState.writeCurrentPid(pidFile: paths.pidFile, fileStore: fileStore)

        let configurationFactory = VMConfigurationFactory.hostCLI(fileStore: fileStore)
        let vmConfiguration: VZVirtualMachineConfiguration
        do {
            vmConfiguration = try configurationFactory.build(from: config)
        } catch VMConfigurationFactoryError.invalidMacAddress(let value) {
            throw LauncherError.invalidMacAddress(value)
        } catch VMConfigurationFactoryError.missingBridgedInterface {
            throw LauncherError.missingArgument("bridged network requires `bridgedInterface` in vm-config.json")
        } catch VMConfigurationFactoryError.noBridgedInterfaces {
            throw LauncherError.noBridgedInterfaces
        } catch VMConfigurationFactoryError.bridgedInterfaceUnavailable(let interface) {
            throw LauncherError.bridgedInterfaceUnavailable(interface)
        } catch VMConfigurationFactoryError.missingStorageFile(let path) {
            throw LauncherError.missingFile(path)
        } catch VMConfigurationFactoryError.missingRootDiskPath {
            throw LauncherError.runtimeOperationFailed(
                "VM root disk path is missing in vm-config.json"
            )
        } catch VMConfigurationFactoryError.missingRuntimeDataDiskPath {
            throw LauncherError.runtimeOperationFailed(
                "VM runtime data disk path is missing in vm-config.json"
            )
        } catch VMConfigurationFactoryError.storagePathInspectionFailed(let path, let reason) {
            throw LauncherError.runtimeOperationFailed(
                "VM storage path inspection failed path=\(path) reason=\(reason)"
            )
        } catch VMConfigurationFactoryError.unexpectedStoragePathState(let path, let state) {
            throw LauncherError.runtimeOperationFailed(
                "VM storage path state is unexpected path=\(path) state=\(state)"
            )
        }
        let virtualMachine = VZVirtualMachine(configuration: vmConfiguration)
        let delegate = VirtualMachineDelegate.hostCLI(
            pidFile: paths.pidFile,
            lifecycleWriter: lifecycleWriter,
            fileStore: fileStore
        )
        let terminationHandler = VirtualMachineTerminationHandler.hostCLI(
            virtualMachine: virtualMachine,
            pidFile: paths.pidFile,
            lifecycleWriter: lifecycleWriter,
            fileStore: fileStore
        )
        virtualMachine.delegate = delegate
        terminationHandler.start()

        print("starting vitalserver VM")
        virtualMachine.start { result in
            switch result {
            case .success:
                do {
                    try lifecycleWriter.writeVMLifecycleResource(
                        state: .bootstrapping,
                        operation: .startServices,
                        terminalReason: nil,
                        message: "VM process started; waiting for guest runtime",
                        bootWindowSeconds: Constants.Runtime.vmBootLifecycleDeadlineSeconds
                    )
                } catch {
                    fputs("failed to write VM lifecycle bootstrapping state: \(error)\n", stderr)
                }
                print("vitalserver VM started")
            case let .failure(error):
                ProcessState.removePidFile(paths.pidFile, fileStore: fileStore)
                do {
                    try lifecycleWriter.writeVMLifecycleResource(
                        state: .failed,
                        operation: .startServices,
                        terminalReason: vmStartFailureReason(error),
                        message: error.localizedDescription,
                        bootWindowSeconds: nil
                    )
                } catch {
                    fputs("failed to write VM lifecycle failed state: \(error)\n", stderr)
                }
                fputs("failed to start VM: \(error)\n", stderr)
                Foundation.exit(1)
            }
        }

        // Keep the CLI alive while the Virtualization framework owns the VM.
        RunLoop.main.run()
        _ = configurationFactory
        _ = delegate
        _ = terminationHandler
    }

    private func removeStaleGuestBootstrapArtifacts(
        paths: LauncherPaths,
        fileStore: RuntimeFileReading & RuntimeFileWriting
    ) throws {
        for url in [paths.installed.runtimeObservation, paths.installed.vmIPFile] {
            if fileStore.fileExists(url) {
                try fileStore.removeItem(at: url)
                print("removed stale guest bootstrap artifact: \(url.path)")
            }
        }
    }

    private func vmStartFailureReason(_ error: Error) -> RuntimeVMLifecycleTerminalReason {
        let nsError = error as NSError
        if nsError.domain == "VZErrorDomain", nsError.code == 2 {
            return .diskAttachmentInvalid
        }
        return .launchFailed
    }

    func listInterfaces() {
        let interfaces = VZBridgedNetworkInterface.networkInterfaces
        if interfaces.isEmpty {
            print("no bridged interfaces available")
            return
        }

        for interface in interfaces {
            print("\(interface.identifier)\t\(interface.localizedDisplayName ?? "")")
        }
    }

    func configureNetwork(paths: LauncherPaths, arguments: [String]) throws {
        guard let modeValue = arguments.first else {
            throw LauncherError.missingArgument("usage: vitalserver-vm network shared|bridged [interface]")
        }
        guard let mode = RuntimeNetworkMode(rawValue: modeValue) else {
            throw LauncherError.missingArgument("network mode must be `shared` or `bridged`")
        }

        let fileStore = SystemRuntimeFileStore()
        var config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        config.network.mode = mode

        switch mode {
        case .shared:
            config.network.bridgedInterface = nil
        case .bridged:
            let interface = try resolveBridgedInterface(arguments.dropFirst().first)
            config.network.bridgedInterface = interface.identifier
        }

        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: paths.installed)
        let data = try JSONEncoder.pretty.encode(config)
        try fileStore.writeData(data, to: paths.config, options: [])

        switch mode {
        case .shared:
            print("network mode: shared")
        case .bridged:
            print("network mode: bridged")
            print("bridged interface: \(config.network.bridgedInterface ?? "")")
            print("mac address: \(config.network.macAddress ?? "")")
        }
    }

    func configureRuntime(paths: LauncherPaths, arguments: [String]) throws {
        let fileStore = SystemRuntimeFileStore()
        var config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        var remaining = arguments

        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            guard let value = remaining.first else {
                throw LauncherError.missingArgument("missing value for \(key)")
            }
            remaining.removeFirst()

            switch key {
            case "--cpu":
                let maximumAllowedCPUCount = Constants.Defaults.maximumAllowedCPUCount(
                    systemCPUCount: ProcessInfo.processInfo.processorCount
                )
                guard let cpu = Int(value),
                      cpu >= Constants.Defaults.minimumCPUCount,
                      cpu <= maximumAllowedCPUCount else {
                    throw LauncherError.missingArgument(
                        "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(maximumAllowedCPUCount)"
                    )
                }
                config.cpuCount = cpu
            case "--memory-mib":
                let maximumAllowedMemoryMiB = Constants.Defaults.maximumAllowedMemoryMiB(
                    physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
                )
                guard let memory = UInt64(value),
                      memory >= UInt64(Constants.Defaults.minimumMemoryGiB * 1024),
                      memory <= maximumAllowedMemoryMiB else {
                    throw LauncherError.missingArgument(
                        "--memory-mib must be between \(Constants.Defaults.minimumMemoryGiB * 1024) and \(maximumAllowedMemoryMiB)"
                    )
                }
                config.memoryMiB = memory
            case "--network":
                guard let mode = RuntimeNetworkMode(rawValue: value) else {
                    throw LauncherError.missingArgument("--network must be `shared` or `bridged`")
                }
                config.network.mode = mode
                if mode == .shared {
                    config.network.bridgedInterface = nil
                }
            case "--shared-dir":
                guard value.hasPrefix("/") else {
                    throw LauncherError.missingArgument("--shared-dir must be an absolute path")
                }
                if config.sharedDirectory == nil {
                    config.sharedDirectory = SharedDirectoryConfig(
                        hostPath: value,
                        tag: Constants.Defaults.sharedDirectoryTag,
                        guestMountPath: Constants.Defaults.sharedDirectoryGuestMountPath,
                        readOnly: false
                    )
                } else {
                    config.sharedDirectory?.hostPath = value
                    config.sharedDirectory?.readOnly = false
                }
            case "--vital-files-dir":
                guard value.hasPrefix("/") else {
                    throw LauncherError.missingArgument("--vital-files-dir must be an absolute path")
                }
                if config.vitalFilesDirectory == nil {
                    config.vitalFilesDirectory = SharedDirectoryConfig(
                        hostPath: value,
                        tag: Constants.Defaults.vitalFilesDirectoryTag,
                        guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                        readOnly: false
                    )
                } else {
                    config.vitalFilesDirectory?.hostPath = value
                    config.vitalFilesDirectory?.readOnly = false
                }
            default:
                throw LauncherError.missingArgument("unsupported configure option: \(key)")
            }
        }

        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: paths.installed)
        let data = try JSONEncoder.pretty.encode(config)
        try fileStore.writeData(data, to: paths.config, options: [])
        print("updated \(paths.config.path)")
    }

    private func resolveBridgedInterface(_ requestedInterface: String?) throws -> VZBridgedNetworkInterface {
        let interfaces = VZBridgedNetworkInterface.networkInterfaces
        guard !interfaces.isEmpty else {
            throw LauncherError.noBridgedInterfaces
        }

        if let requestedInterface, !requestedInterface.isEmpty {
            guard let interface = interfaces.first(where: {
                $0.identifier == requestedInterface || $0.localizedDisplayName == requestedInterface
            }) else {
                throw LauncherError.bridgedInterfaceUnavailable(requestedInterface)
            }
            return interface
        }

        if interfaces.count == 1, let interface = interfaces.first {
            return interface
        }

        let available = interfaces
            .map { "\($0.identifier)\t\($0.localizedDisplayName ?? "")" }
            .joined(separator: "\n")
        throw LauncherError.missingArgument(
            "bridged interface is required. Run `vitalserver-vm interfaces` and choose one.\n\(available)"
        )
    }

    func printUsage() {
        print(
            """
            vitalserver-vm \(Constants.launcherVersion)

            Usage:
              vitalserver-vm init
              vitalserver-vm start
              vitalserver-vm stop
              vitalserver-vm status
              vitalserver-vm network shared
              vitalserver-vm network bridged <interface>
              vitalserver-vm interfaces
              vitalserver-vm configure --cpu <count> --memory-mib <mib> --network shared --vital-files-dir <path>
              vitalserver-vm runtime install
              vitalserver-vm runtime install-provision
              vitalserver-vm runtime status
              vitalserver-vm runtime health
              vitalserver-vm runtime guest-log-sync
              vitalserver-vm runtime watchdog
              vitalserver-vm runtime verify-bundle <bundle.tar.gz>
              vitalserver-vm runtime verify-update-bootstrap <bundle.tar.gz> [--verification-invocation-id <id>]
              vitalserver-vm runtime stage-bundle <bundle.tar.gz>
              vitalserver-vm runtime apply-bundle <bundle.tar.gz> [--allow-unsigned-dev-bundle]
              vitalserver-vm runtime apply-update-bootstrap <bundle.tar.gz> --request-id <id>
              vitalserver-vm runtime rollback [backup-dir]
              vitalserver-vm clean
              vitalserver-vm version

            Environment:
              \(Constants.Environment.vmHome)  Runtime directory. Defaults to \(Constants.Paths.defaultHomeDisplay)
            """
        )
    }
}
