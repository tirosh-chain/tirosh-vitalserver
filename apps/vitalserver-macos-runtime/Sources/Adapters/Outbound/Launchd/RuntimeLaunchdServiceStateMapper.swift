import Contracts
import Foundation

/// Maps launchctl command results to typed state using the exit code only.
/// Classification never reads stderr/stdout text, so it is stable across
/// locales.
///
/// Exit code contract (documented, locale-independent):
/// - `0`     success (`print` = loaded; `bootout`/`bootstrap` = accepted)
/// - `3`     "no such process" (service not loaded)
/// - `113`   "could not find service" (service not found in domain)
/// - `1`     EPERM (operation not permitted / permission denied)
/// - `13`    EACCES (permission denied)
/// - other   read/command failure
enum RuntimeLaunchdServiceStateMapper {
    static let notLoadedExitCodes: Set<Int32> = [3, 113]
    static let permissionDeniedExitCodes: Set<Int32> = [1, 13]

    static func state(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue]
    ) -> RuntimeServiceState {
        if exitCode == 0 {
            return .loaded
        }
        let message = commandFailureMessage(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            outputIssues: outputIssues
        )
        if notLoadedExitCodes.contains(exitCode) {
            return .notLoaded
        }
        if permissionDeniedExitCodes.contains(exitCode) {
            return .permissionDenied(message)
        }
        return .readFailed(message)
    }

    static func launchdOutcome(
        action: HostPlatformLaunchdAction,
        exitCode: Int32
    ) -> HostPlatformLaunchdOutcome {
        switch action {
        case .print:
            if exitCode == 0 {
                return .loaded
            }
            if notLoadedExitCodes.contains(exitCode) {
                return .notLoaded
            }
            if permissionDeniedExitCodes.contains(exitCode) {
                return .permissionDenied
            }
            return .failed
        case .bootout:
            if exitCode == 0 {
                return .accepted
            }
            if notLoadedExitCodes.contains(exitCode) {
                return .alreadyNotLoaded
            }
            if permissionDeniedExitCodes.contains(exitCode) {
                return .permissionDenied
            }
            return .failed
        case .bootstrap:
            if exitCode == 0 {
                return .accepted
            }
            if permissionDeniedExitCodes.contains(exitCode) {
                return .permissionDenied
            }
            return .failed
        }
    }

    static func commandFailureMessage(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue]
    ) -> String {
        let stderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(exitCode) stdout=\(stdout)"
        }
        let outputIssueSummary = outputIssues
            .map { "\($0.stream.rawValue): \($0.message)" }
            .joined(separator: "; ")
        if !outputIssueSummary.isEmpty {
            return "exitCode=\(exitCode) outputIssues=\(outputIssueSummary)"
        }
        return "exitCode=\(exitCode)"
    }
}
