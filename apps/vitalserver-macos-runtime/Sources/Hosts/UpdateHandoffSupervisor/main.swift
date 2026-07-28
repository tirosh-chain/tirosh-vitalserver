import Foundation

do {
    try UpdateHandoffSupervisorHost().run(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
} catch {
    fputs("update handoff supervisor failed: \(error)\n", stderr)
    Foundation.exit(1)
}
