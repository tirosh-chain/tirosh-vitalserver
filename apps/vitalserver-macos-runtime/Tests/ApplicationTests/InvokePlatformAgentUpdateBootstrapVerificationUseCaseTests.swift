import Application
import Contracts
import Domain
import Foundation
import XCTest

final class InvokePlatformAgentUpdateBootstrapVerificationUseCaseTests:
    XCTestCase
{
    func testPersistsInvokedBeforeSpawnAndSucceededAfterMatchingBinding()
        async throws
    {
        var persisted: [String] = []
        let outcome = try await
            InvokePlatformAgentUpdateBootstrapVerificationUseCase().invoke(
                verificationInvocationId: invocationId,
                bundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z",
                persist: { evidence in
                    persisted.append(evidence.state)
                },
                spawn: { id in
                    XCTAssertEqual(id, self.invocationId)
                    XCTAssertEqual(persisted, ["invoked"])
                    return .completed(exitCode: 0)
                },
                bindingRead: { _ in .loaded(self.binding()) }
            )

        XCTAssertEqual(
            outcome,
            .succeeded(
                updateId: "update-42",
                canonicalPayloadSHA256: digest
            )
        )
        XCTAssertEqual(persisted, ["invoked", "succeeded"])
    }

    func testDoesNotSpawnWhenInvokedEvidenceCannotPersist() async {
        var spawned = false
        do {
            _ = try await
                InvokePlatformAgentUpdateBootstrapVerificationUseCase().invoke(
                    verificationInvocationId: invocationId,
                    bundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    persist: { _ in
                        throw NSError(
                            domain: "test",
                            code: 1
                        )
                    },
                    spawn: { _ in
                        spawned = true
                        return .completed(exitCode: 0)
                    },
                    bindingRead: { _ in
                        .missing(path: "/tmp/binding.json")
                    }
                )
            XCTFail("expected persist failure")
        } catch let error as
            InvokePlatformAgentUpdateBootstrapVerificationError
        {
            guard case .evidencePersistFailed = error else {
                return XCTFail("expected persist failure, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertFalse(spawned)
    }

    func testPublicCLIIdentityIsNotInventedWhenInvocationIdIsInvalid()
        async
    {
        var persisted = false
        do {
            _ = try await
                InvokePlatformAgentUpdateBootstrapVerificationUseCase().invoke(
                    verificationInvocationId: "",
                    bundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    persist: { _ in persisted = true },
                    spawn: { _ in .completed(exitCode: 0) },
                    bindingRead: { _ in
                        .missing(path: "/tmp/binding.json")
                    }
                )
            XCTFail("expected invalid invocation id")
        } catch {
            XCTAssertEqual(
                error as?
                    InvokePlatformAgentUpdateBootstrapVerificationError,
                .invalidVerificationInvocationId("")
            )
        }
        XCTAssertFalse(persisted)
    }

    func testPersistsTypedBindingMissingWithoutPrefixingAReceiptMismatch()
        async throws
    {
        var persisted: [String] = []
        let outcome = try await
            InvokePlatformAgentUpdateBootstrapVerificationUseCase().invoke(
                verificationInvocationId: invocationId,
                bundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z",
                persist: { evidence in
                    persisted.append(evidence.state)
                },
                spawn: { _ in .completed(exitCode: 0) },
                bindingRead: { _ in
                    .missing(path: "/tmp/binding.json")
                }
            )

        XCTAssertEqual(
            outcome,
            .bindingMissing(path: "/tmp/binding.json")
        )
        XCTAssertEqual(
            persisted,
            [
                PlatformAgentUpdateBootstrapVerificationContract.stateInvoked,
                PlatformAgentUpdateBootstrapVerificationContract
                    .stateBindingMissing,
            ]
        )
    }

    private func binding() -> UpdateBootstrapVerificationInvocationBinding {
        UpdateBootstrapVerificationInvocationBinding(
            schemaVersion:
                UpdateBootstrapVerificationInvocationBindingContract
                .schemaVersion,
            command: UpdateBootstrapVerificationInvocationBindingContract
                .command,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest
        )
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }
}
