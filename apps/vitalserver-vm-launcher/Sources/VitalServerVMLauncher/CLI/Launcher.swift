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
            VMRuntimeConfig.ensureNetworkIdentity(&config)
            let data = try JSONEncoder.pretty.encode(config)
            try data.write(to: paths.config)
            print("created \(paths.config.path)")
        } else {
            var config = try VMRuntimeConfig.load(from: paths.config)
            let previousMacAddress = config.network.macAddress
            VMRuntimeConfig.ensureNetworkIdentity(&config)
            if config.network.macAddress != previousMacAddress {
                let data = try JSONEncoder.pretty.encode(config)
                try data.write(to: paths.config)
                print("updated \(paths.config.path) with stable VM MAC address")
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

        let vmConfiguration = try VMConfigurationFactory().build(from: config)
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

    func printUsage() {
        print(
            """
            vitalserver-vm \(Constants.launcherVersion)

            Usage:
              vitalserver-vm init
              vitalserver-vm start
              vitalserver-vm stop
              vitalserver-vm status
              vitalserver-vm interfaces
              vitalserver-vm clean
              vitalserver-vm version

            Environment:
              \(Constants.Environment.vmHome)  Runtime directory. Defaults to \(Constants.Paths.defaultHomeDisplay)
            """
        )
    }
}
