import Foundation

enum RuntimeShellCommandFactory {
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        var parts: [String] = []
        if executable == RuntimeControlClientConstants.Paths.launcher {
            parts.append(shellQuote(RuntimeControlClientConstants.Commands.env))
            parts.append("\(RuntimeControlClientConstants.Environment.vmHome)=\(shellQuote(RuntimeControlClientConstants.Paths.vmHome))")
        }
        parts += ([executable] + arguments).map(shellQuote)
        return parts.joined(separator: " ")
    }

    static func commandWithLog(_ shellCommand: String) -> String {
        let logFile = shellQuote(RuntimeControlClientConstants.Paths.commandLogFile)
        let script = [
            "rm -f \(logFile)",
            "{ \(shellCommand); } > \(logFile) 2>&1",
            "status=$?",
            "tail -n 200 \(logFile)",
            "exit $status"
        ].joined(separator: "; ")
        return "/bin/bash -lc \(shellQuote(script))"
    }

    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
