import Foundation
import Application
import RuntimeControl
import Contracts

struct VMConfigDocument: Decodable {
    let cpuCount: Int
    let memoryMiB: UInt64
    let network: NetworkDocument
    let vitalFilesDirectory: SharedDirectoryDocument?
    let autoRecoveryEnabled: Bool?
    let preventSystemSleep: Bool?

    static func loadResult(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput> {
        let url = URL(fileURLWithPath: path)
        switch runtimeSettingsReadableFileState(url, fileStore: fileStore) {
        case .loaded:
            break
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(VMConfigDocument.self, from: data).runtimeSettingsReadInput)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var runtimeSettingsReadInput: RuntimeVMConfigSettingsReadInput {
        RuntimeVMConfigSettingsReadInput(
            cpuCount: cpuCount,
            memoryMiB: memoryMiB,
            networkMode: network.mode,
            bridgedInterface: network.bridgedInterface,
            vitalFilesDirectoryHostPath: vitalFilesDirectory?.hostPath,
            autoRecoveryEnabled: autoRecoveryEnabled,
            preventSystemSleep: preventSystemSleep
        )
    }
}

struct NetworkDocument: Decodable {
    let mode: String
    let bridgedInterface: String?
}

struct SharedDirectoryDocument: Decodable {
    let hostPath: String
}

struct GuestRuntimeSettings: Decodable {
    let vitalServerURL: String
    let remoteConsoleURL: String
    let publicHost: String
    let publicPort: Int
    let automaticBackupEnabled: Bool
    let backupScheduleTimes: [String]
    let backupRetentionCount: Int

    static func loadResult(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeSettingsReadResult<RuntimeGuestRuntimeSettingsReadInput> {
        let url = URL(fileURLWithPath: path)
        switch runtimeSettingsReadableFileState(url, fileStore: fileStore) {
        case .loaded:
            break
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(GuestRuntimeSettings.self, from: data).runtimeSettingsReadInput)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var runtimeSettingsReadInput: RuntimeGuestRuntimeSettingsReadInput {
        RuntimeGuestRuntimeSettingsReadInput(
            vitalServerURL: vitalServerURL,
            remoteConsoleURL: remoteConsoleURL,
            publicHost: publicHost,
            publicPort: publicPort,
            automaticBackupEnabled: automaticBackupEnabled,
            backupScheduleTimes: backupScheduleTimes,
            backupRetentionCount: backupRetentionCount
        )
    }
}

func runtimeSettingsReadableFileState(
    _ url: URL,
    fileStore: RuntimeFileReading
) -> RuntimeSettingsReadResult<Void> {
    let state = fileStore.pathState(at: url)
    switch state {
    case .file:
        return .loaded(())
    case .missing:
        return .missing
    case .inspectFailed(let reason):
        return .failed("path inspection failed path=\(url.path) reason=\(reason)")
    case .directory, .other, .unknown:
        return .failed("path state is unexpected path=\(url.path) state=\(state.rawValue)")
    }
}
