import Foundation
import Core
import Contracts
import HostInfrastructure
import Virtualization

struct Launcher {
    // Keep command routing here so `main.swift` stays as the process entry only.
    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        let paths = LauncherPaths.resolve()
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
                || config.cloudInitPath != previous.cloudInitPath {
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
        let config = try VMRuntimeConfig.load(from: paths.config, fileStore: fileStore)
        try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore)
        try removeStaleRuntimeState(paths: paths, fileStore: fileStore)
        try ProcessState.writeCurrentPid(pidFile: paths.pidFile, fileStore: fileStore)

        let configurationFactory = VMConfigurationFactory(fileStore: fileStore)
        let vmConfiguration = try configurationFactory.build(from: config)
        let virtualMachine = VZVirtualMachine(configuration: vmConfiguration)
        let delegate = VirtualMachineDelegate(pidFile: paths.pidFile, fileStore: fileStore)
        let terminationHandler = VirtualMachineTerminationHandler(
            virtualMachine: virtualMachine,
            pidFile: paths.pidFile,
            fileStore: fileStore
        )
        virtualMachine.delegate = delegate
        terminationHandler.start()

        print("starting vitalserver VM")
        virtualMachine.start { result in
            switch result {
            case .success:
                print("vitalserver VM started")
            case let .failure(error):
                ProcessState.removePidFile(paths.pidFile, fileStore: fileStore)
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

    private func removeStaleRuntimeState(
        paths: LauncherPaths,
        fileStore: RuntimeFileReading & RuntimeFileWriting
    ) throws {
        for url in [paths.installed.runtimeState, paths.installed.vmIPFile] {
            if fileStore.fileExists(url) {
                try fileStore.removeItem(at: url)
                print("removed stale runtime state: \(url.path)")
            }
        }
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
        guard let mode = NetworkMode(rawValue: modeValue) else {
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
                guard let cpu = Int(value),
                      cpu >= Constants.Defaults.minimumCPUCount,
                      cpu <= Constants.Defaults.maximumAllowedCPUCount else {
                    throw LauncherError.missingArgument(
                        "--cpu must be between \(Constants.Defaults.minimumCPUCount) and \(Constants.Defaults.maximumAllowedCPUCount)"
                    )
                }
                config.cpuCount = cpu
            case "--memory-mib":
                guard let memory = UInt64(value),
                      memory >= UInt64(Constants.Defaults.minimumMemoryGiB * 1024),
                      memory <= Constants.Defaults.maximumAllowedMemoryMiB else {
                    throw LauncherError.missingArgument(
                        "--memory-mib must be between \(Constants.Defaults.minimumMemoryGiB * 1024) and \(Constants.Defaults.maximumAllowedMemoryMiB)"
                    )
                }
                config.memoryMiB = memory
            case "--network":
                guard let mode = NetworkMode(rawValue: value) else {
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
              vitalserver-vm runtime status
              vitalserver-vm runtime health
              vitalserver-vm runtime guest-log-sync
              vitalserver-vm runtime watchdog
              vitalserver-vm runtime verify-bundle <bundle.tar.gz>
              vitalserver-vm runtime stage-bundle <bundle.tar.gz>
              vitalserver-vm runtime apply-bundle <bundle.tar.gz>
              vitalserver-vm runtime rollback [backup-dir]
              vitalserver-vm clean
              vitalserver-vm version

            Environment:
              \(Constants.Environment.vmHome)  Runtime directory. Defaults to \(Constants.Paths.defaultHomeDisplay)
            """
        )
    }
}
