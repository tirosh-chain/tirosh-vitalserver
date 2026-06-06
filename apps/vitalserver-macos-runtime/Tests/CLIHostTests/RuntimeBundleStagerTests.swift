import Contracts
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeBundleStagerTests: XCTestCase {
    func testStageCreatesManagedDirectoryRemovesExistingDestinationChecksSpaceAndCopies() throws {
        let source = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let bundle = URL(fileURLWithPath: "/tmp/update-bundle")
        let bundlesDirectory = URL(fileURLWithPath: "/product/bundles")
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-1.2.3")
        var events: [String] = []
        let stager = RuntimeBundleStager(
            context: RuntimeBundleStagingContext(
                bundlesDirectory: bundlesDirectory,
                updateFreeSpaceMarginBytes: 4_096
            ),
            operations: RuntimeBundleStagingOperations(
                directorySize: { url in
                    events.append("directory-size:\(url.path)")
                    return 1_024
                },
                compressedSourceSize: { url in
                    events.append("compressed-size:\(url.path)")
                    return 512
                },
                fileExists: { $0 == destination },
                directoryExists: { _ in false },
                createDirectory: { url, withIntermediateDirectories in
                    events.append("create:\(url.path):\(withIntermediateDirectories)")
                },
                removeItem: { url in
                    events.append("remove:\(url.path)")
                },
                copyItem: { source, destination in
                    events.append("copy:\(source.path)->\(destination.path)")
                },
                requireFreeSpace: { url, bytes, operation in
                    events.append("free-space:\(url.path):\(bytes):\(operation.rawValue)")
                },
                log: { message in
                    events.append("log:\(message)")
                }
            )
        )

        let staged = try stager.stage(input: RuntimeBundleStagingInput(
            sourceURL: source,
            bundleURL: bundle,
            manifestVersion: "1.2.3"
        ))

        XCTAssertEqual(staged, destination)
        XCTAssertEqual(events, [
            "directory-size:/tmp/update-bundle",
            "create:/product/bundles:true",
            "log:removing existing staged bundle path=/product/bundles/update-bundle-1.2.3",
            "remove:/product/bundles/update-bundle-1.2.3",
            "compressed-size:/input/update-bundle.tar.gz",
            "free-space:/product/bundles:5632:stage-bundle",
            "log:copying bundle to managed storage source=/tmp/update-bundle destination=/product/bundles/update-bundle-1.2.3 size=0.0 MiB",
            "copy:/tmp/update-bundle->/product/bundles/update-bundle-1.2.3",
            "log:bundle stage completed destination=/product/bundles/update-bundle-1.2.3",
        ])
    }

    func testStageDoesNotCopyWhenExistingDestinationRemovalFails() {
        let source = URL(fileURLWithPath: "/input/update-bundle")
        let bundle = URL(fileURLWithPath: "/tmp/update-bundle")
        let bundlesDirectory = URL(fileURLWithPath: "/product/bundles")
        let destination = bundlesDirectory.appendingPathComponent("update-bundle-1.2.3")
        var copied = false
        let stager = RuntimeBundleStager(
            context: RuntimeBundleStagingContext(
                bundlesDirectory: bundlesDirectory,
                updateFreeSpaceMarginBytes: 0
            ),
            operations: RuntimeBundleStagingOperations(
                directorySize: { _ in 0 },
                compressedSourceSize: { _ in 0 },
                fileExists: { $0 == destination },
                directoryExists: { _ in false },
                createDirectory: { _, _ in },
                removeItem: { _ in throw TestBundleStagerError.removeFailed },
                copyItem: { _, _ in copied = true },
                requireFreeSpace: { _, _, _ in },
                log: { _ in }
            )
        )

        XCTAssertThrowsError(try stager.stage(input: RuntimeBundleStagingInput(
            sourceURL: source,
            bundleURL: bundle,
            manifestVersion: "1.2.3"
        ))) { error in
            XCTAssertEqual(error as? TestBundleStagerError, .removeFailed)
        }
        XCTAssertFalse(copied)
    }
}

private enum TestBundleStagerError: Error, Equatable {
    case removeFailed
}
