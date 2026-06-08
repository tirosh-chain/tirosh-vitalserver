import XCTest
import Errors

final class ArchitectureHierarchyBoundaryTests: XCTestCase {
    func testSourceRootUsesIdealTopLevelHierarchy() throws {
        let sources = packageRoot().appendingPathComponent("Sources")
        let expected = Set([
            "Errors",
            "Contracts",
            "Domain",
            "Application",
            "Workflow",
            "Adapters",
            "Bootstrap",
            "Hosts",
        ])

        XCTAssertEqual(try childDirectoryNames(of: sources), expected)
    }

    func testRoleFoldersExistAtTheirOwnedLayer() throws {
        let sources = packageRoot().appendingPathComponent("Sources")
        let required = [
            "Contracts/Shared",
            "Contracts/RuntimeControl",
            "Contracts/RuntimeControl/TestKit",
            "Domain/Models",
            "Domain/Policies",
            "Domain/StateMachines",
            "Application/Ports",
            "Application/UseCases",
            "Workflow/RuntimeInstallLifecycle",
            "Workflow/RuntimeHealth",
            "Workflow/RuntimeRepairLifecycle",
            "Workflow/RuntimeShared",
            "Workflow/RuntimeUninstallLifecycle",
            "Workflow/RuntimeUpdateLifecycle",
            "Workflow/RuntimeWatchdog",
            "Application/UseCases/RuntimeOperationReporting",
            "Adapters/Inbound/CLI/Commands",
            "Adapters/Inbound/CLI/Parsing",
            "Adapters/Inbound/CLI/Presentation",
            "Adapters/Inbound/RuntimeControlAPI/Boundary",
            "Adapters/Inbound/RuntimeControlAPI/Transport",
            "Adapters/Inbound/RuntimeControlAPI/DevConsole",
            "Adapters/Inbound/RuntimeControlAPI/TestKit",
            "Adapters/Inbound/MacControlPanel/Configuration",
            "Adapters/Inbound/MacControlPanel/Generated",
            "Adapters/Inbound/MacControlPanel/Presentation",
            "Adapters/Inbound/MacControlPanel/Presentation/Copy",
            "Adapters/Inbound/MacControlPanel/Presentation/TestKit",
            "Adapters/Outbound/FileSystem",
            "Adapters/Outbound/Persistence",
            "Adapters/Outbound/ObservabilityStore",
            "Adapters/Outbound/PackageReceipts",
            "Adapters/Outbound/Health",
            "Adapters/Outbound/Launchd",
            "Adapters/Outbound/Process",
            "Adapters/Outbound/VirtualMachine",
            "Adapters/Outbound/CloudInit",
            "Adapters/Outbound/MacRuntimeControlClient",
            "Adapters/Outbound/MacRuntimeControlClient/Backups",
            "Adapters/Outbound/MacRuntimeControlClient/Client",
            "Adapters/Outbound/MacRuntimeControlClient/Commands",
            "Adapters/Outbound/MacRuntimeControlClient/Environment",
            "Adapters/Outbound/MacRuntimeControlClient/Logs",
            "Adapters/Outbound/MacRuntimeControlClient/Reads",
            "Adapters/Outbound/MacRuntimeControlClient/Settings",
            "Adapters/Outbound/MacRuntimeControlClient/TestKit",
            "Bootstrap/DI",
            "Bootstrap/Composition",
            "Hosts/CLI/Entrypoint",
            "Hosts/CLI/ProcessBoundary",
            "Hosts/CLI/ProcessBoundary/Lifecycle",
            "Hosts/CLI/ProcessBoundary/Support",
            "Hosts/MacControlPanel/Entrypoint",
            "Hosts/MacControlPanel/Composition",
            "Hosts/MacControlPanel/NativeShell",
        ]

        for path in required {
            assertDirectoryExists(sources.appendingPathComponent(path), "\(path) must exist")
        }

        let requiredFiles = [
            "Errors/Errors.swift",
            "Domain/Errors.swift",
            "Application/Errors.swift",
            "Workflow/Errors.swift",
            "Adapters/Inbound/Errors.swift",
            "Adapters/Outbound/Errors.swift",
            "Hosts/CLI/Errors.swift",
            "Hosts/MacControlPanel/Errors.swift",
        ]

        for path in requiredFiles {
            assertFileExists(sources.appendingPathComponent(path), "\(path) must exist")
        }
    }

    func testLayerErrorsUseSingleSwiftFileInsteadOfPackageLikeFolders() throws {
        let sources = packageRoot().appendingPathComponent("Sources")
        let forbidden = [
            "Errors/Boundary",
            "Errors/Context",
            "Errors/Failure",
            "Domain/Errors",
            "Application/Errors",
            "Workflow/Errors",
            "Adapters/Inbound/CLI/Errors",
            "Adapters/Inbound/RuntimeControlAPI/Errors",
            "Adapters/Inbound/MacControlPanel/Errors",
            "Adapters/Inbound/Errors",
            "Adapters/Outbound/FileSystem/Errors",
            "Adapters/Outbound/Persistence/Errors",
            "Adapters/Outbound/ObservabilityStore/Errors",
            "Adapters/Outbound/PackageReceipts/Errors",
            "Adapters/Outbound/Health/Errors",
            "Adapters/Outbound/Launchd/Errors",
            "Adapters/Outbound/Process/Errors",
            "Adapters/Outbound/VirtualMachine/Errors",
            "Adapters/Outbound/CloudInit/Errors",
            "Adapters/Outbound/MacRuntimeControlClient/Errors",
            "Adapters/Outbound/UpdateBundle/Errors",
            "Adapters/Outbound/Errors",
            "Hosts/CLI/Errors",
            "Hosts/MacControlPanel/Errors",
        ]

        for path in forbidden {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: sources.appendingPathComponent(path).path),
                "\(path) must not exist; layer errors should be collected in the owning layer's Errors.swift file"
            )
        }
    }

    func testGlobalErrorsDoesNotKeepLayerSpecificDefinitionsBucket() throws {
        let definitions = packageRoot()
            .appendingPathComponent("Sources/Errors/Definitions")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: definitions.path),
            "Layer-specific error definitions must live under their owning layer, not Sources/Errors/Definitions"
        )
    }

    func testRuntimeControlAPIDevConsoleKeepsHTMLAsResource() throws {
        let root = packageRoot()
        let devConsoleRoot = root.appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole")
        let document = devConsoleRoot.appendingPathComponent("RuntimeControlDevConsoleDocument.swift")
        let html = devConsoleRoot.appendingPathComponent("RuntimeControlDevConsole.html")
        let documentText = try String(contentsOf: document, encoding: .utf8)
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: html.path))
        XCTAssertTrue(
            manifest.contains(#".process("RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html")"#),
            "DevConsole HTML resource must be included by the InboundAdapters target"
        )
        XCTAssertFalse(
            documentText.contains(#"public static let html = #"""#),
            "DevConsole document responder must not inline the large HTML asset"
        )
    }

    func testRuntimeControlAPITestKitKeepsRouterEndpointAndRequestsSplit() throws {
        let testKitRoot = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/TestKit")
        let router = testKitRoot.appendingPathComponent("RuntimeTestKitAPIRouter.swift")
        let endpoint = testKitRoot.appendingPathComponent("RuntimeTestKitAPIEndpoint.swift")
        let requests = testKitRoot.appendingPathComponent("RuntimeTestKitAPIRequests.swift")

        for file in [router, endpoint, requests] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) must exist")
        }

        let routerText = try String(contentsOf: router, encoding: .utf8)
        let endpointText = try String(contentsOf: endpoint, encoding: .utf8)
        let requestsText = try String(contentsOf: requests, encoding: .utf8)

        XCTAssertFalse(routerText.contains("public enum RuntimeTestKitAPIEndpoint"))
        XCTAssertFalse(routerText.contains("public struct RuntimeTestKitStopRequest"))
        XCTAssertFalse(endpointText.contains("controller."))
        XCTAssertFalse(requestsText.contains(#""/dev/testkit/"#))
    }

    func testRuntimeControlHTTPPollingConsumesExplicitClock() throws {
        let boundaryRoot = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary")
        let pollingText = try String(
            contentsOf: boundaryRoot.appendingPathComponent("RuntimeControlHTTPPolling.swift"),
            encoding: .utf8
        )
        let routerText = try String(
            contentsOf: boundaryRoot.appendingPathComponent("RuntimeControlHTTPBoundary.swift"),
            encoding: .utf8
        )
        let streamRoutesText = try String(
            contentsOf: boundaryRoot.appendingPathComponent("RuntimeControlHTTPStreamRoutes.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            pollingText.contains("now: @escaping @Sendable () -> Date"),
            "HTTP stream polling should consume explicit time input for heartbeat decisions"
        )
        XCTAssertFalse(
            pollingText.contains("Date()") || pollingText.contains("Date.init"),
            "HTTP stream polling must not read system time directly"
        )
        XCTAssertTrue(
            pollingText.contains("encoder.outputFormatting = [.sortedKeys]"),
            "HTTP stream snapshot dedupe should use deterministic encoding before comparing payload bytes"
        )
        XCTAssertTrue(
            routerText.contains("now: @escaping @Sendable () -> Date = Date.init")
                && streamRoutesText.contains("now: now"),
            "System clock defaults should stay at the inbound router composition edge"
        )
    }

    func testRuntimeControlStaticFileResponderDelegatesPathAndResponseDetails() throws {
        let transportRoot = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Transport")
        let responderText = try String(
            contentsOf: transportRoot.appendingPathComponent("RuntimeControlStaticFileResponder.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: transportRoot.appendingPathComponent("RuntimeControlStaticFilePathResolver.swift").path
            ),
            "Static file path normalization and root safety should live outside the responder"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: transportRoot.appendingPathComponent("RuntimeControlStaticFileResponseFactory.swift").path
            ),
            "Static file content-type/cache/error responses should live outside the responder"
        )
        XCTAssertTrue(responderText.contains("RuntimeControlStaticFilePathResolver"))
        XCTAssertTrue(responderText.contains("RuntimeControlStaticFileResponseFactory"))
        for token in [
            "removingPercentEncoding",
            "pathExtension.lowercased",
            "static file path contains parent directory segment",
            "public, max-age=31536000, immutable",
        ] {
            XCTAssertFalse(
                responderText.contains(token),
                "Static file responder should orchestrate lookup/read/response, not own detail rule: \(token)"
            )
        }
    }

    func testRuntimeControlHTTPRouteExecutorUsesTypedErrorMapping() throws {
        let root = packageRoot()
        let executorText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPRouteExecutor.swift"),
            encoding: .utf8
        )
        let errorResponseText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPIErrorResponse.swift"),
            encoding: .utf8
        )
        let testKitRouterText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/TestKit/RuntimeTestKitAPIRouter.swift"),
            encoding: .utf8
        )
        let hostErrorsText = try String(
            contentsOf: root.appendingPathComponent("Sources/Hosts/MacControlPanel/Errors.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            executorText.contains("RuntimeControlHTTPErrorResponseMapper.response(for: error)"),
            "Runtime Control route executor must delegate thrown errors to the typed HTTP error mapper"
        )
        XCTAssertFalse(
            executorText.contains("code: .handlerFailed"),
            "Runtime Control route executor must not collapse every handler error to handlerFailed"
        )
        XCTAssertTrue(
            testKitRouterText.contains("RuntimeControlHTTPErrorResponseMapper.response(for: error)"),
            "Runtime Control TestKit router must share the typed HTTP error mapper"
        )
        XCTAssertFalse(
            testKitRouterText.contains("code: .handlerFailed"),
            "Runtime Control TestKit router must not maintain a second generic handlerFailed mapping"
        )
        XCTAssertTrue(
            errorResponseText.contains("case .hostAffordanceUnavailable"),
            "Runtime Control HTTP error mapper must preserve missing host affordance as a distinct API error"
        )
        XCTAssertTrue(
            errorResponseText.contains("case .unsupportedFileReference"),
            "Runtime Control HTTP error mapper must preserve unsupported file references as bad requests"
        )
        XCTAssertFalse(
            hostErrorsText.contains("RuntimeControlAPIHandlerError"),
            "Mac host API handler should use the shared RuntimeControlAPIReadHandlerError contract"
        )
    }

    func testRuntimeControlSingleResourceRoutesDoNotEncodeMissingResourcesAsJSONNull() throws {
        let root = packageRoot()
        let readRoutesText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPReadRoutes.swift"),
            encoding: .utf8
        )
        let apiText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPI.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            readRoutesText.contains("let recorder = try await handler.loadVitalDBRecorders().recorders.first"),
            "Single VitalDB recorder reads must not pass an optional lookup result through JSON as 200 null."
        )
        XCTAssertFalse(
            readRoutesText.contains("let bed = try await handler.loadVitalDBRecorders().beds.first"),
            "Single VitalDB bed reads must not pass an optional lookup result through JSON as 200 null."
        )
        XCTAssertTrue(readRoutesText.contains("RuntimeControlHTTPResponseFactory.resourceNotFound"))
        XCTAssertTrue(
            apiText.contains("case resourceNotFound"),
            "Runtime Control API errors should distinguish missing resources from missing routes."
        )
    }

    func testMacRuntimeControlClientKeepsCapabilityFolders() throws {
        let clientRoot = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient")
        let rootSwiftFiles = try FileManager.default.contentsOfDirectory(
            at: clientRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            url.pathExtension == "swift"
                && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }

        XCTAssertTrue(
            rootSwiftFiles.isEmpty,
            "MacRuntimeControlClient root must only group capability folders, not own source files: \(rootSwiftFiles.map(\.lastPathComponent))"
        )

        let testKitController = clientRoot.appendingPathComponent("TestKit/MacTestKitController.swift")
        let controllerText = try String(contentsOf: testKitController, encoding: .utf8)
        XCTAssertFalse(controllerText.contains("public enum MacTestKitAPIEndpointSource"))
        XCTAssertFalse(controllerText.contains("struct TestKitStartSessionRequest"))
        XCTAssertFalse(controllerText.contains("MacTestKitAvailabilityPolicy"))
        XCTAssertFalse(
            controllerText.contains("activeSessionID"),
            "Outbound TestKit adapter must not own selected session state; callers must pass explicit session IDs"
        )
        XCTAssertFalse(
            controllerText.contains("private var lastError"),
            "Outbound TestKit adapter must report errors in explicit return values or throws, not cache hidden error state"
        )
        XCTAssertTrue(
            controllerText.contains("RuntimeTestKitSessionStatePolicy.preferredActiveSession(from: sessions)"),
            "Outbound TestKit adapter should delegate active-session selection to the RuntimeControl contract policy"
        )
        XCTAssertFalse(
            controllerText.contains("[\"running\", \"paused\", \"starting\", \"stopping\"]"),
            "Outbound TestKit adapter must not own TestKit session-state semantics"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: clientRoot.appendingPathComponent("TestKit/MacTestKitAvailabilityPolicy.swift").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Contracts/RuntimeControl/TestKit/RuntimeTestKitAvailabilityPolicy.swift")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: clientRoot.appendingPathComponent("TestKit/MacTestKitControllerConfiguration.swift").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: clientRoot.appendingPathComponent("TestKit/MacTestKitWireModels.swift").path
            )
        )
    }

    func testRuntimeTestPanelDoesNotInterpretSessionStateStrings() throws {
        let panel = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/TestKit/RuntimeTestPanel.swift")
        let text = try String(contentsOf: panel, encoding: .utf8)

        for token in [
            "session.state.lowercased()",
            "[\"stopped\", \"failed\"]",
            "case \"running\"",
            "case \"paused\"",
            "case \"stopped\", \"failed\"",
            "testKitActionMessage.lowercased()",
            "message.contains(\"error\")",
            "message.contains(\"failed\")",
            "message.contains(\"unavailable\")",
            "message.contains(\"not reachable\")",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeTestPanel must render explicit presentation decisions, not interpret TestKit state or action message strings: \(token)"
            )
        }

        XCTAssertTrue(
            text.contains("viewModel.testKitSessionControlState(session)"),
            "RuntimeTestPanel should render the session control state supplied by presentation policy."
        )
        XCTAssertTrue(
            text.contains("viewModel.testKitActionMessageTone"),
            "RuntimeTestPanel should render explicit action message tone instead of deriving tone from message text."
        )
    }

    func testOutboundAdaptersDoNotForceUnwrapExternalURLConstruction() throws {
        let outboundRoot = packageRoot().appendingPathComponent("Sources/Adapters/Outbound")
        let offenders = try swiftFiles(root: outboundRoot).flatMap { file -> [String] in
            let text = try String(contentsOf: file, encoding: .utf8)
            return text
                .components(separatedBy: .newlines)
                .enumerated()
                .compactMap { index, line in
                    let crashesOnInvalidInput =
                        (line.contains("URL(string:") && line.contains(")!"))
                        || (line.contains("URLComponents(string:") && line.contains(")!"))
                        || line.contains(".url!")
                        || line.contains("request.url!")
                        || line.contains("try!")
                        || line.contains("as!")
                    guard crashesOnInvalidInput else {
                        return nil
                    }
                    return "\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
                }
        }

        XCTAssertEqual(
            offenders,
            [],
            "Outbound adapters must convert invalid external URL/typing state into explicit errors instead of crashing."
        )
    }

    func testRuntimeLogExportManifestIsAContractDocumentNotOutboundOwnedShape() throws {
        let outboundLogFiles = try swiftFiles(
            root: packageRoot().appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Logs")
        )
        let contractManifest = packageRoot()
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeLogExportManifest.swift")
        let outboundManifestDefinitions = try outboundLogFiles.flatMap { file -> [String] in
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("struct RuntimeLogExportManifest") else {
                return []
            }
            return [file.path]
        }
        let contractText = try String(contentsOf: contractManifest, encoding: .utf8)

        XCTAssertEqual(
            outboundManifestDefinitions,
            [],
            "Outbound log exporter may write the manifest, but the exported document shape belongs in Contracts."
        )
        XCTAssertTrue(
            contractText.contains("public struct RuntimeLogExportManifest"),
            "Runtime log export manifest must remain a public RuntimeControl contract document."
        )
    }

    func testRuntimeLogExportSourceDestinationsAreRuntimeControlContracts() throws {
        let root = packageRoot()
        let outboundSources = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Logs/RuntimeLogExportSources.swift")
        let contractSources = root
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeLogExportSourceContracts.swift")
        let outboundText = try String(contentsOf: outboundSources, encoding: .utf8)
        let contractText = try String(contentsOf: contractSources, encoding: .utf8)

        XCTAssertTrue(
            contractText.contains("public enum RuntimeLogExportSourceContract"),
            "Runtime log export bundle destination contract must live in RuntimeControl contracts"
        )
        XCTAssertTrue(
            outboundText.contains("RuntimeLogExportSourceContract.supplementalDestinations()"),
            "Outbound log exporter source mapping should consume the RuntimeControl destination contract"
        )
        XCTAssertTrue(
            outboundText.contains("RuntimeLogExportSourceContract.rotatedSupplementalDestinations()"),
            "Outbound rotated log exporter source mapping should consume the RuntimeControl destination contract"
        )
        for token in [
            #"relativeDestination: "diagnostics/"#,
            #"relativeDestination: "guest/"#,
            #"relativeDestinationDirectory: "diagnostics/"#,
            #"relativeDestinationDirectory: "guest""#,
        ] {
            XCTAssertFalse(
                outboundText.contains(token),
                "Outbound log export source mapping must not own bundle-relative destination literals: \(token)"
            )
        }
    }

    func testRuntimeLogCollectionSourcesUseRuntimeControlContracts() throws {
        let root = packageRoot()
        let outboundSources = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Logs/RuntimeLogCollectionSources.swift")
        let contractDecisionRules = root
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeLogCollectionDecisionRules.swift")
        let outboundReadStrategy = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeLogSourceReadStrategy.swift")
        let contractSources = root
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeLogCollectionSourceContracts.swift")
        let outboundText = try String(contentsOf: outboundSources, encoding: .utf8)
        let contractDecisionRulesText = try String(contentsOf: contractDecisionRules, encoding: .utf8)
        let outboundReadStrategyText = try String(contentsOf: outboundReadStrategy, encoding: .utf8)
        let contractText = try String(contentsOf: contractSources, encoding: .utf8)
        let outboundLogMappingText = [
            outboundText,
            outboundReadStrategyText,
        ].joined(separator: "\n")

        XCTAssertTrue(
            contractText.contains("public enum RuntimeLogCollectionSourceContract"),
            "Runtime log collection source contracts must live in RuntimeControl contracts."
        )
        XCTAssertTrue(
            outboundText.contains("RuntimeLogCollectionSourceContract.fileCopies()"),
            "Outbound log collection source mapping should consume the RuntimeControl file collection contract."
        )
        XCTAssertTrue(
            outboundText.contains("RuntimeLogCollectionSourceContract.directoryCopies()"),
            "Outbound log directory collection mapping should consume the RuntimeControl directory collection contract."
        )
        XCTAssertTrue(
            outboundText.contains("RuntimeLogCollectionSourceContract.rotatedCopies()"),
            "Outbound rotated log collection mapping should consume the RuntimeControl rotated collection contract."
        )
        XCTAssertTrue(
            contractDecisionRulesText.contains("RuntimeLogCollectionSourceContract.fileCopy(for: input.sourceID)"),
            "RuntimeControl log collection decision rules should consume the RuntimeControl log source mapping contract."
        )
        XCTAssertTrue(
            outboundReadStrategyText.contains("RuntimeLogCollectionSourceContract.fileCopy(for: sourceID)"),
            "Outbound log read strategy should consume the RuntimeControl log source mapping contract."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Logs/RuntimeLogCollectionDecisionRules.swift")
                    .path
            ),
            "Pure log collection decision rules must not live in Outbound adapters."
        )
        for token in [
            #""launcher.log""#,
            #""launchd.out.log""#,
            #""launchd.err.log""#,
            #""proxy.err.log""#,
            #""guest-bootstrap.log""#,
            #""guest-container-logs.log""#,
            #"sourceFilePrefix: "container-logs.log.""#,
            #"archivePrefix: "guest-container-logs.log.""#,
        ] {
            XCTAssertFalse(
                outboundLogMappingText.contains(token),
                "Outbound log collection source mapping must not own product log identity literals: \(token)"
            )
        }
    }

    func testOutboundArtifactArchiveValidatorDelegatesArchiveEntryPolicyInward() throws {
        let validator = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/UpdateBundle/RuntimeArtifactArchiveValidator.swift")
        let text = try String(contentsOf: validator, encoding: .utf8)

        XCTAssertTrue(
            text.contains("validateArchiveEntries("),
            "Outbound archive validator should pass tar list output to the inward archive validation policy."
        )
        for token in [
            "path traversal",
            "unsafe tar entry",
            "unexpected top-level entry",
            "unexpected root entry",
            "components.contains(\"..\")",
            "hasPrefix(\"/\")",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "Outbound archive validator must not own archive entry/root policy: \(token)"
            )
        }
    }

    func testUpdateBundleArtifactArchiveLayoutLivesInContracts() throws {
        let root = packageRoot()
        let contractText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/UpdateBundleContracts.swift"),
            encoding: .utf8
        )
        let replacementConfigurationText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/UpdateBundle/RuntimeArtifactReplacementConfiguration.swift"
            ),
            encoding: .utf8
        )
        let updateSupportText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Hosts/CLI/ProcessBoundary/Support/RuntimeLifecycle+UpdateSupport.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            contractText.contains("public struct UpdateBundleArtifactArchiveLayout"),
            "Update bundle artifact archive layout must be a shared contract."
        )
        XCTAssertTrue(
            replacementConfigurationText.contains("UpdateBundleArtifactArchiveLayout"),
            "Outbound replacement configuration should consume the shared archive layout contract."
        )
        for token in [
            #"appBundleRoot: "VitalServer Helper.app""#,
            #"nginxBundleRoot: "nginx""#,
            #"guestDeployRoot: "deploy""#,
            #""vitalserver-vm""#,
            #""vitalserver-proxy-run""#,
            #""tirosh-vitalserver-uninstall""#,
        ] {
            XCTAssertFalse(
                replacementConfigurationText.contains(token) || updateSupportText.contains(token),
                "Artifact archive layout literals must not live in Outbound/Host composition: \(token)"
            )
        }
    }

    func testUninstallProgressCommandDoesNotGuessWorkflowLogMessages() throws {
        let root = packageRoot()
        let commandFactoryText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/RuntimeUninstallCommandFactory.swift"
            ),
            encoding: .utf8
        )
        let progressScriptText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/RuntimeUninstallProgressScript.swift"
            ),
            encoding: .utf8
        )
        let useCaseText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Application/UseCases/UninstallRuntime/UninstallRuntimeUseCase.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(progressScriptText.contains("background_status=$?"))
        XCTAssertTrue(progressScriptText.contains("uninstall process completed exitCode=0"))
        XCTAssertTrue(progressScriptText.contains("uninstall process failed exitCode="))
        XCTAssertTrue(useCaseText.contains(#""uninstall completed""#))
        for text in [commandFactoryText, progressScriptText] {
            XCTAssertFalse(
                text.contains("uninstall completed log="),
                "Helper uninstall progress must not grep a guessed Workflow log line"
            )
        }
    }

    func testBootstrapCompositionKeepsOnlyConstantsAndPathComposition() throws {
        let compositionRoot = packageRoot().appendingPathComponent("Sources/Bootstrap/Composition")
        let fileNames = Set(
            try FileManager.default.contentsOfDirectory(
                at: compositionRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .map(\.lastPathComponent)
        )

        XCTAssertEqual(
            fileNames,
            [
                "Constants.swift",
                "GeneratedVersion.swift",
                "LauncherPaths.swift",
                "RuntimeManagedServicePaths.swift",
            ],
            "Bootstrap/Composition must not contain Host runner, file IO, process, Workflow, or Usecase composition"
        )
    }

    func testLegacyLayerFoldersAndGitkeepFilesDoNotRemain() throws {
        let root = packageRoot()
        let forbidden = [
            "Sources/Core",
            "Sources/Interfaces",
            "Sources/HostCLI",
            "Sources/Infrastructure",
            "Sources/HostAdapters",
            "Sources/MacHostRuntimeAdapter",
            "Sources/MacRuntimeControlApp",
            "Sources/RuntimeControlAPI",
            "Sources/Adapters/Inbound/HostCLI",
            "Sources/Adapters/Outbound/Infrastructure",
            "Sources/Adapters/Outbound/HostAdapters",
            "Sources/Adapters/Outbound/MacHostRuntimeAdapter",
            "Sources/Hosts/MacControlPanelHost",
            "Sources/Application/UseCases/RuntimeWorkflow",
            "Sources/Contracts/RuntimeControl/Testing",
            "Sources/Adapters/Inbound/RuntimeControlAPI/Testing",
            "Sources/Adapters/Inbound/MacControlPanel/Composition",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Testing",
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Testing",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Support.swift",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle+Workflows.swift",
        ]

        for path in forbidden {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not remain in the ideal hierarchy"
            )
        }

        let gitkeepFiles = try swiftPackageFiles(root: root).filter { $0.lastPathComponent == ".gitkeep" }
        XCTAssertTrue(gitkeepFiles.isEmpty, ".gitkeep files must not remain")
    }

    func testSourceTestAndSupportFoldersDoNotKeepEmptyPlaceholders() throws {
        let root = packageRoot()
        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
            root.appendingPathComponent("Support"),
        ]

        let emptyPlaceholderDirectories = try scannedRoots.flatMap { try emptyDirectories(root: $0) }
        XCTAssertTrue(
            emptyPlaceholderDirectories.isEmpty,
            "Empty source/test/support placeholder directories must not remain: \(emptyPlaceholderDirectories.map(\.path).sorted())"
        )
    }

    func testMacControlPanelHostTestsKeepOutboundClientTestsGrouped() throws {
        let testRoot = packageRoot().appendingPathComponent("Tests/MacControlPanelHostTests")
        let outboundClientRoot = testRoot.appendingPathComponent("OutboundClient")
        assertDirectoryExists(outboundClientRoot, "MacControlPanelHost outbound client tests must be grouped")

        for fileName in [
            "MacRuntimeControlClientWorkerTests.swift",
            "MacTestKitControllerTests.swift",
            "ProcessRunnerTests.swift",
            "RuntimeActionEnvironmentTests.swift",
            "RuntimeCommandFactoryTests.swift",
            "RuntimeFileReaderTests.swift",
            "RuntimeLogCollectorTests.swift",
            "RuntimeLogExporterTests.swift",
            "RuntimeObservabilityReaderTests.swift",
            "RuntimeSettingsReaderTests.swift",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: testRoot.appendingPathComponent(fileName).path),
                "\(fileName) must not sit at the MacControlPanelHostTests root"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outboundClientRoot.appendingPathComponent(fileName).path),
                "\(fileName) must live under MacControlPanelHostTests/OutboundClient"
            )
        }
    }

    func testSwiftPMTargetsUseIdealModuleNames() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for target in [
            "Errors",
            "Contracts",
            "RuntimeControl",
            "Domain",
            "Application",
            "Workflow",
            "InboundAdapters",
            "OutboundAdapters",
            "Bootstrap",
            "CLIHost",
            "MacControlPanelHost",
        ] {
            XCTAssertTrue(manifest.contains("name: \"\(target)\""), "\(target) target must be declared")
        }

        for legacyTarget in ["Adapters", "Infrastructure", "HostAdapters", "HostCLI", "MacHostRuntimeAdapter"] {
            XCTAssertFalse(manifest.contains("name: \"\(legacyTarget)\""), "\(legacyTarget) target must not remain")
        }
    }

    func testBootstrapDIHasExplicitApplicationContainer() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/DI/RuntimeApplicationContainer.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("public struct RuntimeApplicationContainer"))
        XCTAssertTrue(text.contains("RuntimeLifecycleComposition.resolve"))
        for token in [
            "static let shared",
            "static var shared",
            "RuntimeApplicationContainer.shared",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "DI container must be explicit per host startup, not a global service locator: \(token)"
            )
        }
    }

    func testRuntimeLifecycleDependencyResolutionLivesInBootstrapDI() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Bootstrap/DI/RuntimeLifecycleComposition.swift").path
            ),
            "Concrete lifecycle dependency resolution belongs in Bootstrap/DI"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Bootstrap/Composition/RuntimeLifecycleComposition.swift").path
            ),
            "Composition must not own application-level dependency graph resolution"
        )
    }

    func testHostCLIRuntimeLifecycleUsesApplicationContainerForInitialDependencyGraph() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("let container: RuntimeApplicationContainer"))
        XCTAssertTrue(text.contains("RuntimeApplicationContainer("))
        XCTAssertFalse(
            text.contains("RuntimeLifecycleComposition.resolve("),
            "HostCLI must receive the initial dependency graph through Bootstrap/DI container"
        )
    }

    func testHostCLIRepairFactoriesLiveAtProcessBoundary() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/Lifecycle/RuntimeLifecycle+RepairComposition.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("container.makeRuntimeDatastoreRepairComposition"))
        XCTAssertTrue(text.contains("container.makeRuntimeVMDiskRepairComposition"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeApplicationContainer+Repair.swift")
                    .path
            ),
            "Repair composition factories belong at the Host process boundary"
        )
        for token in [
            "RuntimeDatastoreRepairCompositionContext(",
            "RuntimeDatastoreRepairCompositionOperations(",
            "RuntimeVMDiskRepairCompositionContext(",
            "RuntimeVMDiskRepairCompositionOperations(",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeLifecycle must provide explicit actions and delegate repair composition to the Host factory: \(token)"
            )
        }
    }

    func testBootstrapDIDoesNotContainRepairExecutionFactories() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/DI/RuntimeApplicationContainer+Repair.swift")
                    .path
            ),
            "Repair execution factories must not live in Bootstrap DI"
        )
    }

    func testWorkflowTestTargetRemainsForStatefulOrchestration() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            manifest.contains("name: \"WorkflowTests\""),
            "Stateful lifecycle orchestration must keep Workflow-specific tests"
        )
    }

    func testLegacyLayerVocabularyDoesNotLeakIntoRuntimeSourcesTestsOrSupportFiles() throws {
        let root = packageRoot()
        let forbidden = [
            "HostCLI",
            "MacHostRuntime",
            "MacHostRuntimeAdapter",
            "MacRuntimeControlApp",
            "InfrastructureLayerMarker",
            "HostAdaptersLayerMarker",
            "RuntimeAdapterConstants",
        ]
        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
            root.appendingPathComponent("Support"),
            root.appendingPathComponent("README.md"),
        ]

        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    text.contains(token),
                    "\(token) must not remain in \(file.path)"
                )
            }
        }
    }

    func testLayerImportDirectionStaysInward() throws {
        let root = packageRoot().appendingPathComponent("Sources")
        let checks: [(String, Set<String>)] = [
            (
                "Contracts/Shared",
                ["Errors", "Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Contracts/RuntimeControl",
                ["Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Errors",
                ["Domain", "Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Domain",
                ["Application", "Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Application",
                ["Workflow", "InboundAdapters", "OutboundAdapters", "Bootstrap", "RuntimeControl", "CLIHost", "MacControlPanelHost"]
            ),
            (
                "Workflow",
                ["InboundAdapters", "OutboundAdapters", "Bootstrap", "CLIHost", "MacControlPanelHost"]
            ),
        ]

        for (layerPath, forbiddenImports) in checks {
            let layerRoot = root.appendingPathComponent(layerPath)
            for file in try swiftFiles(root: layerRoot) {
                let imports = try importedModules(in: file)
                let forbidden = imports.intersection(forbiddenImports)
                XCTAssertTrue(
                    forbidden.isEmpty,
                    "\(layerPath) must not import outward modules \(forbidden.sorted()) in \(file.path)"
                )
            }
        }
    }

    func testSwiftFilesDoNotKeepDuplicateImports() throws {
        let root = packageRoot()
        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
        ]

        for file in try scannedRoots.flatMap({ try swiftFiles(root: $0) }) {
            var imports = Set<String>()
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                let text = String(line).trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix("import ") else {
                    continue
                }
                XCTAssertTrue(imports.insert(text).inserted, "Duplicate import \(text) in \(file.path)")
            }
        }
    }

    func testAdaptersDoNotImportDomainDirectly() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters")
        for file in try swiftFiles(root: root) {
            let imports = try importedModules(in: file)
            XCTAssertFalse(
                imports.contains("Domain"),
                "Adapters must call Domain policy through Application use cases or Contracts, not directly: \(file.path)"
            )
        }
    }

    func testAdapterTargetsDoNotDependOnDomain() throws {
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        for target in ["InboundAdapters", "OutboundAdapters"] {
            let dependencies = try targetDependencies(target, in: manifest)
            XCTAssertFalse(
                dependencies.contains("Domain"),
                "\(target) must not depend on Domain directly; Adapters cross inward through Application/Contracts"
            )
        }
    }

    func testAdaptersDoNotConstructApplicationUseCases() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters")
        let useCaseConstruction = try NSRegularExpression(
            pattern: #"\b[A-Za-z0-9_]+UseCase\s*\("#
        )
        for file in try swiftFiles(root: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            XCTAssertNil(
                useCaseConstruction.firstMatch(in: text, range: range),
                "Adapters may receive Application usecases from Host/Bootstrap composition, but must not construct them directly: \(file.path)"
            )
        }
    }

    func testOutboundAdaptersDoNotReferenceApplicationUseCaseTypes() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters/Outbound")
        let useCaseReference = try NSRegularExpression(
            pattern: #"\b[A-Za-z0-9_]+UseCase\b"#
        )
        for file in try swiftFiles(root: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            XCTAssertNil(
                useCaseReference.firstMatch(in: text, range: range),
                "Outbound adapters must expose explicit IO results and must not depend on concrete Application usecase types: \(file.path)"
            )
        }
    }

    func testOutboundAdaptersDoNotKeepPolicyNamedExecutors() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters/Outbound")
        for file in try swiftFiles(root: root) {
            XCTAssertFalse(
                file.lastPathComponent.contains("Policy"),
                "Outbound adapters execute explicit plans/read IO; policy-named files belong inward: \(file.path)"
            )
        }
    }

    func testSQLiteVitalDBRelationshipProjectionWriterExecutesExplicitPlanOnly() throws {
        let root = packageRoot()
        let writerText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/ObservabilityStore/SQLiteVitalDBRelationshipProjectionWriter.swift"
            ),
            encoding: .utf8
        )
        let storeText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/ObservabilityStore/SQLiteRuntimeObservabilityStore.swift"
            ),
            encoding: .utf8
        )
        let useCaseText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Application/UseCases/Observability/PlanVitalDBRelationshipProjectionUseCase.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            writerText.contains("relationshipProjectionPlanner(observation, openAssignmentsByBedID)"),
            "SQLite relationship projection writer must execute a pure projection plan from Application/Domain"
        )
        XCTAssertFalse(
            writerText.contains("openAssignment.vrcode =="),
            "SQLite relationship projection writer must not decide assignment continuity"
        )
        XCTAssertFalse(
            writerText.contains("Bed VRecorder assignment changed."),
            "SQLite relationship projection writer must not own handoff domain messages"
        )
        XCTAssertFalse(
            storeText.contains("relationshipEventID"),
            "SQLite relationship projection adapter must not receive domain event ID factories"
        )
        XCTAssertFalse(
            useCaseText.contains("public func eventID"),
            "Application projection usecase should expose projection plans, not low-level ID helpers"
        )
    }

    func testRuntimeInstallVMRuntimeConfigurationUseCaseDoesNotLiveInOutboundAdapter() throws {
        let root = packageRoot()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Outbound/VirtualMachine/RuntimeInstallVMRuntimeConfigurator.swift"
                ).path
            ),
            "Install VM runtime configuration applies explicit install input through ports; it belongs in Application, not Outbound"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Application/UseCases/InstallRuntime/RuntimeInstallVMRuntimeConfigurator.swift"
                ).path
            ),
            "Application must own the install VM runtime configuration usecase"
        )
    }

    func testRuntimeManagedServiceDisplayNameDoesNotLiveInLaunchdAdapter() throws {
        let root = packageRoot()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Outbound/Launchd/RuntimeManagedServiceDisplayName.swift"
                ).path
            ),
            "RuntimeManagedService labels are shared contract vocabulary, not Launchd adapter-local display logic"
        )

        let contractsFile = root.appendingPathComponent("Sources/Contracts/Shared/RuntimeManagedService.swift")
        let text = try String(contentsOf: contractsFile, encoding: .utf8)
        XCTAssertTrue(
            text.contains("runtimeServiceDisplayName"),
            "RuntimeManagedService must expose the shared service display vocabulary"
        )
    }

    func testOutboundHealthAdapterDoesNotAssembleApplicationHealthObservation() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters/Outbound/Health")
        let forbiddenTokens = [
            "RuntimeHealthObservation(",
            "RuntimeContainerObservation(",
            "RuntimeGuestRuntimeStateInputPlan",
            "RuntimeComposeServicesReadResult",
            "reportedVMErrors",
            "hostProxyListenerFailureReasons",
        ]

        for file in try swiftFiles(root: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "Outbound Health adapters must return explicit read results; Application usecase must assemble health observation: \(token) in \(file.path)"
                )
            }
        }
    }

    func testRuntimeHealthInputsRequireExplicitProxyPortReadState() throws {
        let root = packageRoot()
        for relativePath in [
            "Sources/Application/UseCases/RuntimeHealth/EvaluateRuntimeHealthUseCase.swift",
            "Sources/Domain/Policies/RuntimeHealthEvaluator.swift",
        ] {
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)

            XCTAssertFalse(
                text.contains("proxyPortReadState: RuntimeProxyPortReadState?"),
                "Runtime health inputs must require explicit proxy port read state: \(relativePath)"
            )
            XCTAssertFalse(
                text.contains("proxyPortReadState ?? .observed(proxyPort)"),
                "Runtime health inputs must not create observed proxy port state from missing read state: \(relativePath)"
            )
        }
    }

    func testRuntimeHealthReadContractsDoNotLiveInsideUseCaseImplementation() throws {
        let root = packageRoot()
        let contractsFile = root
            .appendingPathComponent("Sources/Contracts/Shared/RuntimeHealthObservationReads.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contractsFile.path),
            "Runtime health read contracts are shared adapter-to-usecase contracts and must live in Contracts"
        )

        let useCaseFile = root
            .appendingPathComponent("Sources/Application/UseCases/RuntimeHealth/EvaluateRuntimeHealthUseCase.swift")
        let useCaseText = try String(contentsOf: useCaseFile, encoding: .utf8)
        for token in [
            "public struct RuntimeHealthObservationReads",
            "public struct RuntimeAuditProxyStatusReadResult",
            "public enum RuntimeAuditProxyStatusReadState",
            "public struct RuntimeHostProxyListenerObservation",
            "public struct RuntimeGuestRuntimeStateObservation",
            "public struct RuntimeContainerLogsMetadata",
            "public struct RuntimeFileModifiedAtReadResult",
            "public enum RuntimeFileMetadataReadState",
            "public enum RuntimeGuestRuntimeStateReadIssue",
        ] {
            XCTAssertFalse(
                useCaseText.contains(token),
                "Application usecase must consume health read contracts, not declare adapter-facing read DTOs: \(token)"
            )
        }
    }

    func testRuntimeStateFileMetadataReadStateStaysExplicit() throws {
        let root = packageRoot()
        let contractsText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"),
            encoding: .utf8
        )
        let containerObservationText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/RuntimeContainerObservation.swift"),
            encoding: .utf8
        )
        let checkerText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            contractsText.contains("public enum RuntimeFileMetadataReadState")
                && contractsText.contains("case notRead")
                && contractsText.contains("public let readState: RuntimeFileMetadataReadState"),
            "Runtime file metadata reads must preserve notRead/loaded/readFailed explicitly"
        )
        XCTAssertTrue(
            containerObservationText.contains("runtimeStateFileMetadataReadState"),
            "Runtime container observation must carry runtime state file metadata read state to API/UI consumers"
        )
        XCTAssertTrue(
            checkerText.contains("return .notRead()"),
            "RuntimeHealthChecker must report skipped runtime-state metadata reads explicitly"
        )
        XCTAssertFalse(
            checkerText.contains("RuntimeFileModifiedAtReadResult(updatedAt: nil, readError: nil)"),
            "RuntimeHealthChecker must not represent skipped metadata reads as nil updatedAt and nil error only"
        )
    }

    func testAuditProxyStatusReadStateStaysExplicit() throws {
        let root = packageRoot()
        let contractsText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"),
            encoding: .utf8
        )
        let containerObservationText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/RuntimeContainerObservation.swift"),
            encoding: .utf8
        )
        let readerText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Outbound/Health/RuntimeAuditProxyStatusReader.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            contractsText.contains("public enum RuntimeAuditProxyStatusReadState")
                && contractsText.contains("case commandFailed")
                && contractsText.contains("case emptyResponse")
                && contractsText.contains("public let readState: RuntimeAuditProxyStatusReadState"),
            "Audit proxy status reads must preserve command/decode/empty/output failures explicitly"
        )
        XCTAssertTrue(
            containerObservationText.contains("auditProxyStatusReadState"),
            "Runtime container observation must carry audit proxy read state to API/UI consumers"
        )
        XCTAssertFalse(
            readerText.contains(#"httpStatus: "failed""#),
            "Audit proxy reader must not encode command failure as an invented HTTP status string only"
        )
    }

    func testContainerServicesReadStateDoesNotInferFromReadErrorText() throws {
        let containerObservationText = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/Contracts/Shared/RuntimeContainerObservation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            containerObservationText.contains("composeServicesReadState"),
            "Runtime container observation must carry compose services read state explicitly"
        )
        for token in [
            #"readError.contains("stale")"#,
            #"readError.contains("invalid")"#,
            #"readError.contains("missing")"#,
            "RuntimeContainerServicesReadState(readError:",
        ] {
            XCTAssertFalse(
                containerObservationText.contains(token),
                "Compose services read state must not be inferred from read error text: \(token)"
            )
        }
    }

    func testRuntimeHealthCheckerDoesNotCreateMissingProxyPortHTTPStatus() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("RuntimeHTTPStatusText.missingProxyPort"),
            "RuntimeHealthChecker should report skipped proxy HTTP probes as nil reads; Application maps missing proxy port to display/status text"
        )
        XCTAssertTrue(
            text.contains("let hostProxyHTTP = proxyPort.map"),
            "RuntimeHealthChecker should only run host proxy HTTP probe when an explicit proxy port exists"
        )
    }

    func testHTTPProbeReadsStayTypedUntilApplicationMapping() throws {
        let root = packageRoot()
        let prober = try String(
            contentsOf: root.appendingPathComponent("Sources/Application/Ports/RuntimeHTTPProber.swift"),
            encoding: .utf8
        )
        let reads = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"),
            encoding: .utf8
        )
        let checker = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            prober.contains("func statusRead(url: String) -> RuntimeHTTPProbeResult"),
            "HTTP probe port must expose typed read results, not only a status string"
        )
        for token in [
            "public let hostProxyHTTP: RuntimeHTTPProbeResult?",
            "public let redisUIHTTP: RuntimeHTTPProbeResult?",
            "public let swaggerUIHTTP: RuntimeHTTPProbeResult?",
        ] {
            XCTAssertTrue(reads.contains(token), "Health observation reads must preserve typed HTTP probe state: \(token)")
        }
        XCTAssertTrue(
            checker.contains("httpProber.statusRead"),
            "RuntimeHealthChecker must keep command failure/empty/invalid HTTP reads typed"
        )
        XCTAssertFalse(
            checker.contains("httpProber.statusCode"),
            "RuntimeHealthChecker must not collapse HTTP probe failures to strings"
        )
    }

    func testGuestRuntimeStateReaderReportsReadIssuesWithoutDomainFailureReasons() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/Health/RuntimeGuestRuntimeStateObservationReader.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("RuntimeFailureReason"),
            "Guest runtime state reader must report read issues, not domain failure reason types"
        )
        XCTAssertFalse(
            text.contains(".guestRuntimeStateInvalid"),
            "Guest runtime state invalid judgement belongs in Application/Domain policy, not the outbound reader"
        )
        XCTAssertTrue(
            text.contains("RuntimeGuestRuntimeStateObservationAssembler.loadFailed(message)"),
            "Guest runtime state load failure must stay explicit before observation assembly"
        )
        XCTAssertTrue(
            text.contains("RuntimeGuestRuntimeStateObservationAssembler.metadataReadFailed"),
            "Guest runtime state metadata failure must stay explicit before observation assembly"
        )
        XCTAssertFalse(
            text.contains("timeIntervalSince"),
            "Guest runtime state freshness policy must not live in the outbound reader"
        )
        XCTAssertTrue(
            text.contains("RuntimeGuestRuntimeStateObservationAssembler.loaded"),
            "Guest runtime state reader should delegate freshness observation assembly to Contracts"
        )
    }

    func testBackupActionPlanningLivesInPresentationPoliciesNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeBackupActionPlanner.swift"
                ).path
            ),
            "Backup action planning is presentation input planning and should live with presentation policies"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelBackupActionPlanner.swift"
                ).path
            ),
            "ViewModels should orchestrate UI state and actions, not own backup action planning types"
        )
    }

    func testHealthNotificationStatePolicyLivesInPresentationPoliciesNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeHealthNotificationState.swift"
                ).path
            ),
            "Health notification state classification is presentation policy and should live with presentation policies"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeHealthNotificationState.swift"
                ).path
            ),
            "ViewModels should own notification baseline state, not health notification classification policy"
        )
    }

    func testPresentationOptionsLiveInPoliciesNotViewModels() throws {
        let root = packageRoot()
        let eventPeriodPath = root.appendingPathComponent(
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeEventPeriodOption.swift"
        )
        for path in [
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeEventPeriodOption.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeLogPresentationOptions.swift",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "Presentation option definitions should live with presentation policies: \(path)"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeEventPeriodOption.swift"
                ).path
            ),
            "ViewModels should store selected option state, not own event period option definitions"
        )

        let eventPeriodText = try String(contentsOf: eventPeriodPath, encoding: .utf8)
        XCTAssertTrue(
            eventPeriodText.contains("sinceTimestamp(now: Date)"),
            "Event period timestamp calculation should consume explicit current time"
        )
        XCTAssertFalse(
            eventPeriodText.contains("Date()"),
            "Event period option policy must not read system time directly"
        )

        let logViewModelText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModel+Logs.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            logViewModelText.contains("RuntimeLogPresentationOptions"),
            "RuntimeViewModel log actions should consume presentation log options from policy"
        )
        XCTAssertFalse(
            logViewModelText.contains("private enum RuntimeLogOptions"),
            "RuntimeViewModel log actions must not own log option definitions"
        )
    }

    func testPresentationTimePoliciesConsumeExplicitNow() throws {
        let root = packageRoot()
        let remoteConsoleText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeStatusRemoteConsoleAvailabilityPolicy.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            remoteConsoleText.contains("now: Date"),
            "Remote console availability policy should consume explicit current time"
        )
        XCTAssertFalse(
            remoteConsoleText.contains("Date()"),
            "Remote console availability policy must not read system time directly"
        )
    }

    func testBackupDeletionSafetyPolicyIsSharedWithOutboundCommandBoundary() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Contracts/Shared/RuntimeManagedBackupPolicy.swift"
                ).path
            ),
            "Managed backup path validation should be a pure shared contract, not only a UI policy"
        )

        let commandWorker = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/MacRuntimeControlCommandWorker.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            commandWorker.contains("ensureManagedBackupDeletionTarget"),
            "deleteBackup must validate the deletion target before running privileged rm"
        )
        XCTAssertTrue(
            commandWorker.contains("RuntimeManagedBackupPolicy.isManagedBackupURL"),
            "Outbound deleteBackup must use the shared managed backup contract"
        )

        let backupReader = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Backups/RuntimeBackup.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            backupReader.contains("RuntimeManagedBackupPolicy.nameFragment"),
            "Outbound backup list reader must use the shared managed backup name convention"
        )
        XCTAssertTrue(
            backupReader.contains("RuntimeManagedBackupPolicy.isManagedBackupURL"),
            "Outbound backup list reader must validate latestBackupPath against the managed backup root"
        )

        let storageMaintenance = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/FileSystem/RuntimeStorageMaintenance.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            storageMaintenance.contains("RuntimeManagedBackupPolicy.nameFragment"),
            "Outbound storage maintenance must use the shared managed backup name convention"
        )

        let backupStore = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/Persistence/RuntimeBackupStore.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            backupStore.contains("RuntimeManagedBackupPolicy.nameFragment"),
            "Outbound backup store must use the shared managed backup name convention"
        )
        let backupStoreConfiguration = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/Persistence/RuntimeBackupStoreConfiguration.swift"
            ),
            encoding: .utf8
        )
        let managedBackupArtifactContract = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Contracts/Shared/RuntimeManagedBackupArtifact.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            managedBackupArtifactContract.contains("public enum RuntimeManagedBackupArtifact"),
            "Managed backup artifact identity belongs in Contracts as a shared update/backup contract"
        )
        XCTAssertFalse(
            backupStoreConfiguration.contains("public enum RuntimeManagedBackupArtifact"),
            "Outbound backup store configuration must only add host path mapping for managed backup artifacts"
        )
        XCTAssertTrue(
            backupStore.contains("BackupManifest.managedRuntimeBackup("),
            "Outbound backup store should delegate backup manifest construction to the contract document factory"
        )
        XCTAssertFalse(
            backupStore.contains("BackupManifest(\n"),
            "Outbound backup store must not directly decide backup manifest field meanings"
        )
    }

    func testOutboundLogReaderDoesNotOwnNoDataDisplayText() throws {
        let root = packageRoot()
        let runtimeClientContracts = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            runtimeClientContracts.contains("displayText"),
            "RuntimeControl contracts should expose typed text read results, not display formatting"
        )
        XCTAssertFalse(
            runtimeClientContracts.contains("func logText(")
                || runtimeClientContracts.contains("func loadLogText(")
                || runtimeClientContracts.contains("func updateBundleSummary(url:"),
            "RuntimeHostClient contract must not provide string convenience APIs that hide typed read state"
        )

        let readerText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeLogFileTextReader.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            readerText.contains(".missing(.noData)"),
            "Outbound log reader should report typed no-data state"
        )
        XCTAssertTrue(
            readerText.contains(".missing(.message(message))"),
            "Outbound log reader should preserve missing log files as explicit missing messages, not no-data"
        )
        XCTAssertFalse(
            readerText.contains("noLogData"),
            "Outbound log reader must not own display fallback text for missing log data"
        )

        let fileReaderText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeFileReaders.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(
            fileReaderText.contains("displayText"),
            "Outbound file readers should return typed text read results and leave display formatting to inbound boundaries"
        )

        let displayPolicy = root.appendingPathComponent("Sources/Adapters/Inbound/RuntimeHostTextDisplayPolicy.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: displayPolicy.path),
            "Log no-data display fallback belongs at the inbound presentation/API formatting boundary"
        )
    }

    func testTestKitInputPolicyLivesInPresentationPoliciesNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeTestKitPresentationPolicy.swift"
                ).path
            ),
            "Test Kit input and action availability policy should live with presentation policies"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelTestKitStatePolicy.swift"
                ).path
            ),
            "ViewModels should own UI state and action flow, not Test Kit input policy types"
        )
    }

    func testNavigationCoordinationLivesInPresentationNavigationNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/Navigation/RuntimeNavigationCoordinator.swift"
                ).path
            ),
            "Presentation navigation effects should live under the Navigation adapter folder"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelNavigationCoordinator.swift"
                ).path
            ),
            "ViewModels should orchestrate UI state and call navigation helpers, not own navigation effect types"
        )
    }

    func testUpdateBundleVerificationLivesInPresentationUpdateBundleNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/UpdateBundle/RuntimeUpdateBundleVerifier.swift"
                ).path
            ),
            "Update bundle verification result formatting should live with update bundle presentation"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelUpdateBundleVerifier.swift"
                ).path
            ),
            "ViewModels should trigger update bundle verification, not own verifier result mapping"
        )
    }

    func testClientActionRunningLivesInPresentationActionsNotViewModels() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/Actions/RuntimeClientActionRunner.swift"
                ).path
            ),
            "Client command action progress handling should live with presentation actions"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelCommandActionRunner.swift"
                ).path
            ),
            "ViewModels should present action state through a protocol, not own the shared command action runner"
        )
        let runnerFile = root.appendingPathComponent(
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Actions/RuntimeClientActionRunner.swift"
        )
        let runnerText = try String(contentsOf: runnerFile, encoding: .utf8)
        XCTAssertTrue(
            runnerText.contains("enum RuntimeClientActionRunResult"),
            "Client action runner must preserve success, command failure, and thrown action failure as explicit outcomes"
        )
        XCTAssertFalse(
            runnerText.contains(") async -> Bool"),
            "Client action runner must not collapse command/action outcomes to Bool"
        )
    }

    func testLogExportCleanupIssueIsPreservedThroughAdapterContractAndPresentation() throws {
        let root = packageRoot()
        let contractText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            contractText.contains("public let cleanupIssue: String?"),
            "Log export result must preserve successful archive creation and staging cleanup failure as distinct facts"
        )

        let exporterText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs/MacRuntimeControlLogExporter.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            exporterText.contains("cleanupIssue: cleanupStagingRoot(stagingRoot)"),
            "Outbound log exporter must report success-path staging cleanup issues instead of hiding them"
        )

        let viewModelText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModel+Logs.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            viewModelText.contains("result.cleanupIssue"),
            "Presentation must surface explicit log export cleanup issues returned by the host contract"
        )
    }

    func testRuntimeEventSQLiteCatchUpDueDoesNotCollapseReadFailureToBool() throws {
        let root = packageRoot()
        let repositoryText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/Persistence/SQLiteRuntimeEventRepository.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            repositoryText.contains("enum RuntimeEventIndexCatchUpDueRead"),
            "SQLite event catch-up due state must preserve due, not-due, and read-failure meanings"
        )
        XCTAssertFalse(
            repositoryText.contains("func catchUpDue(now: Date, intervalSeconds: TimeInterval) -> Bool"),
            "SQLite event catch-up due reads must not collapse read failure to Bool"
        )

        let catchUpText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/Persistence/RuntimeEventSQLiteProjectionCatchUp.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            catchUpText.contains("case .dueAfterReadFailure(let reason)")
                && catchUpText.contains("runtime event sqlite catch-up due read failed"),
            "Projection catch-up should keep attempting recovery while reporting due-state read failures"
        )
    }

    func testSQLiteObservabilityTransactionsDoNotDiscardRollbackFailure() throws {
        let root = packageRoot()
        let databaseText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/ObservabilityStore/SQLiteRuntimeObservabilityDatabase.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            databaseText.contains("func rollbackTransactionAfterFailure")
                && databaseText.contains("transactionRollbackFailed"),
            "SQLite observability transactions must preserve rollback failure alongside the original failure"
        )

        for relativePath in [
            "Sources/Adapters/Outbound/ObservabilityStore/SQLiteRuntimeEventStore.swift",
            "Sources/Adapters/Outbound/ObservabilityStore/SQLiteVitalDBObservationStore.swift",
        ] {
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertFalse(
                text.contains("try? execute(db, sql: \"ROLLBACK\")"),
                "\(relativePath) must not silently discard rollback failures at the repository boundary"
            )
            XCTAssertTrue(
                text.contains("rollbackTransactionAfterFailure(db, originalError: error)"),
                "\(relativePath) should use the explicit rollback failure-preserving helper"
            )
        }
    }

    func testPresentationReachabilityPolicyDoesNotOwnServiceOrVMStateSeverity() throws {
        let root = packageRoot()
        let reachabilityText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeStatusReachabilityPolicy.swift"
            ),
            encoding: .utf8
        )
        for token in [
            "serviceStateSeverity",
            "vmStateSeverity",
            "shouldDisplayOperationStateInsteadOfServiceState",
        ] {
            XCTAssertFalse(
                reachabilityText.contains(token),
                "HTTP reachability presentation policy must not also own service or VM state presentation severity: \(token)"
            )
        }

        for relativePath in [
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeStatusServiceStatePresentationPolicy.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeStatusVMStatePresentationPolicy.swift",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path),
                "Service and VM state presentation severity should live in focused presentation policies"
            )
        }
    }

    func testLogCollectionRotationUsesExplicitNowDecisionRulesOutsideCollectorIO() throws {
        let root = packageRoot()
        let collectorPath = root.appendingPathComponent(
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs/MacRuntimeControlLogCollector.swift"
        )
        let decisionRulesPath = root.appendingPathComponent(
            "Sources/Contracts/RuntimeControl/RuntimeLogCollectionDecisionRules.swift"
        )
        let collectorText = try String(contentsOf: collectorPath, encoding: .utf8)
        let decisionRulesText = try String(contentsOf: decisionRulesPath, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: decisionRulesPath.path),
            "Log collection decisions should live in focused RuntimeControl contract decision rules, not inside the IO collector"
        )
        XCTAssertTrue(
            collectorText.contains("RuntimeLogCollectionDecisionRules"),
            "MacRuntimeControlLogCollector should delegate pure log collection decisions to RuntimeLogCollectionDecisionRules"
        )
        XCTAssertFalse(
            collectorText.contains("isDateInToday"),
            "Log collection rotation must not use implicit system-date helpers inside the outbound IO collector"
        )
        XCTAssertTrue(
            decisionRulesText.contains("RuntimeLogCollectionRotationInput")
                && decisionRulesText.contains("calendar.isDate(input.modificationDate, inSameDayAs: input.now)"),
            "Log collection rotation should compare file modification dates against explicit now input"
        )
    }

    func testRuntimeEventFactoryLivesInApplicationObservabilityUseCases() throws {
        let root = packageRoot()
        for fileName in [
            "RuntimeEventFactory.swift",
            "RuntimeEventPublisher.swift",
            "RuntimeObservationRecorder.swift",
            "RuntimeObservedEventPublisher.swift",
            "RuntimeObservedStatusPublisher.swift",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(
                        "Sources/Application/UseCases/Observability/\(fileName)"
                    ).path
                ),
                "\(fileName) is event document assembly/publishing orchestration and belongs in Application/UseCases/Observability"
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(
                        "Sources/Adapters/Outbound/ObservabilityStore/\(fileName)"
                    ).path
                ),
                "Outbound ObservabilityStore must persist/project event documents, not own event publishing orchestration: \(fileName)"
            )
        }
    }

    func testOutboundAdaptersDoNotConstructRuntimeStatusDocuments() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters/Outbound")
        for file in try swiftFiles(root: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("RuntimeStatusDocument("),
                "Outbound adapters must persist status documents, not own status document construction policy: \(file.path)"
            )
        }
    }

    func testOutboundAdaptersDoNotAssembleRuntimeControlStatusReadModel() throws {
        let root = packageRoot().appendingPathComponent("Sources/Adapters/Outbound")
        for file in try swiftFiles(root: root) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("RuntimeStatus("),
                "Outbound adapters must read external state; RuntimeControl read model assembly belongs in RuntimeControl contracts: \(file.path)"
            )
        }
    }

    func testRuntimeLiveDiagnosticsAssemblyDoesNotLiveInOutboundReader() throws {
        let root = packageRoot()
        let reader = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeLiveDiagnosticsReader.swift")
        let readerText = try String(contentsOf: reader, encoding: .utf8)

        XCTAssertTrue(
            readerText.contains("RuntimeLiveDiagnosticsAssembler.makeDiagnostics"),
            "RuntimeLiveDiagnosticsReader should read live state and delegate diagnostics read model assembly to RuntimeControl"
        )
        for token in [
            "RuntimeStatusReadIssue",
            "RuntimeServiceStateRead(",
            "runtimeInstalled:",
            "unknown service state",
            "readIssue(",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "Outbound diagnostics reader must not own RuntimeControl read model policy: \(token)"
            )
        }

        let assembler = root
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift")
        let assemblerText = try String(contentsOf: assembler, encoding: .utf8)
        XCTAssertTrue(assemblerText.contains("public enum RuntimeLiveDiagnosticsAssembler"))
    }

    func testRuntimeHealthProbeStatusAssemblyDoesNotLiveInOutboundReader() throws {
        let root = packageRoot()
        let reader = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeStatusReader.swift")
        let readerText = try String(contentsOf: reader, encoding: .utf8)

        XCTAssertTrue(
            readerText.contains("RuntimeHealthStatusAssembler.applyingHealthProbeReads"),
            "RuntimeStatusReader should read HTTP probe results and delegate RuntimeStatus mutation policy to RuntimeControl"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeStatusReadModels.swift"
                    )
                    .path
            ),
            "Runtime HTTP read model contracts belong in RuntimeControl, not an Outbound read-model bucket"
        )
        for token in [
            "next.guestHTTP",
            "next.hostProxyHTTP",
            "next.redisUIHTTP",
            "next.swaggerUIHTTP",
            "missingVMIP",
            "appendStatusReadIssue",
            "appendUniqueStatusReadIssue",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "Outbound RuntimeStatusReader must not own health probe status assembly: \(token)"
            )
        }

        let runtimeControlAssembly = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(runtimeControlAssembly.contains("public enum RuntimeHealthStatusAssembler"))
        XCTAssertTrue(runtimeControlAssembly.contains("RuntimeHTTPStatusText.missingVMIP"))
    }

    func testRuntimeDataDirectoryMetricsAssemblyDoesNotLiveInOutboundReader() throws {
        let root = packageRoot()
        let reader = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeStatusReader.swift")
        let readerText = try String(contentsOf: reader, encoding: .utf8)

        XCTAssertTrue(
            readerText.contains("RuntimeDataDirectoryMetricsAssembler.applyingMetricReads"),
            "RuntimeStatusReader should collect data directory metric reads and delegate RuntimeStatus mutation policy to RuntimeControl"
        )
        for token in [
            "next.dataStorage",
            "next.dataStorageError",
            "next.dataDirectoryStats",
            "next.dataDirectoryStatsError",
            "var next = status",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "Outbound RuntimeStatusReader must not own data directory metric status assembly: \(token)"
            )
        }

        let runtimeControlAssembly = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(runtimeControlAssembly.contains("public enum RuntimeDataDirectoryMetricsAssembler"))
        XCTAssertTrue(
            runtimeControlAssembly.contains("case missing(path: String)"),
            "RuntimeControl must preserve missing data directory state distinctly from unavailable and failed stats reads"
        )
        XCTAssertFalse(
            runtimeControlAssembly.contains("case loaded(RuntimeDataDirectoryStats?)"),
            "RuntimeControl data directory stats reads must not encode missing stats as loaded nil"
        )

        let statsReaderText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeDataDirectoryStatsReader.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            statsReaderText.contains("RuntimeDataDirectoryStats?"),
            "Outbound data directory stats reader must return an explicit read state, not optional stats"
        )
        XCTAssertTrue(
            statsReaderText.contains("return .missing(path: root.path)"),
            "Outbound data directory stats reader must preserve missing configured directories as explicit missing state"
        )
    }

    func testRuntimeObservabilityProjectionAssemblyDoesNotLiveInOutboundReader() throws {
        let root = packageRoot()
        let reader = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeObservabilityReader.swift")
        let readerText = try String(contentsOf: reader, encoding: .utf8)

        for token in [
            "RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot",
            "RuntimeVitalDBRecorderHistoryAssembler.makeHistory",
            "RuntimeVitalDBRelationshipHistoryAssembler.makeHistory",
        ] {
            XCTAssertTrue(
                readerText.contains(token),
                "RuntimeObservabilityReader should collect projection reads and delegate read-model assembly: \(token)"
            )
        }
        XCTAssertTrue(
            readerText.contains("RuntimeVitalDBProjectionReadCollector"),
            "RuntimeObservabilityReader should delegate projection read collection to a dedicated Outbound collector"
        )

        let collector = root
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeVitalDBProjectionReadCollector.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: collector.path),
            "Outbound projection reads should be collected behind an explicit collector boundary"
        )

        for token in [
            "RuntimeVitalDBObservationSnapshot(",
            "RuntimeVitalRecorderHistory(",
            "RuntimeVitalRelationshipHistory(",
            "readErrors",
            "assignmentsReadFailed",
            "eventsReadFailed",
            ".partiallyLoaded",
            ".readFailed",
            "joinedReadError",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "Outbound RuntimeObservabilityReader must not own observability projection assembly: \(token)"
            )
        }
        for token in [
            "private func latestObservationRead",
            "private func observationListRead",
            "private func recorderActivityBucketListRead",
            "private func bedAssignmentListRead",
            "private func relationshipEventListRead",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "RuntimeObservabilityReader must not own low-level projection read collection helpers: \(token)"
            )
        }

        for removedPath in [
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeObservabilityReadError.swift",
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeVitalRelationshipProjectionMapper.swift",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(removedPath).path),
                "RuntimeControl assembly should own this read-model policy, not Outbound: \(removedPath)"
            )
        }

        let runtimeControlAssembly = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeObservabilityAssembly.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(runtimeControlAssembly.contains("public enum RuntimeVitalDBObservationSnapshotAssembler"))
        XCTAssertTrue(runtimeControlAssembly.contains("public enum RuntimeVitalDBRecorderHistoryAssembler"))
        XCTAssertTrue(runtimeControlAssembly.contains("public enum RuntimeVitalDBRelationshipHistoryAssembler"))
    }

    func testRuntimeStatusReaderUsesSharedProcessFailureFormatter() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeStatusReader.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(
            text.contains("RuntimeProcessFailureMessageFormatter.message("),
            "RuntimeStatusReader should keep command failure formatting delegated to the shared Contracts formatter"
        )
        for token in [
            "func commandFailureMessage",
            "executionIssue=",
            "outputIssues=",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeStatusReader reads/probes status; command failure message formatting must stay shared: \(token)"
            )
        }
    }

    func testRuntimeSettingsReaderDelegatesReadModelPolicyToRuntimeControl() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Settings/RuntimeSettingsReader.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(
            text.contains("RuntimeSettingsReadPolicy.settings(from: loadSnapshot())"),
            "RuntimeSettingsReader should collect explicit reads and delegate settings assembly to RuntimeControl"
        )
        for token in [
            "RuntimeSettingsReadPolicy.applyVMConfig",
            "RuntimeSettingsReadPolicy.applyGuestRuntimeSettings",
            "RuntimeSettingsReadPolicy.appendReadIssue",
            "var settings = RuntimeSettings()",
            "redisBackupRetentionCount is out of range",
            "network mode is invalid",
            "bridgedInterface is missing for bridged network mode",
            "autoRecoveryEnabled is missing",
            "preventSystemSleep is missing",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "RuntimeSettingsReader must not own RuntimeSettings read model policy: \(token)"
            )
        }
    }

    func testProcessFailureFormatterDoesNotDependOnRuntimeControlReadModels() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Contracts/Shared/RuntimeProcessFailureMessageFormatter.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeProcessFailureMessageFormatter.swift")
                    .path
            ),
            "Process failure formatting is a Contracts concern; Outbound adapters should only call it"
        )
        XCTAssertFalse(
            text.contains("import RuntimeControl"),
            "Generic process failure formatting must not depend on RuntimeControl client read models"
        )
        XCTAssertFalse(
            text.contains("RuntimeCommandResult"),
            "RuntimeControl command result adaptation should happen at the caller boundary, not inside Process formatter"
        )
    }

    func testRuntimeControlOverviewAssemblerDoesNotMutateStatusObservation() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlOverviewAssembler.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("status.vitalDBObservation ="),
            "RuntimeControl overview must carry VitalDB observation through explicit overview fields, not by mutating status"
        )
    }

    func testPresentationDoesNotAnnotateRuntimeStatusWithSyntheticRuntimeControlState() throws {
        let root = packageRoot()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeControlStatusAnnotator.swift"
                    )
                    .path
            ),
            "Presentation must not create RuntimeStatus runtimeControl fields; host/read contracts should provide state explicitly"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeControlStatusAnnotator.swift")
                    .path
            ),
            "RuntimeControl local API state must use explicit read contracts and assemblers, not an annotator type"
        )
        for file in try swiftFiles(root: root.appendingPathComponent("Sources")) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("RuntimeControlStatusAnnotator"),
                "RuntimeControlStatusAnnotator must not reappear in Sources; use RuntimeControlLocalAPIStatusRead and RuntimeControlLocalAPIStatusAssembler: \(file.path)"
            )
        }
        let hostHandlerFile = root
            .appendingPathComponent("Sources/Hosts/MacControlPanel/Composition/MacRuntimeControlAPIHandler.swift")
        let hostHandlerText = try String(contentsOf: hostHandlerFile, encoding: .utf8)
        XCTAssertTrue(
            hostHandlerText.contains("RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus"),
            "Host should pass explicit local API status reads through the RuntimeControl assembler"
        )

        let presentationRoot = root
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation")
        for file in try swiftFiles(root: presentationRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                ".runtimeControlHTTP =",
                ".runtimeControlStartedAt =",
            ] {
                XCTAssertFalse(
                    text.contains(token),
                    "Presentation must not mutate RuntimeStatus runtimeControl state: \(token) in \(file.path)"
                )
            }
        }
    }

    func testPresentationFormatterDoesNotCreateOpenURLFallbacksFromMissingAdvertisedURLs() throws {
        let formatterFile = packageRoot()
            .appendingPathComponent(
                "Sources/Adapters/Inbound/MacControlPanel/Presentation/Formatting/RuntimePresentationFormatter.swift"
            )
        let formatterText = try String(contentsOf: formatterFile, encoding: .utf8)

        XCTAssertTrue(
            formatterText.contains("public let openURL: String?"),
            "Presentation URL open target must be optional so display presets do not become actionable state"
        )
        XCTAssertTrue(
            formatterText.contains("ServiceURLPresentation(displayURL: displayFallback, openURL: nil)"),
            "Missing advertised URL may have display text, but must not create an open URL fallback"
        )
        XCTAssertFalse(
            formatterText.contains("openFallback"),
            "Presentation formatter must not create actionable URL fallbacks from missing advertised settings"
        )
    }

    func testMacHostRemoteConsoleStatusUsesExplicitLocalAPIReadContract() throws {
        let environmentFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/MacControlPanel/Composition/MacRuntimeControlEnvironment.swift")
        let environmentText = try String(contentsOf: environmentFile, encoding: .utf8)

        XCTAssertTrue(
            environmentText.contains("RuntimeControlLocalAPIStatusRead.reachable"),
            "Mac host environment should publish reachable local API state through the shared read contract"
        )
        XCTAssertTrue(
            environmentText.contains("RuntimeControlLocalAPIStatusRead.failed"),
            "Mac host environment should publish failed local API state through the shared read contract"
        )
        XCTAssertFalse(
            environmentText.contains(#"updateRemoteConsoleStatus(http: "200""#),
            "Mac host environment must not inject raw reachable HTTP strings into presentation state"
        )
        XCTAssertFalse(
            environmentText.contains(#"updateRemoteConsoleStatus(http: "failed""#),
            "Mac host environment must not inject raw failed HTTP strings into presentation state"
        )
    }

    func testRecorderSummaryPolicyUsesExplicitVitalDBObservationSnapshotInput() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies/RuntimeStatusRecorderSummaryPolicy.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("status.vitalDBObservation"),
            "Recorder summary must use explicit VitalDB observation snapshot input, not stale status observation"
        )
        XCTAssertTrue(
            text.contains("vitalDBObservation: VitalDBObservationDocument?"),
            "Recorder summary must require explicit VitalDB observation input"
        )
    }

    func testOutboundObservabilityReaderUsesSnapshotContractForVitalDBObservation() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeObservabilityReader.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(
            text.contains("func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot"),
            "Outbound observability reader must expose VitalDB observation through explicit snapshot state"
        )
        XCTAssertFalse(
            text.contains("func loadVitalDBObservation() -> VitalDBObservationDocument?"),
            "Outbound observability reader must not collapse failed/unavailable/missing observation state into optional nil"
        )
    }

    func testRuntimeControlClientContractDoesNotExposeOptionalVitalDBObservationShortcut() throws {
        let contractFile = packageRoot()
            .appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift")
        let workerFile = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/MacRuntimeControlReadWorker.swift")
        let contractText = try String(contentsOf: contractFile, encoding: .utf8)
        let workerText = try String(contentsOf: workerFile, encoding: .utf8)

        XCTAssertTrue(
            contractText.contains("func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot"),
            "Runtime control client contract must expose VitalDB observation through explicit snapshot state"
        )
        XCTAssertFalse(
            contractText.contains("func loadVitalDBObservation() -> VitalDBObservationDocument?"),
            "Runtime control client contract must not collapse failed/unavailable/missing observation state into optional nil"
        )
        XCTAssertFalse(
            workerText.contains("func loadVitalDBObservation() -> VitalDBObservationDocument?"),
            "Read worker must not reintroduce optional observation shortcuts"
        )
    }

    func testRepairProxyCommandContractDoesNotAcceptUnusedProxyPortInput() throws {
        let root = packageRoot()
        let files = [
            "Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift",
            "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPTypes.swift",
            "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPIRequests.swift",
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Client/MacRuntimeControlClient.swift",
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/MacRuntimeControlCommandWorker.swift",
        ]

        for relativePath in files {
            let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertFalse(
                text.contains("repairProxy(proxyPort:"),
                "Proxy repair command boundary must not accept unused proxyPort input: \(relativePath)"
            )
            XCTAssertFalse(
                text.contains("RuntimeRepairProxyRequest"),
                "Proxy repair HTTP boundary must not expose a request body for unused proxyPort input: \(relativePath)"
            )
        }
    }

    func testCommandWorkerDelegatesExecutablePreflightPolicy() throws {
        let root = packageRoot()
        let workerPath = root.appendingPathComponent(
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/MacRuntimeControlCommandWorker.swift"
        )
        let preflightPath = root.appendingPathComponent(
            "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/RuntimeExecutableCommandPreflight.swift"
        )
        let workerText = try String(contentsOf: workerPath, encoding: .utf8)
        let preflightText = try String(contentsOf: preflightPath, encoding: .utf8)

        XCTAssertTrue(
            preflightText.contains("enum RuntimeExecutableCommandPreflight"),
            "Executable state error mapping should be an adapter-local stateless preflight policy"
        )
        XCTAssertTrue(
            workerText.contains("RuntimeExecutableCommandPreflight.requireExecutable"),
            "Command worker should orchestrate state read and command execution, not own executable state policy"
        )
        for token in [
            "case .missing:",
            "case .inspectFailed",
            "case .present:",
            "case .unknown",
        ] {
            XCTAssertFalse(
                workerText.contains(token),
                "Command worker must not own executable state mapping policy: \(token)"
            )
        }
    }

    func testHostTextReadResultPreservesDegradedLoadedState() throws {
        let root = packageRoot()
        let contractText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift"),
            encoding: .utf8
        )
        let fileReaderText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeFileReaders.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            contractText.contains("case loadedWithIssue(text: String, issue: String)"),
            "Host text reads must preserve degraded loaded state instead of hiding dependency failures"
        )
        XCTAssertTrue(
            fileReaderText.contains("preservingRefreshIssue"),
            "Runtime file reader should combine refresh failures with loaded/read-failed log text explicitly"
        )
        XCTAssertFalse(
            fileReaderText.contains("if case .missing = text"),
            "Refresh failures must not be reported only when log text is missing"
        )
    }

    func testRecorderActivityDisplayDoesNotHideInvalidTimestampsAsOldSamples() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/Views/RuntimeRecorderActivityChartDataBuilder.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains(".distantPast"),
            "Recorder activity display must keep invalid timestamps distinct instead of sorting them as old samples"
        )
        XCTAssertTrue(
            text.contains("case invalidTimeline(String)"),
            "Recorder activity display must expose invalid timestamp state explicitly"
        )
    }

    func testRuntimeEventRefreshDoesNotPromoteHistoricalObservationToCurrentState() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh/RuntimeObservabilityRefresher.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("events.events.first { $0.containerObservation != nil }?.containerObservation"),
            "Runtime event payloads are historical observations; ViewModel refresh must not promote them to current container state"
        )
        XCTAssertTrue(
            text.contains("containerObservation: statusContainerObservation"),
            "Current container observation must come from the explicit status refresh input"
        )
    }

    func testPresentationRefreshHelpersLiveInRefreshNotViewModels() throws {
        let root = packageRoot()
        let refreshFiles = [
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh/RuntimePresentationSnapshotLoader.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh/RuntimeStatusRefresher.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh/RuntimeObservabilityRefresher.swift",
        ]
        for path in refreshFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "Presentation refresh helpers should live in the Refresh role folder: \(path)"
            )
        }

        let viewModelFiles = [
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelSnapshotLoader.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelStatusRefresher.swift",
            "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModelObservabilityRefresher.swift",
        ]
        for path in viewModelFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "ViewModels should own UI state, not shared refresh/snapshot helpers: \(path)"
            )
        }
    }

    func testRuntimeViewModelDoesNotCreatePlaceholderRuntimeStatus() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModel.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            text.contains("@Published var status = RuntimeStatus()"),
            "RuntimeViewModel must initialize status from explicit host/client state, not from an empty placeholder"
        )
        XCTAssertTrue(
            text.contains("@Published var status: RuntimeStatus"),
            "RuntimeViewModel should keep status non-optional while requiring explicit initialization"
        )
        XCTAssertTrue(
            text.contains("let loadedSettings = initialSettings ?? controlClient.loadSettings()")
                && text.contains("localAPISettings?.settingsWithLocalAPIPort(loadedSettings) ?? loadedSettings")
                && text.contains("initialStatus ?? controlClient.loadStatus(settings: resolvedSettings)"),
            "RuntimeViewModel init must use explicit initialStatus or load status from the control client"
        )
        XCTAssertFalse(
            text.contains(") ?? (initialSettings ?? controlClient.loadSettings())"),
            "RuntimeViewModel init must resolve settings source once before applying local API overrides"
        )
    }

    func testApplicationUseCasesAreStatelessStructsWithoutOwnedPorts() throws {
        let useCaseRoot = packageRoot().appendingPathComponent("Sources/Application/UseCases")
        let useCaseFiles = try swiftFiles(root: useCaseRoot)
            .filter { $0.lastPathComponent.hasSuffix("UseCase.swift") }
        XCTAssertFalse(useCaseFiles.isEmpty, "Application/UseCases must contain explicit usecase files")

        for file in useCaseFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("class ") && text.contains("UseCase"),
                "Usecases must not be class declarations: \(file.path)"
            )

            let body = try useCaseStructBody(in: text, file: file)
            XCTAssertFalse(body.contains("ports."), "Usecases must not own or call ports directly: \(file.path)")
            XCTAssertFalse(body.contains("Ports"), "Usecases must not own port bundles: \(file.path)")

            for token in [
                "FileManager",
                "Process(",
                "URLSession",
                "Data(contentsOf",
                "String(contentsOf",
            ] {
                XCTAssertFalse(body.contains(token), "Usecases must not perform direct IO/effects via \(token): \(file.path)")
            }

            for line in topLevelLines(in: body) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                XCTAssertFalse(
                    storedPropertyPatternMatches(trimmed),
                    "Usecase structs must remain stateless and not declare stored properties: \(file.path) line=\(trimmed)"
                )
            }
        }
    }

    func testWorkflowDoesNotOwnConcreteHostEffects() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "FileManager.default",
                "URLSession",
                "import Virtualization",
                "import SQLite3",
                "VZVirtual",
            ] {
                XCTAssertFalse(text.contains(token), "Workflow must use ports/operations instead of concrete host effect \(token): \(file.path)")
            }
            XCTAssertFalse(
                containsConcreteProcessInvocation(text),
                "Workflow must use ports/operations instead of constructing Process directly: \(file.path)"
            )
        }
    }

    func testDomainPoliciesDoNotOwnPollingOrEffectClosures() throws {
        let domainRoot = packageRoot().appendingPathComponent("Sources/Domain")
        for file in try swiftFiles(root: domainRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "sleep:",
                "onProgress:",
                "observe:",
                "loadResult: () ->",
                "Thread.sleep",
            ] {
                XCTAssertFalse(
                    text.contains(token),
                    "Domain must return pure decisions; polling/effect closure \(token) belongs in Workflow/Application: \(file.path)"
                )
            }
        }
    }

    func testBootstrapDoesNotOwnCommandExecutionDetails() throws {
        let bootstrapRoot = packageRoot().appendingPathComponent("Sources/Bootstrap")
        for file in try swiftFiles(root: bootstrapRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in [
                "Constants.Commands",
                "runProcess",
                "runRequired",
                "runProcessToFile",
                "Process(",
                "FileManager",
                "ProcessInfo",
            ] {
                XCTAssertFalse(
                    text.contains(token),
                    "Bootstrap must assemble explicit ports, not own command execution details via \(token): \(file.path)"
                )
            }
        }
    }

    func testWorkflowDoesNotCallDomainPolicyOrReasonFormatterDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                containsRegex(#"Runtime[A-Za-z0-9]+Policy\."#, in: text),
                "Workflow must call Application usecases instead of Domain policy static methods directly: \(file.path)"
            )
            XCTAssertFalse(
                text.contains("RuntimeFailureReasonText.describe"),
                "Workflow must call Application usecases instead of formatting failure reasons directly: \(file.path)"
            )
        }
    }

    func testWorkflowDoesNotDescribeErrorsDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let forbiddenTokens = [
                "error.localizedDescription",
                "String(describing:",
                #"\(error)"#,
                "RuntimeErrorDescription.describe",
            ]
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "Workflow must use Errors/Application contracts instead of formatting Error directly with \(token): \(file.path)"
                )
            }
        }
    }

    func testWorkflowDoesNotInterpretOperationStepsDirectly() throws {
        let workflowRoot = packageRoot().appendingPathComponent("Sources/Workflow")
        for file in try swiftFiles(root: workflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("switch step"),
                "Workflow must ask UseCase for step execution plans instead of interpreting RuntimeWorkflowStep directly: \(file.path)"
            )
        }
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretOperationStepsDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("switch step"),
                "RuntimeUpdateLifecycle Workflow must ask UseCase for step execution plans instead of interpreting RuntimeWorkflowStep directly: \(file.path)"
            )
        }
    }

    func testRuntimeInstallLifecycleKeepsStatefulWorkflowOnly() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallWorkflow.swift")
                    .path
            ),
            "Install state/progress orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeInstallComposition.swift")
                    .path
            ),
            "Install concrete runner wiring belongs at the Host process boundary"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeFreshInstallPreflightRunner.swift",
            "Sources/Workflow/RuntimeInstallLifecycle/RuntimeInstallStepExecutor.swift",
            "Sources/Errors/Definitions/RuntimeInstallWorkflowError.swift",
            "Sources/Bootstrap/Composition/RuntimeInstallComposition.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Install Workflow must not own preflight adapters, step executors, or Workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeInstallLifecycleWorkflowDirectoryHasOnlyWorkflowRunner() throws {
        let installWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeInstallLifecycle")
        let fileNames = Set(try swiftFiles(root: installWorkflowRoot).map(\.lastPathComponent))
        XCTAssertEqual(
            fileNames,
            ["RuntimeInstallWorkflow.swift"],
            "RuntimeInstallLifecycle Workflow must keep only the stateful runner"
        )
    }

    func testRuntimeInstallStepExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeInstallComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Install concrete execution belongs at the Host process boundary, not Bootstrap"
        )
    }

    func testRuntimeConfigureExecutionDoesNotRemainInBootstrapOrWorkflow() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeConfigureRunner.swift")
                    .path
            ),
            "Runtime configure execution belongs at the Host process boundary"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeConfigureRunner.swift")
                    .path
            ),
            "Runtime configure execution must not live in Bootstrap composition"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Workflow/RuntimeConfigureLifecycle/RuntimeConfigureWorkflow.swift")
                    .path
            ),
            "Runtime configure execution belongs in Application usecase and Host process boundary, not Workflow"
        )
    }

    func testRuntimeHealthWaitExecutionBelongsInWorkflow() {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Workflow/RuntimeHealth/RuntimeHealthWaitWorkflow.swift",
            "Sources/Workflow/RuntimeHealth/RuntimeHealthWaitRunner.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must own runtime health wait execution"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Adapters/Inbound/CLI/Presentation/RuntimeHealthWaitRunner.swift"
                ).path
            ),
            "Runtime health wait execution must not live in inbound presentation adapters"
        )
    }

    func testRuntimeHealthWaitSleepIntervalDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeHealthWaitRunnerComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime health wait concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeHealthWaitRunnerComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime health wait Host process-boundary composition must exist"
        )

        let workflowText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Workflow/RuntimeHealth/RuntimeHealthWaitRunner.swift"),
            encoding: .utf8
        )
        for token in [
            "RuntimeHealthWaitWorkflowContext",
            "sleep:",
        ] {
            XCTAssertTrue(
                workflowText.contains(token),
                "Runtime health wait polling flow belongs in Workflow: \(token)"
            )
        }
    }

    func testRuntimeHealthRefreshExecutionDoesNotRemainInWorkflow() {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeHealth/RuntimeHealthRefreshWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeHealthRefreshWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime health refresh execution"
            )
        }
    }

    func testRuntimeDatastoreRepairKeepsStatefulWorkflowOnly() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairWorkflow.swift").path
            ),
            "Datastore repair request/wait/restart orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeDatastoreRepairComposition.swift").path
            ),
            "Datastore repair Host process-boundary composition must exist"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairRunner.swift",
            "Sources/Workflow/RuntimeRepairLifecycle/RuntimeDatastoreRepairResultWaiter.swift",
            "Sources/Errors/Definitions/RuntimeDatastoreRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own datastore repair concrete execution"
            )
        }
    }

    func testRuntimeDatastoreRepairBestEffortStatusDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeDatastoreRepairComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Datastore repair concrete execution belongs at the Host process boundary, not Bootstrap"
        )
    }

    func testRepairRuntimeUseCasesStaySplitByOperationResponsibility() throws {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Application/UseCases/RepairRuntime/RepairRuntimeSharedPlans.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeVMDiskRepairUseCase.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeDatastoreRepairUseCase.swift",
            "Sources/Application/UseCases/RepairRuntime/RuntimeRedisBackupUseCase.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "RepairRuntime usecase responsibility must stay operation-specific: \(path)"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Application/UseCases/RepairRuntime/RepairRuntimeUseCase.swift"
                ).path
            ),
            "RepairRuntimeUseCase must not return as a mixed VM disk/datastore/Redis backup planning bucket"
        )

        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
        ]
        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("RepairRuntimeUseCase("),
                "Callers must depend on operation-specific repair usecases instead of RepairRuntimeUseCase: \(file.path)"
            )
        }
    }

    func testRuntimeServiceLifecycleExecutionDoesNotRemainInWorkflow() throws {
        let root = packageRoot()
        let forbiddenFiles = [
            "Sources/Workflow/RuntimeServiceLifecycle/RuntimeServiceLifecycleWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeServiceLifecycleWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime service lifecycle execution"
            )
        }
    }

    func testRuntimeServiceStopPollingDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/DI/RuntimeLifecycleComposition.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in [
            "Thread.sleep",
            "while try",
            "waitUntilServiceStops",
            "launchdServiceIsLoaded",
            "service did not unload within",
            "launchd service state read failed",
            "ProcessState.",
            "requestStopAndWait",
            "waitUntilObservedProcessStopped",
            "RuntimeVMLifecycleStore(",
            "print(\"[",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "Runtime service stop polling belongs in OutboundAdapters, not Bootstrap: \(token)"
            )
        }

        let hostText = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift"),
            encoding: .utf8
        )
        for token in [
            "StopRuntimeVMProcessUseCase().requestStopAndWait",
            "StopRuntimeVMProcessUseCase().waitUntilObservedProcessStopped",
            "RuntimeVMLifecycleStore(",
        ] {
            XCTAssertTrue(
                hostText.contains(token),
                "Runtime service process-boundary execution must stay in HostCLI: \(token)"
            )
        }
    }

    func testRuntimeVMProcessStopStateInterpretationLivesInContracts() throws {
        let root = packageRoot()
        let contractsFile = root
            .appendingPathComponent("Sources/Contracts/Shared/RuntimeVMProcessStopStatePolicy.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contractsFile.path),
            "VM process stop state interpretation must live in Contracts"
        )

        for removedAdapterPath in [
            "Sources/Adapters/Outbound/Process/ProcessStateStopWait.swift",
            "Sources/Adapters/Outbound/Process/ProcessStateStopRequests.swift",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(removedAdapterPath).path),
                "Outbound process adapters must not own VM process stop sequencing: \(removedAdapterPath)"
            )
        }

        let useCaseFile = root
            .appendingPathComponent("Sources/Application/UseCases/RuntimeServices/StopRuntimeVMProcessUseCase.swift")
        let useCaseText = try String(contentsOf: useCaseFile, encoding: .utf8)
        XCTAssertTrue(
            useCaseText.contains("RuntimeVMProcessStopStatePolicy.blockingFailureMessage"),
            "Application process stop usecase should delegate blocking interpretation to Contracts"
        )
        for token in [
            "failed to send signal to VM process",
            "VM process did not stop within",
            "VM process is still running",
            "unknown VM process state value",
        ] {
            XCTAssertFalse(
                useCaseText.contains(token),
                "Application process stop usecase must not own stop-state failure wording: \(token)"
            )
        }
    }

    func testHostProxyNginxOwnershipPolicyDoesNotLiveInOutboundAdapter() throws {
        let root = packageRoot()
        let policyFile = root
            .appendingPathComponent("Sources/Application/UseCases/RuntimeServices/RuntimeHostProxyNginxOwnershipPolicy.swift")
        let readerFile = root
            .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyNginxCommandLineReader.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: policyFile.path),
            "Host proxy nginx ownership judgement belongs in Application policy"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: readerFile.path),
            "Outbound process adapter should only read explicit nginx command line state"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyNginxOwnershipClassifier.swift")
                    .path
            ),
            "Outbound process adapter must not own Host proxy nginx ownership classification"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyOwnedListenerStopper.swift")
                    .path
            ),
            "Outbound process adapter must not own Host proxy TERM/KILL stop sequencing"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/RuntimeProxyRepairCommandFactory.swift")
                    .path
            ),
            "Mac control outbound adapter must not hide host proxy ownership and kill policy in a privileged bash factory"
        )

        let useCaseText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Application/UseCases/RuntimeServices/CleanRuntimeHostProxyPortUseCase.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            useCaseText.contains("RuntimeHostProxyNginxOwnershipPolicy.classify"),
            "Clean host proxy port usecase should delegate ownership judgement to Application policy"
        )
        XCTAssertTrue(
            useCaseText.contains("operations.signalOwnedListener(pid, signal)"),
            "Clean host proxy port usecase should own TERM/KILL sequencing and call adapter signal ports explicitly"
        )

        let readerText = try String(contentsOf: readerFile, encoding: .utf8)
        for token in [
            "ownedNginxPathFragments",
            "RuntimeHostProxyListenerClassification",
            "commandLine.contains(",
        ] {
            XCTAssertFalse(
                readerText.contains(token),
                "Outbound nginx command line reader must not own ownership judgement: \(token)"
            )
        }

        let macCommandFactoryText = try String(
            contentsOf: root
                .appendingPathComponent("Sources/Adapters/Outbound/MacRuntimeControlClient/Commands/RuntimeCommandService.swift"),
            encoding: .utf8
        )
        for token in [
            "lsof",
            "foreign_nginx",
            "expected_nginx_pid",
            "kill -TERM",
        ] {
            XCTAssertFalse(
                macCommandFactoryText.contains(token),
                "Mac control command factory must delegate proxy repair to launcher usecases, not own listener policy: \(token)"
            )
        }
        XCTAssertTrue(
            macCommandFactoryText.contains("RuntimeControlClientConstants.RuntimeCommand.repairProxy"),
            "Mac control command factory should delegate proxy repair through the launcher repair-proxy command"
        )
    }

    func testMacControlProxyRepairDoesNotRequireUnusedProxyPortInput() throws {
        let root = packageRoot()
        let clientContractsText = try String(
            contentsOf: root.appendingPathComponent("Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift"),
            encoding: .utf8
        )
        let apiRequestsText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPIRequests.swift"),
            encoding: .utf8
        )
        let commandRoutesText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPCommandRoutes.swift"),
            encoding: .utf8
        )
        let viewModelText = try String(
            contentsOf: root.appendingPathComponent("Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(clientContractsText.contains("func repairProxy() async throws -> RuntimeCommandResult"))
        XCTAssertFalse(clientContractsText.contains("repairProxy(proxyPort:"))
        XCTAssertFalse(apiRequestsText.contains("RuntimeRepairProxyRequest"))
        XCTAssertFalse(commandRoutesText.contains("decodedBody(RuntimeRepairProxyRequest.self)"))
        XCTAssertFalse(viewModelText.contains("controlClient.repairProxy(proxyPort:"))
    }

    func testRuntimeBackupStoreProcessExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBackupStoreComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "BackupStore concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeBackupStoreComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "BackupStore Host process-boundary composition must exist"
        )

        let hostSupportText = try processBoundarySupportText()
        for token in [
            "runRequired",
            "Constants.Commands.chmod",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "BackupStore process execution must stay at the Host process boundary: \(token)"
            )
        }
    }

    func testRuntimeCloudInitSeedProcessExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeCloudInitSeedComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Cloud-init seed concrete composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeCloudInitSeedComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Cloud-init seed Host process-boundary composition must exist"
        )

        let hostSupportText = try processBoundarySupportText()
        for token in [
            "runRequired",
            "hdiutil",
            "Constants.Commands.hdiutil",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "Cloud-init seed image process execution must stay at the Host process boundary: \(token)"
            )
        }
    }

    func testRuntimeFreshInstallPreflightProcessObservationDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeFreshInstallPreflightComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Fresh install preflight concrete observation composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeFreshInstallPreflightComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Fresh install preflight Host process-boundary composition must exist"
        )
    }

    func testFreshInstallSettingsReaderDoesNotApplyDocumentedDefaultsAtAdapterBoundary() throws {
        let readerFile = packageRoot()
            .appendingPathComponent("Sources/Adapters/Outbound/FileSystem/RuntimeFreshInstallStateReaders.swift")
        let text = try String(contentsOf: readerFile, encoding: .utf8)

        XCTAssertFalse(
            text.contains("defaultProxyPort"),
            "Outbound settings reader must report explicit read state; documented defaults belong in the use case input preset step"
        )
        XCTAssertFalse(
            text.contains(".defaulted("),
            "Outbound settings reader must not convert missing settings into a defaulted success state"
        )
        XCTAssertTrue(
            text.contains("return .missing(path: path)")
                && text.contains("return .proxyPortMissing(path: path)"),
            "Outbound settings reader must preserve missing file and missing proxyPort as distinct states"
        )
    }

    func testRuntimeConfigFlagReaderDoesNotCollapseReadFailureToBoolFallback() throws {
        let root = packageRoot()
        let readerText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Adapters/Inbound/CLI/Parsing/RuntimeConfigFlagReader.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            readerText.contains("case failed(name: String, reason: String)"),
            "Runtime config flag reader must preserve read failure as an explicit result"
        )
        XCTAssertFalse(
            readerText.contains("defaultOnFailure"),
            "Runtime config flag reader must not convert read failure into a bool fallback"
        )
        XCTAssertFalse(
            readerText.contains("public func automaticRecoveryEnabled() -> Bool")
                || readerText.contains("public func preventSystemSleepEnabled() -> Bool"),
            "Runtime config flag reader should expose explicit flag read results, not failure-collapsing bool convenience APIs"
        )

        let watchdogText = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            watchdogText.contains("public let automaticRecoveryEnabled: () throws -> Bool"),
            "Watchdog workflow must let config read failure propagate instead of treating it as disabled recovery"
        )
    }

    func testRuntimeVersionStoreFileIOCompositionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeVersionStoreComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime version file IO composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeVersionStoreComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime version store Host process-boundary composition must exist"
        )
    }

    func testVMRuntimeConfigFileIOCompositionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/VMRuntimeConfigComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "VM runtime config file IO and JSON composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/VMRuntimeConfigComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "VM runtime config Host process-boundary composition must exist"
        )
    }

    func testRuntimeRedisBackupExecutionBelongsInWorkflow() throws {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Workflow/RuntimeRepairLifecycle/RuntimeRedisBackupWorkflow.swift"
                ).path
            ),
            "Redis backup request/wait/status orchestration belongs in Workflow"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Bootstrap/Composition/RuntimeRedisBackupComposition.swift"
                ).path
            ),
            "Redis backup concrete execution must not live in Bootstrap composition"
        )

        let forbiddenFiles = [
            "Sources/Application/UseCases/RepairRuntime/RuntimeRedisBackupWorkflow.swift",
            "Sources/Errors/Definitions/RuntimeRedisBackupWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own redis backup execution or workflow-specific errors"
            )
        }
    }

    func testRuntimeVMDiskRepairExecutionBelongsInWorkflow() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift"
                ).path
            ),
            "VM disk repair sequence/status/restart orchestration belongs in Workflow"
        )

        let forbiddenFiles = [
            "Sources/Application/UseCases/RepairRuntime/RunVMDiskRepairUseCase.swift",
            "Sources/Errors/Definitions/RuntimeVMDiskRepairWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own VM disk repair execution or workflow-specific errors"
            )
        }
    }

    func testRuntimeVMDiskRepairWorkflowConsumesExplicitBestEffortResult() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeRepairLifecycle/RuntimeVMDiskRepairWorkflow.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("RuntimeBestEffortOperationResult"))
        for token in [
            "describeError",
            "RuntimeErrorDescription.describe",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "VM disk repair Workflow must consume explicit best-effort failure results, not format thrown errors: \(token)"
            )
        }
    }

    func testRuntimeVMDiskRepairExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeVMDiskRepairComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "VM disk repair concrete execution belongs at the Host process boundary, not Bootstrap"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeVMDiskRepairComposition.swift")
                    .path
            ),
            "VM disk repair Host process-boundary composition must exist"
        )
    }

    func testRuntimeUninstallKeepsStatefulWorkflowOnly() {
        let root = packageRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift").path
            ),
            "Uninstall state/progress orchestration belongs in Workflow"
        )

        let forbiddenFiles = [
            "Sources/Errors/Definitions/RuntimeUninstallWorkflowError.swift",
        ]

        for path in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must not own runtime uninstall Workflow-specific errors"
            )
        }
    }

    func testRuntimeUninstallExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeUninstallComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Runtime uninstall composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeUninstallComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Runtime uninstall Host process-boundary composition must exist"
        )

        let workflowFile = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeUninstallLifecycle/RuntimeUninstallWorkflow.swift")
        let workflowText = try String(
            contentsOf: workflowFile,
            encoding: .utf8
        )
        for token in [
            "UninstallRuntimeUseCase()",
            "executeFileRemoval",
            "executeReceiptForgetting",
            "RuntimeUninstallFileRemovalExecutionError",
            "RuntimeUninstallReceiptForgetExecutionError",
            "RuntimeUninstallPreservedPaths",
            "preserveUserData",
            "restorePreservedPaths",
            "restorePreservedDataAfterFailureIfNeeded",
            "safeRemove",
            "receiptForgetDecision",
        ] {
            XCTAssertTrue(
                workflowText.contains(token),
                "Runtime uninstall execution responsibility must remain explicit in Workflow: \(token)"
            )
        }

        let hostSupportText = try processBoundarySupportText()
        for token in [
            "runProcess",
            "RuntimePackageReceiptStateReader",
            "Constants.Commands.lsof",
            "Constants.Commands.pkgutil",
        ] {
            XCTAssertTrue(
                hostSupportText.contains(token),
                "Runtime uninstall process observation/execution must stay at Host process boundary: \(token)"
            )
        }
    }

    func testHostProxyPortCleanupConsumesExplicitListenerScanResult() throws {
        let root = packageRoot()
        let useCaseFile = root
            .appendingPathComponent("Sources/Application/UseCases/RuntimeServices/CleanRuntimeHostProxyPortUseCase.swift")
        let useCaseText = try String(contentsOf: useCaseFile, encoding: .utf8)

        XCTAssertTrue(
            useCaseText.contains("portListenerScan: (Int) -> RuntimeHostProxyListenerScanResult"),
            "Host proxy port cleanup must consume explicit scan results instead of raw listener arrays"
        )
        XCTAssertFalse(
            useCaseText.contains("portListeners: (Int) throws -> [RuntimeHostProxyListener]"),
            "Host proxy port cleanup must not collapse scan failure and clear state into a throwing listener array"
        )
        for token in [
            "case .clear:",
            "case .commandFailed",
            "case .malformedOutput",
            "case .inspectionFailed",
        ] {
            XCTAssertTrue(
                useCaseText.contains(token),
                "Host proxy port cleanup must handle explicit listener scan state: \(token)"
            )
        }

        let scannerFile = root
            .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyPortListenerScanner.swift")
        let scanReaderFile = root
            .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyListenerScanReader.swift")
        let scanMapperFile = root
            .appendingPathComponent("Sources/Adapters/Outbound/Process/RuntimeHostProxyListenerScanResultMapper.swift")
        let scannerText = try String(contentsOf: scannerFile, encoding: .utf8)
        let scanReaderText = try String(contentsOf: scanReaderFile, encoding: .utf8)
        let scanMapperText = try String(contentsOf: scanMapperFile, encoding: .utf8)
        XCTAssertFalse(
            scannerText.contains("return []"),
            "Outbound listener scanner must not express clear state as an empty listener fallback"
        )
        XCTAssertTrue(scannerText.contains("RuntimeHostProxyListenerScanResultMapper.scanResult"))
        XCTAssertTrue(scanReaderText.contains("RuntimeHostProxyListenerScanResultMapper.scanResult"))
        XCTAssertFalse(scannerText.contains("RuntimeLsofListenerParser.parse"))
        XCTAssertFalse(scanReaderText.contains("RuntimeLsofListenerParser.parse"))
        XCTAssertTrue(scanMapperText.contains("RuntimeLsofListenerParser.parse"))
        XCTAssertTrue(
            scanMapperText.contains("return .clear"),
            "Outbound listener scanner should preserve clear as an explicit scan result"
        )
        XCTAssertTrue(
            scanMapperText.contains("return .commandFailed"),
            "Outbound listener scanner should preserve command failures as explicit scan results"
        )
    }

    func testRuntimeWatchdogKeepsRunnerButNotManagedOperationGuardInWorkflow() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift")
                    .path
            ),
            "Watchdog runner orchestration belongs in Workflow"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeManagedOperationGuard.swift")
                    .path
            ),
            "Managed operation guard decision must stay in Application/Bootstrap, not Workflow"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeManagedOperationGuardComposition.swift")
                    .path
            ),
            "Managed operation guard Host composition must not live in Bootstrap"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeManagedOperationGuardComposition.swift")
                    .path
            ),
            "Managed operation guard Host process-boundary composition must exist"
        )
    }

    func testRuntimeWatchdogDecisionExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeWatchdogRunnerComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Watchdog concrete runner composition belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeWatchdogRunnerComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Watchdog Host process-boundary composition must exist"
        )
    }

    func testRuntimeWatchdogWorkflowConsumesExplicitBestEffortResultsForLogPreparation() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("RuntimeBestEffortOperationResult"))
        for token in [
            "describeError",
            "RuntimeErrorDescription.describe",
            "try operations.createLogsDirectory",
            "try operations.rotateRuntimeLogs",
            "try operations.collectGuestLogs",
        ] {
            XCTAssertFalse(
                text.contains(token),
                "Watchdog Workflow must consume explicit log-preparation results, not format thrown errors: \(token)"
            )
        }
    }

    func testRuntimeApplyBundleExecutionDoesNotRemainInBootstrap() throws {
        let bootstrapFile = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: bootstrapFile.path),
            "Apply bundle concrete execution belongs at the Host process boundary, not Bootstrap"
        )

        let hostFile = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeBundleComposition.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: hostFile.path),
            "Apply bundle Host process-boundary composition must exist"
        )
    }

    func testRuntimeBundleVerificationIODoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Bundle verification file IO must not live in Bootstrap composition"
        )
    }

    func testRuntimeApplyBundlePreflightJudgementDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeBundleComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Apply bundle preflight judgement must not live in Bootstrap composition"
        )
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretRollbackBackupSelectionDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let forbiddenTokens = [
            "backupURL(for:",
            "case .latestBackup",
            "case .specificBackup",
        ]

        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "RuntimeUpdateLifecycle Workflow must pass rollback backup selections to a port instead of interpreting \(token) directly: \(file.path)"
                )
            }
        }
    }

    func testRuntimeGuestUpdateWaitExecutionBelongsInWorkflow() throws {
        let requiredFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationWorkflow.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownWorkflow.swift",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestActivationComposition.swift",
            "Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestShutdownComposition.swift",
        ]

        for relativePath in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Guest update activation/shutdown wait execution belongs in Workflow: \(relativePath)"
            )
        }

        let forbiddenFiles = [
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCases.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestActivationRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestShutdownRunner.swift",
            "Sources/Errors/Definitions/RuntimeGuestActivationWorkflowError.swift",
            "Sources/Errors/Definitions/RuntimeGuestShutdownWorkflowError.swift",
            "Sources/Bootstrap/Composition/RuntimeGuestActivationComposition.swift",
            "Sources/Bootstrap/Composition/RuntimeGuestShutdownComposition.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Guest update activation/shutdown workflow must not use obsolete placement or workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeUpdatePlanningStaysSplitByOperationResponsibility() throws {
        let root = packageRoot()
        let requiredFiles = [
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundleUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundlePreflightUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/PrepareRuntimeBundleUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RequireRuntimeGuestCapabilityUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RollbackRuntimeUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestActivationUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestShutdownUseCase.swift",
            "Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateSharedPlans.swift",
            "Sources/Application/UseCases/UpdateRuntime/UpdateRuntimeSharedPlans.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "Runtime update planning must stay operation-specific: \(path)"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Application/UseCases/UpdateRuntime/UpdateRuntimeUseCase.swift").path
            ),
            "UpdateRuntimeUseCase must not return as a mixed apply/rollback/guest planning bucket"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Application/UseCases/UpdateRuntime/RuntimeGuestUpdateUseCase.swift").path
            ),
            "RuntimeGuestUpdateUseCase must not return as a mixed activation/shutdown planning bucket"
        )

        let applyFile = root.appendingPathComponent(
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundleUseCase.swift"
        )
        let preflightFile = root.appendingPathComponent(
            "Sources/Application/UseCases/UpdateRuntime/ApplyRuntimeBundlePreflightUseCase.swift"
        )
        let applyText = try String(contentsOf: applyFile, encoding: .utf8)
        let preflightText = try String(contentsOf: preflightFile, encoding: .utf8)
        let preflightJudgementTokens = [
            "preflightManifestPlan(",
            "preflightCapabilityPlan(",
            "storageRequirement(",
            "storagePreflightStagedBundleLogMessage(",
            "replacingRootfsStoragePreflightPlan(",
            "unchangedRootfsStoragePreflightPlan(",
            "rootfsStorageObservationPlan(",
            "rootfsStorageDecision(",
            "missingFileFailureMessage(",
            "backupCreatedLogMessage(",
            "diskHealthDecision(",
        ]

        for token in preflightJudgementTokens {
            XCTAssertFalse(
                applyText.contains(token),
                "ApplyRuntimeBundleUseCase must not reabsorb apply preflight judgement: \(token)"
            )
            XCTAssertTrue(
                preflightText.contains(token),
                "ApplyRuntimeBundlePreflightUseCase must own apply preflight judgement: \(token)"
            )
        }

        let scannedRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Tests"),
        ]
        let files = try scannedRoots.flatMap { try sourceLikeFiles(root: $0) }
            .filter { !$0.path.contains("/Tests/ArchitectureBoundaryTests/") }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                text.contains("UpdateRuntimeUseCase("),
                "Callers must depend on operation-specific update usecases instead of UpdateRuntimeUseCase: \(file.path)"
            )
            XCTAssertFalse(
                text.contains("RuntimeGuestUpdateUseCase("),
                "Callers must depend on activation/shutdown-specific guest update usecases instead of RuntimeGuestUpdateUseCase: \(file.path)"
            )
        }
    }

    func testRuntimeUpdateWorkflowDoesNotInterpretPreflightFileObservationsDirectly() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let forbiddenTokens = [
            "missingFileFailureMessage",
            "replacingRootfsStoragePreflightPlan",
            "unchangedRootfsStoragePreflightPlan",
            "guard fileExists",
            "guard directoryExists",
            "!fileExists",
            "!directoryExists",
            "RuntimeFileNames.updateBundleManifest",
            "shouldReplace",
            "guard let stagedRootfs",
            "stagedRootfs == nil",
            "stagedRootfs != nil",
            "preparesGuestShutdown",
            "String(describing:",
            "requiresRuntimeDiskHealthCheck",
            "requiredGuestCapabilities",
        ]

        for file in try swiftFiles(root: updateWorkflowRoot) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    text.contains(token),
                    "RuntimeUpdateLifecycle Workflow must pass explicit file observations to UseCase/Adapters instead of interpreting \(token) directly: \(file.path)"
                )
            }
        }
    }

    func testRuntimeUpdateLifecycleWorkflowDirectoryHasOnlyWorkflowRunners() throws {
        let updateWorkflowRoot = packageRoot().appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle")
        let fileNames = Set(try swiftFiles(root: updateWorkflowRoot).map(\.lastPathComponent))

        XCTAssertEqual(
            fileNames,
            [
                "RuntimeApplyBundleWorkflow.swift",
                "RuntimeGuestActivationWorkflow.swift",
                "RuntimeGuestShutdownWorkflow.swift",
                "RuntimeRollbackWorkflow.swift",
            ],
            "RuntimeUpdateLifecycle Workflow must keep only stateful runners: \(fileNames.sorted())"
        )
    }

    func testRuntimeBundlePreparationWorkflowDoesNotExist() throws {
        let file = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeBundlePreparationWorkflow.swift"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Bundle preparation execution belongs in Application usecase, not Workflow"
        )
    }

    func testRuntimeGuestCapabilityCheckerDoesNotRemainInWorkflow() throws {
        let workflowFile = packageRoot().appendingPathComponent(
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeGuestCapabilityChecker.swift"
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workflowFile.path),
            "Guest capability requirement execution belongs in Application usecase, not Workflow"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeGuestCapabilityCheckerComposition.swift")
                    .path
            ),
            "Guest capability Host composition must not live in Bootstrap"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeGuestCapabilityCheckerComposition.swift")
                    .path
            ),
            "Guest capability Host process-boundary composition must exist"
        )
    }

    func testRuntimeRollbackKeepsStatefulWorkflowOnly() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackWorkflow.swift")
                    .path
            ),
            "Rollback progress/status orchestration belongs in Workflow"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageRoot()
                    .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/RuntimeRollbackComposition.swift")
                    .path
            ),
            "Rollback Host process-boundary composition must exist"
        )

        let forbiddenFiles = [
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackPreflightRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackRunner.swift",
            "Sources/Workflow/RuntimeUpdateLifecycle/RuntimeRollbackStepExecutor.swift",
            "Sources/Errors/Definitions/RuntimeRollbackWorkflowError.swift",
        ]

        for relativePath in forbiddenFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: packageRoot().appendingPathComponent(relativePath).path),
                "Rollback Workflow must not own preflight runners, step executors, or Workflow-specific errors: \(relativePath)"
            )
        }
    }

    func testRuntimeRollbackStepExecutionDoesNotRemainInBootstrap() throws {
        let file = packageRoot()
            .appendingPathComponent("Sources/Bootstrap/Composition/RuntimeRollbackComposition.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Rollback concrete execution belongs at the Host process boundary, not Bootstrap"
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func childDirectoryNames(of url: URL) throws -> Set<String> {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return Set(try urls.compactMap { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? child.lastPathComponent : nil
        })
    }

    private func assertDirectoryExists(_ url: URL, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && isDirectory.boolValue, message, file: file, line: line)
    }

    private func assertFileExists(_ url: URL, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && !isDirectory.boolValue, message, file: file, line: line)
    }

    private func swiftPackageFiles(root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
        return try enumerator?.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        } ?? []
    }

    private func sourceLikeFiles(root: URL) throws -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return []
        }
        let files: [URL]
        if isDirectory.boolValue {
            files = try swiftPackageFiles(root: root)
        } else {
            files = [root]
        }
        return files.filter { file in
            [
                "swift",
                "md",
                "py",
                "sh",
                "template",
            ].contains(file.pathExtension) || file.lastPathComponent.contains(".template")
        }
    }

    private func swiftFiles(root: URL) throws -> [URL] {
        try swiftPackageFiles(root: root).filter { $0.pathExtension == "swift" }
    }

    private func processBoundarySupportText() throws -> String {
        let supportRoot = packageRoot()
            .appendingPathComponent("Sources/Hosts/CLI/ProcessBoundary/Support")
        return try swiftFiles(root: supportRoot)
            .sorted { $0.path < $1.path }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func emptyDirectories(root: URL) throws -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try enumerator?.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return children.isEmpty ? url : nil
        } ?? []
    }

    private func importedModules(in file: URL) throws -> Set<String> {
        let text = try String(contentsOf: file, encoding: .utf8)
        return Set(text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("@testable import ") else {
                return nil
            }
            return String(trimmed.split(separator: " ").last ?? "")
        })
    }

    private func targetDependencies(_ target: String, in manifest: String) throws -> Set<String> {
        guard let nameRange = manifest.range(of: #"name: "\#(target)""#) else {
            XCTFail("Package.swift must define target \(target)")
            return []
        }
        guard let dependenciesLabel = manifest[nameRange.upperBound...].range(of: "dependencies:") else {
            XCTFail("Package.swift target \(target) must declare dependencies explicitly")
            return []
        }
        guard let dependenciesStart = manifest[dependenciesLabel.upperBound...].firstIndex(of: "[") else {
            XCTFail("Package.swift target \(target) dependencies must be an array")
            return []
        }

        var depth = 0
        var index = dependenciesStart
        while index < manifest.endIndex {
            let character = manifest[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    let block = String(manifest[dependenciesStart...index])
                    let regex = try NSRegularExpression(pattern: #""([^"]+)""#)
                    let range = NSRange(block.startIndex..<block.endIndex, in: block)
                    return Set(regex.matches(in: block, range: range).compactMap { match in
                        guard let captureRange = Range(match.range(at: 1), in: block) else {
                            return nil
                        }
                        return String(block[captureRange])
                    })
                }
            }
            index = manifest.index(after: index)
        }

        XCTFail("Package.swift target \(target) dependencies array must be balanced")
        return []
    }

    private func useCaseStructBody(in text: String, file: URL) throws -> String {
        let pattern = #"public\s+struct\s+\w+UseCase(?:<[^>]+>)?\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text),
              let openBraceIndex = text[matchRange].lastIndex(of: "{") else {
            XCTFail("Usecase file must declare public struct ...UseCase: \(file.path)")
            return ""
        }

        let bodyStart = text.index(after: openBraceIndex)
        var depth = 1
        var index = bodyStart
        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[bodyStart..<index])
                }
            }
            index = text.index(after: index)
        }

        XCTFail("Usecase struct body must be balanced: \(file.path)")
        return ""
    }

    private func topLevelLines(in body: String) -> [String] {
        var depth = 1
        var lines: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if depth == 1 {
                lines.append(String(line))
            }
            for character in line {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                }
            }
        }
        return lines
    }

    private func storedPropertyPatternMatches(_ line: String) -> Bool {
        line.hasPrefix("let ")
            || line.hasPrefix("var ")
            || line.hasPrefix("public let ")
            || line.hasPrefix("public var ")
            || line.hasPrefix("internal let ")
            || line.hasPrefix("internal var ")
            || line.hasPrefix("private let ")
            || line.hasPrefix("private var ")
            || line.hasPrefix("fileprivate let ")
            || line.hasPrefix("fileprivate var ")
    }

    private func containsConcreteProcessInvocation(_ text: String) -> Bool {
        let pattern = #"(^|[^A-Za-z0-9_])Process\s*\("#
        return containsRegex(pattern, in: text)
    }

    private func containsRegex(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
