import Foundation

do {
    try BundleOwnedProductUpdateRunner().run(
        arguments: Array(CommandLine.arguments.dropFirst())
    )
} catch {
    fputs("product update runner failed: \(error)\n", stderr)
    Foundation.exit(1)
}
