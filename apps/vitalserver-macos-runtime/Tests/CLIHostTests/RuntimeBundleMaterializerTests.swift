import Contracts
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeBundleMaterializerTests: XCTestCase {
    func testMaterializeReturnsDirectoryInputWithoutTemporaryRoot() throws {
        let bundleURL = URL(fileURLWithPath: "/input/update-bundle")
        var events: [String] = []
        let materializer = makeMaterializer(
            directoryExists: { url in
                events.append("dir:\(url.path)")
                return url == bundleURL
            }
        )

        let materialized = try materializer.materialize(bundleURL)

        XCTAssertEqual(materialized, RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: nil))
        XCTAssertEqual(events, ["dir:/input/update-bundle"])
    }

    func testMaterializeExtractsArchiveIntoTemporaryRootAndRequiresExtractedDirectory() throws {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test")
        let extractedBundle = temporaryRoot.appendingPathComponent("update-bundle", isDirectory: true)
        var events: [String] = []
        let materializer = makeMaterializer(
            directoryExists: { url in
                events.append("dir:\(url.path)")
                return url == extractedBundle
            },
            fileExists: { url in
                events.append("file:\(url.path)")
                return url == archiveURL
            },
            temporaryRoot: {
                events.append("temporary-root")
                return temporaryRoot
            },
            createDirectory: { url, withIntermediateDirectories in
                events.append("create:\(url.path):\(withIntermediateDirectories)")
            },
            runProcess: { executable, arguments in
                events.append("process:\(executable) \(arguments.joined(separator: " "))")
                if arguments.first == "-tzf" {
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: "update-bundle/\nupdate-bundle/manifest.json\n",
                        stderr: ""
                    )
                }
                return RuntimeProcessResult(
                    exitCode: 0,
                    stdout: "drwxr-xr-x 0 root wheel 0 Jan 1 00:00 update-bundle/\n",
                    stderr: ""
                )
            },
            runRequired: { executable, arguments in
                events.append("required:\(executable) \(arguments.joined(separator: " "))")
            },
            log: { message in
                events.append("log:\(message)")
            }
        )

        let materialized = try materializer.materialize(archiveURL)

        XCTAssertEqual(materialized, RuntimeMaterializedBundle(bundleURL: extractedBundle, temporaryRoot: temporaryRoot))
        XCTAssertEqual(events, [
            "dir:/input/update-bundle.tar.gz",
            "file:/input/update-bundle.tar.gz",
            "temporary-root",
            "create:/tmp/tirosh-update-bundle-test:true",
            "process:/usr/bin/tar -tzf /input/update-bundle.tar.gz",
            "process:/usr/bin/tar -tvzf /input/update-bundle.tar.gz",
            "required:/usr/bin/tar -xzf /input/update-bundle.tar.gz -C /tmp/tirosh-update-bundle-test",
            "dir:/tmp/tirosh-update-bundle-test/update-bundle",
            "log:bundle archive extracted source=/input/update-bundle.tar.gz destination=/tmp/tirosh-update-bundle-test/update-bundle",
        ])
    }

    func testMaterializeLogsArchiveListFailureAndUsesInvalidArchiveError() {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        var logs: [String] = []
        let materializer = makeMaterializer(
            fileExists: { _ in true },
            runProcess: { _, _ in
                RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "not gzip")
            },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try materializer.materialize(archiveURL)) { error in
            XCTAssertEqual(error as? TestBundleMaterializerError, .invalidArchive(archiveURL.path))
        }
        XCTAssertEqual(logs, ["bundle archive list failed stderr=not gzip"])
    }

    func testMaterializeMapsArchiveValidationFailure() {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let materializer = makeMaterializer(
            fileExists: { _ in true },
            runProcess: { _, arguments in
                if arguments.first == "-tzf" {
                    return RuntimeProcessResult(exitCode: 0, stdout: "../escape\n", stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        XCTAssertThrowsError(try materializer.materialize(archiveURL)) { error in
            XCTAssertEqual(
                error as? TestBundleMaterializerError,
                .validation("unsafe update bundle archive path: ../escape")
            )
        }
    }

    private func makeMaterializer(
        directoryExists: @escaping (URL) -> Bool = { _ in false },
        fileExists: @escaping (URL) -> Bool = { _ in false },
        temporaryRoot: @escaping () -> URL = { URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test") },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult = { _, _ in
            RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
        },
        runRequired: @escaping (String, [String]) throws -> Void = { _, _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundleMaterializer {
        RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(tarExecutable: "/usr/bin/tar"),
            operations: RuntimeBundleMaterializationOperations(
                directoryExists: directoryExists,
                fileExists: fileExists,
                temporaryRoot: temporaryRoot,
                createDirectory: createDirectory,
                runProcess: runProcess,
                runRequired: runRequired,
                missingFileError: { TestBundleMaterializerError.missingFile($0.path) },
                invalidArchiveError: { TestBundleMaterializerError.invalidArchive($0.path) },
                archiveValidationError: { TestBundleMaterializerError.validation($0.description) },
                log: log
            )
        )
    }
}

private enum TestBundleMaterializerError: Error, Equatable {
    case missingFile(String)
    case invalidArchive(String)
    case validation(String)
}
