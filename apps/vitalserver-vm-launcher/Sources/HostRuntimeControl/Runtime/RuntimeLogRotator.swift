import Foundation
import RuntimeCore

struct RuntimeLogRotator {
    let logsDirectory: URL
    let fileStore: RuntimeFileStore
    let log: (String) -> Void

    func rotate() throws {
        let logFiles = [
            "launcher.log",
            "launchd.out.log",
            "launchd.err.log",
            "proxy.out.log",
            "proxy.err.log",
            "watchdog.out.log",
            "watchdog.err.log",
        ]

        for fileName in logFiles {
            let logFile = logsDirectory.appendingPathComponent(fileName)
            guard fileStore.fileExists(logFile),
                  try fileStore.fileSize(logFile) >= Constants.Runtime.logRotationMaxBytes
            else {
                continue
            }

            for index in stride(from: Constants.Runtime.logRotationKeepCount - 1, through: 1, by: -1) {
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
