import Application
import Contracts
import Foundation
import Errors

public struct RuntimeConfigureCommand: Equatable, Sendable {
    public let changes: [RuntimeConfigureChange]
    public let activation: ConfigureRuntimeActivationIntent

    public var restart: Bool {
        activation != .saveOnly
    }

    public init(changes: [RuntimeConfigureChange] = [], restart: Bool = false) {
        self.changes = changes
        self.activation = restart ? .activateChangedComponents : .saveOnly
    }

    public init(
        changes: [RuntimeConfigureChange] = [],
        activation: ConfigureRuntimeActivationIntent
    ) {
        self.changes = changes
        self.activation = activation
    }
}

public enum RuntimeConfigureChange: Equatable, Sendable {
    case cpu(Int)
    case memoryGiB(UInt64)
    case diskGiB(Int)
    case network(RuntimeNetworkMode)
    case bridgedInterface(String)
    case proxyPort(Int)
    case runtimeControlPort(Int)
    case vitalFilesDirectory(URL)
    case vitalServerURL(String)
    case remoteConsoleURL(String)
    case publicHost(String)
    case publicPort(Int)
    case recorderIngressSendDataMode(RuntimeRecorderIngressSendDataMode)
    case recorderIngressSendDataReplayBatchSize(Int)
    case recorderIngressSendDataReplayMaxMiBPerSecond(Int)
    case recorderIngressSettingsFile(URL)
    case containerMemoryLimitsEnabled(Bool)
    case vitalServerContainerMemoryLimitMiB(Int)
    case recorderIngressContainerMemoryLimitMiB(Int)
    case redisContainerMemoryLimitMiB(Int)
    case adminPassword(String)
    case adminPasswordFile(URL)
    case startOnBoot(Bool)
    case autoRecovery(Bool)
    case preventSystemSleep(Bool)
    case automaticBackup(Bool)
    case backupScheduleTimes([String])
    case backupRetention(Int)
    case logArchiveRetentionDays(Int)
    case logArchiveMaximumGiB(Int)
}
