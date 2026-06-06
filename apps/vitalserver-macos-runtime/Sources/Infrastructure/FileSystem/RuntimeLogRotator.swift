import Application
import Foundation

public struct RuntimeLogRotationConfiguration: Equatable, Sendable {
    public let fileNames: [String]
    public let maxBytes: UInt64
    public let keepCount: Int

    public init(
        fileNames: [String],
        maxBytes: UInt64,
        keepCount: Int
    ) {
        self.fileNames = fileNames
        self.maxBytes = maxBytes
        self.keepCount = keepCount
    }
}

public struct RuntimeLogRotator {
    public let logsDirectory: URL
    public let fileStore: RuntimeFileStore
    public let configuration: RuntimeLogRotationConfiguration
    public let log: (String) -> Void

    public init(
        logsDirectory: URL,
        fileStore: RuntimeFileStore,
        configuration: RuntimeLogRotationConfiguration,
        log: @escaping (String) -> Void
    ) {
        self.logsDirectory = logsDirectory
        self.fileStore = fileStore
        self.configuration = configuration
        self.log = log
    }

    public func rotate() throws {
        guard configuration.keepCount > 0 else {
            return
        }

        for fileName in configuration.fileNames {
            let logFile = logsDirectory.appendingPathComponent(fileName)
            guard fileStore.fileExists(logFile),
                  try fileStore.fileSize(logFile) >= configuration.maxBytes
            else {
                continue
            }

            for index in stride(from: configuration.keepCount - 1, through: 1, by: -1) {
                let source = logsDirectory.appendingPathComponent("\(fileName).\(index)")
                let destination = logsDirectory.appendingPathComponent("\(fileName).\(index + 1)")
                if fileStore.fileExists(destination) {
                    try fileStore.removeItem(at: destination)
                }
                if fileStore.fileExists(source) {
                    try fileStore.moveItem(at: source, to: destination)
                }
            }

            let rotated = logsDirectory.appendingPathComponent("\(fileName).1")
            if fileStore.fileExists(rotated) {
                try fileStore.removeItem(at: rotated)
            }
            try fileStore.moveItem(at: logFile, to: rotated)
            try fileStore.writeData(Data(), to: logFile, options: [])
            log("rotated log file=\(logFile.path)")
        }
    }
}
