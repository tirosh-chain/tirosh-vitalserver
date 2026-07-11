import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeLiveDiagnosticsReading {
    func loadLiveDiagnostics() -> RuntimeLiveDiagnostics
}

protocol RuntimeProxyPortReading {
    func loadProxyPortReadState() -> RuntimeProxyPortReadState
}

protocol RuntimeVersionReading {
    func loadRuntimeVersionRead() -> RuntimeVersionRead
}

protocol RuntimeLatestBackupReading {
    func loadLatestBackupRead() -> RuntimeLatestBackupRead
}

protocol RuntimeVMLifecycleReading {
    func loadVMLifecycleRead() -> RuntimeVMLifecycleRead
}

struct RuntimeHostStatusOwnerReaderBundle {
    let guestAddressProvider: any RuntimeGuestAddressProvider
    let liveDiagnosticsReader: any RuntimeLiveDiagnosticsReading
    let proxyPortReader: any RuntimeProxyPortReading
    let runtimeVersionReader: any RuntimeVersionReading
    let latestBackupReader: any RuntimeLatestBackupReading
    let vmLifecycleReader: any RuntimeVMLifecycleReading

    static func live(
        runtimeLauncherPath: String = RuntimeControlClientConstants.Paths.launcher,
        fileStore: RuntimeFileStore,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
        runtimeVersionFile: URL = InstalledRuntimePaths.defaultInstalled.runtimeDirectory
            .appendingPathComponent(RuntimePackageArtifactFileNames.runtimeVersion),
        backupsDirectory: URL = InstalledRuntimePaths.defaultInstalled.backupsDirectory,
        vmLifecycleResourceReader: (any RuntimeVMLifecycleResourceReading)? = nil,
        runtimeExecutableState: @escaping (String) -> RuntimeFileState,
        runSyncCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult
    ) -> RuntimeHostStatusOwnerReaderBundle {
        RuntimeHostStatusOwnerReaderBundle(
            guestAddressProvider: guestAddressProvider ?? UnavailableRuntimeGuestAddressProvider(
                reason: "runtime Guest address owner unavailable for status reader"
            ),
            liveDiagnosticsReader: RuntimeHostLiveDiagnosticsReader(
                runtimeLauncherPath: runtimeLauncherPath,
                runtimeExecutableState: runtimeExecutableState,
                runSyncCommand: runSyncCommand
            ),
            proxyPortReader: RuntimeHostProxyPortReader(
                plistPath: InstalledRuntimePaths.defaultInstalled.proxyLaunchDaemon.path,
                fileStore: fileStore
            ),
            runtimeVersionReader: RuntimeHostVersionReader(
                versionFile: runtimeVersionFile,
                fileStore: fileStore
            ),
            latestBackupReader: RuntimeHostLatestBackupReader(
                backupsDirectory: backupsDirectory,
                fileStore: fileStore
            ),
            vmLifecycleReader: RuntimeHostVMLifecycleReader(
                resourceReader: vmLifecycleResourceReader ?? UnavailableRuntimeVMLifecycleResourceReader(
                    reason: "runtime VM lifecycle owner unavailable for status reader"
                )
            )
        )
    }
}

struct RuntimeHostLiveDiagnosticsReader: RuntimeLiveDiagnosticsReading {
    let runtimeLauncherPath: String
    let runtimeExecutableState: (String) -> RuntimeFileState
    let runSyncCommand: @Sendable (String, [String]) -> RuntimeCommandResult

    func loadLiveDiagnostics() -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnosticsReader(
            runtimeLauncherPath: runtimeLauncherPath,
            runtimeExecutableState: runtimeExecutableState,
            launchdServiceState: launchdServiceState
        ).load()
    }

    private func launchdServiceState(_ service: RuntimeManagedService) -> RuntimeServiceState {
        let result = runSyncCommand(
            RuntimeControlClientConstants.Commands.launchctl,
            ["print", "system/\(service.label)"]
        )
        return RuntimeLaunchdServiceStateMapper.state(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            outputIssues: result.outputIssues
        )
    }
}

struct RuntimeHostProxyPortReader: RuntimeProxyPortReading {
    let plistPath: String
    let fileStore: RuntimeFileStore

    func loadProxyPortReadState() -> RuntimeProxyPortReadState {
        RuntimeProxyLaunchDaemonPortReader(
            plistPath: plistPath,
            fileStore: fileStore
        ).loadReadState()
    }
}

struct RuntimeHostVersionReader: RuntimeVersionReading {
    let versionFile: URL
    let fileStore: RuntimeFileStore

    func loadRuntimeVersionRead() -> RuntimeVersionRead {
        let store = RuntimeVersionStore(
            versionFile: versionFile,
            metadata: RuntimeVersionStoreMetadata(
                productIdentifier: RuntimeControlClientConstants.Product.packageIdentifier,
                rootfsBase: RuntimePackageArtifactFileNames.rootfsBase,
                vmDisk: "vm-disk.img"
            ),
            timestamp: { "" },
            versionPathState: { url in
                fileStore.pathState(at: url)
            },
            createDirectory: { _, _ in },
            readData: { url in
                try fileStore.readData(url)
            },
            writeData: { _, _ in }
        )
        switch store.readVersion() {
        case .loaded(let version):
            return RuntimeVersionRead(version: version, issue: nil)
        case .missing:
            return RuntimeVersionRead(
                version: nil,
                issue: PlatformStateReadIssue(
                    source: "runtimeVersion",
                    message: "runtime version document missing path=\(versionFile.path)"
                )
            )
        case .failed(let message):
            return RuntimeVersionRead(
                version: nil,
                issue: PlatformStateReadIssue(source: "runtimeVersion", message: message)
            )
        }
    }
}

struct RuntimeHostLatestBackupReader: RuntimeLatestBackupReading {
    let backupsDirectory: URL
    let fileStore: RuntimeFileStore

    func loadLatestBackupRead() -> RuntimeLatestBackupRead {
        let directoryState = fileStore.pathState(at: backupsDirectory)
        switch directoryState {
        case .directory:
            break
        case .missing:
            return RuntimeLatestBackupRead(
                path: nil,
                issue: PlatformStateReadIssue(
                    source: "latestBackup",
                    message: "backup directory missing path=\(backupsDirectory.path)"
                )
            )
        case .inspectFailed(let reason):
            return RuntimeLatestBackupRead(
                path: nil,
                issue: PlatformStateReadIssue(
                    source: "latestBackup",
                    message: "backup directory inspection failed path=\(backupsDirectory.path) reason=\(reason)"
                )
            )
        case .file, .other, .unknown:
            return RuntimeLatestBackupRead(
                path: nil,
                issue: PlatformStateReadIssue(
                    source: "latestBackup",
                    message: "backup directory path state is unexpected path=\(backupsDirectory.path) state=\(directoryState.rawValue)"
                )
            )
        }
        do {
            let directories = try fileStore.childDirectories(
                at: backupsDirectory,
                nameContains: RuntimeManagedBackupPolicy.nameFragment,
                skipsHiddenFiles: true
            )
            let latest = directories
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .last
            return RuntimeLatestBackupRead(path: latest?.path, issue: nil)
        } catch {
            return RuntimeLatestBackupRead(
                path: nil,
                issue: PlatformStateReadIssue(source: "latestBackup", message: error.localizedDescription)
            )
        }
    }
}

struct RuntimeHostVMLifecycleReader: RuntimeVMLifecycleReading {
    let resourceReader: any RuntimeVMLifecycleResourceReading

    func loadVMLifecycleRead() -> RuntimeVMLifecycleRead {
        RuntimeVMLifecycleResourceReadMapper.statusRead(
            from: resourceReader.loadVMLifecycleResource()
        )
    }
}
