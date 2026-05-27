import Foundation

struct RuntimeConfigureCommand: Equatable {
    let changes: [RuntimeConfigureChange]
    let restart: Bool

    init(changes: [RuntimeConfigureChange] = [], restart: Bool = false) {
        self.changes = changes
        self.restart = restart
    }
}

enum RuntimeConfigureChange: Equatable {
    case cpu(Int)
    case memoryGiB(UInt64)
    case diskGiB(Int)
    case network(NetworkMode)
    case bridgedInterface(String)
    case proxyPort(Int)
    case vitalFilesDirectory(URL)
    case publicHost(String)
    case publicPort(Int)
    case adminPassword(String)
    case adminPasswordFile(URL)
    case startOnBoot(Bool)
    case autoRecovery(Bool)
    case preventSystemSleep(Bool)
    case redisBackupRetention(Int)
}
