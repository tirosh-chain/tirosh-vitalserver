import Contracts
import Application
import Domain
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeBundleMaterializerTests: XCTestCase {
    func testMaterializeReturnsDirectoryInputWithoutTemporaryRoot() throws {
        let bundleURL = URL(fileURLWithPath: "/input/update-bundle")
        var events: [String] = []
        let materializer = makeMaterializer(
            pathState: { url in
                events.append("path:\(url.path)")
                return url == bundleURL ? .directory : .missing
            }
        )

        let materialized = try materializer.materialize(bundleURL)

        XCTAssertEqual(materialized, RuntimeMaterializedBundle(bundleURL: bundleURL, temporaryRoot: nil))
        XCTAssertEqual(events, ["path:/input/update-bundle"])
    }

    func testMaterializeExtractsArchiveIntoTemporaryRootAndRequiresExtractedDirectory() throws {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test")
        let extractedBundle = temporaryRoot.appendingPathComponent("update-bundle", isDirectory: true)
        var events: [String] = []
        let materializer = makeMaterializer(
            pathState: { url in
                events.append("path:\(url.path)")
                if url == archiveURL {
                    return .file
                }
                if url == extractedBundle {
                    return .directory
                }
                return .missing
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
            "path:/input/update-bundle.tar.gz",
            "temporary-root",
            "create:/tmp/tirosh-update-bundle-test:true",
            "process:/usr/bin/tar -tzf /input/update-bundle.tar.gz",
            "process:/usr/bin/tar -tvzf /input/update-bundle.tar.gz",
            "required:/usr/bin/tar -xzf /input/update-bundle.tar.gz -C /tmp/tirosh-update-bundle-test",
            "path:/tmp/tirosh-update-bundle-test/update-bundle",
            "log:bundle archive extracted source=/input/update-bundle.tar.gz destination=/tmp/tirosh-update-bundle-test/update-bundle",
        ])
    }

    func testMaterializeLogsArchiveListFailureAndUsesInvalidArchiveError() {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        var logs: [String] = []
        let materializer = makeMaterializer(
            pathState: { _ in .file },
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
            pathState: { _ in .file },
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

    func testMaterializeFailsWhenInputPathInspectionFails() {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let materializer = makeMaterializer(
            pathState: { _ in .inspectFailed("permission denied") }
        )

        XCTAssertThrowsError(try materializer.materialize(archiveURL)) { error in
            XCTAssertEqual(
                error as? TestBundleMaterializerError,
                .pathInspection(path: archiveURL.path, reason: "permission denied")
            )
        }
    }

    func testMaterializeFailsWhenExtractedBundleIsNotDirectory() {
        let archiveURL = URL(fileURLWithPath: "/input/update-bundle.tar.gz")
        let temporaryRoot = URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test")
        let extractedBundle = temporaryRoot.appendingPathComponent("update-bundle", isDirectory: true)
        let materializer = makeMaterializer(
            pathState: { url in
                if url == archiveURL {
                    return .file
                }
                if url == extractedBundle {
                    return .file
                }
                return .missing
            },
            temporaryRoot: { temporaryRoot },
            runProcess: { _, arguments in
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
            }
        )

        XCTAssertThrowsError(try materializer.materialize(archiveURL)) { error in
            XCTAssertEqual(
                error as? TestBundleMaterializerError,
                .unexpectedPathState(path: extractedBundle.path, state: RuntimePathState.file.rawValue)
            )
        }
    }

    private func makeMaterializer(
        pathState: @escaping (URL) -> RuntimePathState = { _ in .missing },
        temporaryRoot: @escaping () -> URL = { URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test") },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult = { _, _ in
            RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
        },
        runRequired: @escaping (String, [String]) throws -> Void = { _, _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundleMaterializer {
        let archiveValidator = ValidateUpdateBundleArchiveUseCase()
        return RuntimeBundleMaterializer(
            context: RuntimeBundleMaterializationContext(tarExecutable: "/usr/bin/tar"),
            operations: RuntimeBundleMaterializationOperations(
                pathState: pathState,
                temporaryRoot: temporaryRoot,
                createDirectory: createDirectory,
                runProcess: runProcess,
                runRequired: runRequired,
                rootDirectory: archiveValidator.rootDirectory,
                validateArchiveEntryTypes: archiveValidator.rejectUnsupportedEntryTypes,
                missingFileError: { TestBundleMaterializerError.missingFile($0.path) },
                invalidArchiveError: { TestBundleMaterializerError.invalidArchive($0.path) },
                pathInspectionError: { url, reason in
                    TestBundleMaterializerError.pathInspection(path: url.path, reason: reason)
                },
                unexpectedPathStateError: { url, state in
                    TestBundleMaterializerError.unexpectedPathState(path: url.path, state: state.rawValue)
                },
                archiveValidationError: { TestBundleMaterializerError.validation(String(describing: $0)) },
                log: log
            )
        )
    }
}

private enum TestBundleMaterializerError: Error, Equatable {
    case missingFile(String)
    case invalidArchive(String)
    case pathInspection(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case validation(String)
}
