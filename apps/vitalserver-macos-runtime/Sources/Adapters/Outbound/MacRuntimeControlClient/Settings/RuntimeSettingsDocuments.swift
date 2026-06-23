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
    enum CodingKeys: String, CodingKey {
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case recorderIngressSendDataMode
        case recorderIngressSendDataReplayBatchSize
        case recorderIngressSendDataReplayRateLimitPerSecond
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
    let recorderIngressSendDataReplayRateLimitPerSecond: Int
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
        recorderIngressSendDataReplayRateLimitPerSecond = try container.decodeIfPresent(
            Int.self,
            forKey: .recorderIngressSendDataReplayRateLimitPerSecond
        ) ?? RuntimeSettingsInitialValues.recorderIngressSendDataReplayRateLimitPerSecond
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
            recorderIngressSendDataReplayRateLimitPerSecond: recorderIngressSendDataReplayRateLimitPerSecond,
            automaticBackupEnabled: automaticBackupEnabled,
            backupScheduleTimes: backupScheduleTimes,
            backupRetentionCount: backupRetentionCount
        )
    }
}

public struct RuntimeControlSettingsDocument: Codable, Equatable {
    public let logArchiveRetentionDays: Int
    public let logArchiveMaximumGiB: Int
    public let redisRelay: RuntimeRedisRelaySettings

    enum CodingKeys: String, CodingKey {
        case logArchiveRetentionDays
        case logArchiveMaximumGiB
        case redisRelay
    }

    public init(
        logArchiveRetentionDays: Int = RuntimeSettingsInitialValues.logArchiveRetentionDays,
        logArchiveMaximumGiB: Int = RuntimeSettingsInitialValues.logArchiveMaximumGiB,
        redisRelay: RuntimeRedisRelaySettings = RuntimeRedisRelaySettings()
    ) {
        self.logArchiveRetentionDays = logArchiveRetentionDays
        self.logArchiveMaximumGiB = logArchiveMaximumGiB
        self.redisRelay = redisRelay
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
            redisRelay: try container.decodeIfPresent(
                RuntimeRedisRelaySettings.self,
                forKey: .redisRelay
            ) ?? RuntimeRedisRelaySettings()
        )
    }

    static func loadResult(
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
            redisRelay: redisRelay
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
