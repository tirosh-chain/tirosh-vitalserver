import Contracts
import Foundation

enum RuntimeLsofListenerParser {
    static func parse(_ output: String) throws -> [RuntimeHostProxyListener] {
        try output
            .split(separator: "\n")
            .dropFirst()
            .map { line in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else {
                    throw RuntimeLsofListenerParseError.malformedLine(String(line))
                }
                return RuntimeHostProxyListener(command: String(fields[0]), pid: String(fields[1]))
            }
    }
}

enum RuntimeLsofListenerParseError: Error, CustomStringConvertible, Equatable {
    case malformedLine(String)

    var description: String {
        switch self {
        case .malformedLine(let line):
            return "malformed lsof listener line=\(line)"
        }
    }
}
