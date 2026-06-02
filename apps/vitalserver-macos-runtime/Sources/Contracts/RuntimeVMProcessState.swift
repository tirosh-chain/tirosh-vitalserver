import Foundation

public enum RuntimeVMProcessState: Codable, Equatable, Sendable {
    case pidFileMissing
    case pidFileInvalid(String)
    case running(pid: Int32)
    case stopped
    case stalePid(pid: Int32)
    case signalFailed(pid: Int32, signal: Int32, errnoCode: Int32)
    case stopTimedOut(pid: Int32, timeoutSeconds: Int)
    case readFailed(String)
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "pid-file-missing":
            self = .pidFileMissing
        case "stopped":
            self = .stopped
        default:
            if rawValue.hasPrefix("pid-file-invalid: ") {
                self = .pidFileInvalid(String(rawValue.dropFirst("pid-file-invalid: ".count)))
            } else if rawValue.hasPrefix("running: pid="),
                      let pid = Int32(String(rawValue.dropFirst("running: pid=".count))) {
                self = .running(pid: pid)
            } else if rawValue.hasPrefix("stale-pid: pid="),
                      let pid = Int32(String(rawValue.dropFirst("stale-pid: pid=".count))) {
                self = .stalePid(pid: pid)
            } else if rawValue.hasPrefix("signal-failed: ") {
                self = Self.parseSignalFailed(rawValue) ?? .unknown(rawValue)
            } else if rawValue.hasPrefix("stop-timed-out: ") {
                self = Self.parseStopTimedOut(rawValue) ?? .unknown(rawValue)
            } else if rawValue.hasPrefix("read-failed: ") {
                self = .readFailed(String(rawValue.dropFirst("read-failed: ".count)))
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .pidFileMissing:
            return "pid-file-missing"
        case .pidFileInvalid(let reason):
            return "pid-file-invalid: \(reason)"
        case .running(let pid):
            return "running: pid=\(pid)"
        case .stopped:
            return "stopped"
        case .stalePid(let pid):
            return "stale-pid: pid=\(pid)"
        case .signalFailed(let pid, let signal, let errnoCode):
            return "signal-failed: pid=\(pid) signal=\(signal) errno=\(errnoCode)"
        case .stopTimedOut(let pid, let timeoutSeconds):
            return "stop-timed-out: pid=\(pid) timeout-seconds=\(timeoutSeconds)"
        case .readFailed(let reason):
            return "read-failed: \(reason)"
        case .unknown(let value):
            return value
        }
    }

    public var blocksUninstallCleanup: Bool {
        switch self {
        case .pidFileMissing, .running, .pidFileInvalid, .signalFailed, .stopTimedOut, .readFailed, .unknown:
            return true
        case .stopped, .stalePid:
            return false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parseSignalFailed(_ rawValue: String) -> RuntimeVMProcessState? {
        let values = keyValues(from: rawValue, prefix: "signal-failed: ")
        guard
            let pid = values["pid"].flatMap(Int32.init),
            let signal = values["signal"].flatMap(Int32.init),
            let errnoCode = values["errno"].flatMap(Int32.init)
        else {
            return nil
        }
        return .signalFailed(pid: pid, signal: signal, errnoCode: errnoCode)
    }

    private static func parseStopTimedOut(_ rawValue: String) -> RuntimeVMProcessState? {
        let values = keyValues(from: rawValue, prefix: "stop-timed-out: ")
        guard
            let pid = values["pid"].flatMap(Int32.init),
            let timeoutSeconds = values["timeout-seconds"].flatMap(Int.init)
        else {
            return nil
        }
        return .stopTimedOut(pid: pid, timeoutSeconds: timeoutSeconds)
    }

    private static func keyValues(from rawValue: String, prefix: String) -> [String: String] {
        let body = rawValue.dropFirst(prefix.count)
        var values: [String: String] = [:]
        for component in body.split(separator: " ") {
            let parts = component.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            values[String(parts[0])] = String(parts[1])
        }
        return values
    }
}
