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
            return decodeResult(data)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func decodeResult(_ data: Data) -> RuntimeSettingsReadResult<RuntimeVMConfigSettingsReadInput> {
        do {
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
    enum CodingKeys: String, CodingKey {
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case recorderIngressSendDataMode
        case recorderIngressSendDataReplayBatchSize
        case recorderIngressSendDataReplayMaxMiBPerSecond
        case recorderIngress
        case containerMemoryLimitsEnabled
        case vitalServerContainerMemoryLimitMiB
        case recorderIngressContainerMemoryLimitMiB
        case redisContainerMemoryLimitMiB
        case automaticBackupEnabled
        case backupScheduleTimes
        case backupRetentionCount
    }

    let vitalServerURL: String
    let remoteConsoleURL: String
    let publicHost: String
    let publicPort: Int
    let recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode
    let recorderIngressSendDataReplayBatchSize: Int
    let recorderIngressSendDataReplayMaxMiBPerSecond: Int
    let recorderIngress: RuntimeRecorderIngressSettings
    let containerMemoryLimitsEnabled: Bool
    let vitalServerContainerMemoryLimitMiB: Int
    let recorderIngressContainerMemoryLimitMiB: Int
    let redisContainerMemoryLimitMiB: Int
    let automaticBackupEnabled: Bool
    let backupScheduleTimes: [String]
    let backupRetentionCount: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vitalServerURL = try container.decode(String.self, forKey: .vitalServerURL)
        remoteConsoleURL = try container.decode(String.self, forKey: .remoteConsoleURL)
        publicHost = try container.decode(String.self, forKey: .publicHost)
        publicPort = try container.decode(Int.self, forKey: .publicPort)
        recorderIngressSendDataMode = try container.decodeIfPresent(
            RuntimeRecorderIngressSendDataMode.self,
            forKey: .recorderIngressSendDataMode
        ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataMode
        recorderIngressSendDataReplayBatchSize = try container.decodeIfPresent(
            Int.self,
            forKey: .recorderIngressSendDataReplayBatchSize
        ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataReplayBatchSize
        recorderIngressSendDataReplayMaxMiBPerSecond = try container.decodeIfPresent(
            Int.self,
            forKey: .recorderIngressSendDataReplayMaxMiBPerSecond
        ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataReplayMaxMiBPerSecond
        recorderIngress = try container.decodeIfPresent(
            RuntimeRecorderIngressSettings.self,
            forKey: .recorderIngress
        ) ?? RuntimeRecorderIngressSettings()
        containerMemoryLimitsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .containerMemoryLimitsEnabled
        ) ?? RuntimeSettingsInitialValues.containerMemoryLimitsEnabled
        vitalServerContainerMemoryLimitMiB = try container.decodeIfPresent(
            Int.self,
            forKey: .vitalServerContainerMemoryLimitMiB
        ) ?? RuntimeSettingsInitialValues.vitalServerContainerMemoryLimitMiB
        recorderIngressContainerMemoryLimitMiB = try container.decodeIfPresent(
            Int.self,
            forKey: .recorderIngressContainerMemoryLimitMiB
        ) ?? RuntimeSettingsInitialValues.recorderIngressContainerMemoryLimitMiB
        redisContainerMemoryLimitMiB = try container.decodeIfPresent(
            Int.self,
            forKey: .redisContainerMemoryLimitMiB
        ) ?? RuntimeSettingsInitialValues.redisContainerMemoryLimitMiB
        automaticBackupEnabled = try container.decode(Bool.self, forKey: .automaticBackupEnabled)
        backupScheduleTimes = try container.decode([String].self, forKey: .backupScheduleTimes)
        backupRetentionCount = try container.decode(Int.self, forKey: .backupRetentionCount)
    }

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
            return decodeResult(data)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func decodeResult(
        _ data: Data
    ) -> RuntimeSettingsReadResult<RuntimeGuestRuntimeSettingsReadInput> {
        do {
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
            recorderIngressSendDataMode: recorderIngressSendDataMode,
            recorderIngressSendDataReplayBatchSize: recorderIngressSendDataReplayBatchSize,
            recorderIngressSendDataReplayMaxMiBPerSecond: recorderIngressSendDataReplayMaxMiBPerSecond,
            recorderIngress: recorderIngress,
            containerMemoryLimitsEnabled: containerMemoryLimitsEnabled,
            vitalServerContainerMemoryLimitMiB: vitalServerContainerMemoryLimitMiB,
            recorderIngressContainerMemoryLimitMiB: recorderIngressContainerMemoryLimitMiB,
            redisContainerMemoryLimitMiB: redisContainerMemoryLimitMiB,
            automaticBackupEnabled: automaticBackupEnabled,
            backupScheduleTimes: backupScheduleTimes,
            backupRetentionCount: backupRetentionCount
        )
    }
}

public struct RuntimeControlSettingsDocument: Codable, Equatable {
    public let logArchiveRetentionDays: Int
    public let logArchiveMaximumGiB: Int
    public let runtimeControlPort: Int

    enum CodingKeys: String, CodingKey {
        case logArchiveRetentionDays
        case logArchiveMaximumGiB
        case runtimeControlPort
    }

    public init(
        logArchiveRetentionDays: Int = RuntimeSettingsInitialValues.logArchiveRetentionDays,
        logArchiveMaximumGiB: Int = RuntimeSettingsInitialValues.logArchiveMaximumGiB,
        runtimeControlPort: Int = RuntimeSettingsInitialValues.runtimeControlPort
    ) {
        self.logArchiveRetentionDays = logArchiveRetentionDays
        self.logArchiveMaximumGiB = logArchiveMaximumGiB
        self.runtimeControlPort = runtimeControlPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            logArchiveRetentionDays: try container.decodeIfPresent(
                Int.self,
                forKey: .logArchiveRetentionDays
            ) ?? RuntimeSettingsInitialValues.logArchiveRetentionDays,
            logArchiveMaximumGiB: try container.decodeIfPresent(
                Int.self,
                forKey: .logArchiveMaximumGiB
            ) ?? RuntimeSettingsInitialValues.logArchiveMaximumGiB,
            runtimeControlPort: try container.decodeIfPresent(
                Int.self,
                forKey: .runtimeControlPort
            ) ?? RuntimeSettingsInitialValues.runtimeControlPort
        )
    }

    public static func loadResult(
        path: String,
        fileStore: RuntimeFileReading
    ) -> RuntimeSettingsReadResult<RuntimeLogArchiveSettingsReadInput> {
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
            return try .loaded(JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: data).runtimeSettingsReadInput)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var runtimeSettingsReadInput: RuntimeLogArchiveSettingsReadInput {
        RuntimeLogArchiveSettingsReadInput(
            retentionDays: logArchiveRetentionDays,
            maximumGiB: logArchiveMaximumGiB,
            runtimeControlPort: runtimeControlPort
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
