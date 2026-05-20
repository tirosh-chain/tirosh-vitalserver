import Foundation
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
            try ProcessState.status(pidFile: paths.pidFile)
        case .stop:
            try ProcessState.stop(pidFile: paths.pidFile)
        case .network:
            try configureNetwork(paths: paths, arguments: Array(arguments.dropFirst()))
        case .interfaces:
            listInterfaces()
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
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: paths.home.appendingPathComponent(Constants.Paths.imagesDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.home
                .appendingPathComponent(Constants.Paths.dataDirectory)
                .appendingPathComponent(Constants.Paths.vitalFilesDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.home
                .appendingPathComponent(Constants.Paths.dataDirectory)
                .appendingPathComponent(Constants.Paths.vrReleaseDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.home.appendingPathComponent(Constants.Paths.runDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: paths.home.appendingPathComponent(Constants.Paths.logsDirectory),
            withIntermediateDirectories: true
        )

        if !fileManager.fileExists(atPath: paths.config.path) {
            var config = VMRuntimeConfig.default(home: paths.home)
            VMRuntimeConfig.ensureRuntimeDefaults(&config, home: paths.home)
            let data = try JSONEncoder.pretty.encode(config)
            try data.write(to: paths.config)
            print("created \(paths.config.path)")
        } else {
            var config = try VMRuntimeConfig.load(from: paths.config)
            let previous = config
            VMRuntimeConfig.ensureRuntimeDefaults(&config, home: paths.home)
            if config.network.macAddress != previous.network.macAddress
                || config.cloudInitPath != previous.cloudInitPath {
                let data = try JSONEncoder.pretty.encode(config)
                try data.write(to: paths.config)
                print("updated \(paths.config.path) with missing runtime defaults")
            } else {
                print("exists \(paths.config.path)")
            }
        }

        let imagesPath = paths.home.appendingPathComponent(Constants.Paths.imagesDirectory).path
        print("place Linux boot assets under \(imagesPath)")
        print("shared data directory: \(paths.home.appendingPathComponent(Constants.Paths.dataDirectory).path)")
    }

    // Remove disposable VM runtime state while preserving host-bound data.
    func clean(paths: LauncherPaths) throws {
        try ProcessState.stop(pidFile: paths.pidFile)

        let fileManager = FileManager.default
        for url in paths.cleanableRuntimePaths {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("removed \(url.path)")
            }
        }

        let dataPath = paths.home.appendingPathComponent(Constants.Paths.dataDirectory).path
        print("preserved shared data directory: \(dataPath)")
    }

    // Build the VM configuration, start it, then keep the process alive.
    func start(paths: LauncherPaths) throws {
        let config = try VMRuntimeConfig.load(from: paths.config)
        try VMRuntimeConfig.validateBootFiles(config)
        try ProcessState.writeCurrentPid(pidFile: paths.pidFile)

        let configurationFactory = VMConfigurationFactory()
        let vmConfiguration = try configurationFactory.build(from: config)
        let virtualMachine = VZVirtualMachine(configuration: vmConfiguration)
        let delegate = VirtualMachineDelegate(pidFile: paths.pidFile)
        virtualMachine.delegate = delegate

        print("starting vitalserver VM")
        virtualMachine.start { result in
            switch result {
            case .success:
                print("vitalserver VM started")
            case let .failure(error):
                ProcessState.removePidFile(paths.pidFile)
                fputs("failed to start VM: \(error)\n", stderr)
                Foundation.exit(1)
            }
        }

        // Keep the CLI alive while the Virtualization framework owns the VM.
        RunLoop.main.run()
        _ = configurationFactory
        _ = delegate
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

        var config = try VMRuntimeConfig.load(from: paths.config)
        config.network.mode = mode

        switch mode {
        case .shared:
            config.network.bridgedInterface = nil
        case .bridged:
            let interface = try resolveBridgedInterface(arguments.dropFirst().first)
            config.network.bridgedInterface = interface.identifier
        }

        VMRuntimeConfig.ensureRuntimeDefaults(&config, home: paths.home)
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: paths.config)

        switch mode {
        case .shared:
            print("network mode: shared")
        case .bridged:
            print("network mode: bridged")
            print("bridged interface: \(config.network.bridgedInterface ?? "")")
            print("mac address: \(config.network.macAddress ?? "")")
        }
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
              vitalserver-vm clean
              vitalserver-vm version

            Environment:
              \(Constants.Environment.vmHome)  Runtime directory. Defaults to \(Constants.Paths.defaultHomeDisplay)
            """
        )
    }
}
