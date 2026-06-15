import Foundation
import Errors

do {
    try Launcher().run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("error: \(error)\n", stderr)
    Foundation.exit(1)
}
