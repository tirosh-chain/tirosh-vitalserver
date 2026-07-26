import Contracts
import Domain
import XCTest

final class RuntimePackageInstallPreflightPolicyTests: XCTestCase {
    func testAllowsFreshInstallWhenFreshPreflightPassed() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(
                document: document(),
                targetVersion: version("0.2.1")
            ),
            .fresh
        )
    }

    func testClassifiesFreshSameVersionRepairUpgradeAndDowngrade() {
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .absent,
                targetVersion: version("0.2.1")
            ),
            .fresh
        )
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .present(version("0.2.1")),
                targetVersion: version("0.2.1")
            ),
            .sameVersionRepair
        )
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .present(version("0.2.0")),
                targetVersion: version("0.2.1")
            ),
            .upgrade
        )
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .present(version("0.2.2")),
                targetVersion: version("0.2.1")
            ),
            .downgrade
        )
    }

    func testBlocksSameVersionRepairBeforeOwnedArtifactOrServiceEffects() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(
                document: document(
                    passed: false,
                    blockers: [
                        "install-artifact-present:path=/Applications/VitalServer Helper.app",
                        "launchd-service-loaded:label=ai.tirosh.vitalserver.helper.vm",
                    ],
                    artifactStates: [.present(path: "/Applications/VitalServer Helper.app")],
                    receiptStates: [
                        .present(
                            identifier: "ai.tirosh.vitalserver.helper",
                            version: version("0.2.1")
                        ),
                    ]
                ),
                targetVersion: version("0.2.1")
            ),
            .blocked([
                "package-install-intent-unsupported:intent=same-version-repair identifier=ai.tirosh.vitalserver.helper installedVersion=0.2.1 targetVersion=0.2.1",
            ])
        )
    }

    func testBlocksUpgrade() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(
                document: document(receiptStates: [
                    .present(
                        identifier: "ai.tirosh.vitalserver.helper",
                        version: version("0.2.0")
                    ),
                ]),
                targetVersion: version("0.2.1")
            ),
            .blocked([
                "package-install-intent-unsupported:intent=upgrade identifier=ai.tirosh.vitalserver.helper installedVersion=0.2.0 targetVersion=0.2.1",
            ])
        )
    }

    func testBlocksDowngrade() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(
                document: document(receiptStates: [
                    .present(
                        identifier: "ai.tirosh.vitalserver.helper",
                        version: version("0.2.2")
                    ),
                ]),
                targetVersion: version("0.2.1")
            ),
            .blocked([
                "package-install-intent-unsupported:intent=downgrade identifier=ai.tirosh.vitalserver.helper installedVersion=0.2.2 targetVersion=0.2.1",
            ])
        )
    }

    func testBlocksWhenReceiptStateCannotBeRead() {
        XCTAssertEqual(
            RuntimePackageInstallPreflightPolicy.disposition(
                document: document(
                    passed: false,
                    blockers: [],
                    receiptStates: [.readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "pkgutil failed")]
                ),
                targetVersion: version("0.2.1")
            ),
            .blocked([
                "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper reason=pkgutil failed",
            ])
        )
    }

    func testStrictNumericPackageVersionRejectsMissingAndMalformedValues() {
        XCTAssertNil(RuntimePackageVersion(rawValue: ""))
        XCTAssertNil(RuntimePackageVersion(rawValue: "0.2.1-dev"))
        XCTAssertNil(RuntimePackageVersion(rawValue: "0..2"))
        XCTAssertNil(RuntimePackageVersion(rawValue: " 0.2.1"))
        XCTAssertNotNil(RuntimePackageVersion(rawValue: "0.2.1"))
    }

    func testVersionOrderingNormalizesLeadingAndMissingZeroComponentsWithoutIntegerOverflow() {
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .present(version("01.0.0")),
                targetVersion: version("1")
            ),
            .sameVersionRepair
        )
        XCTAssertEqual(
            RuntimePackageInstallIntentPolicy.classify(
                installed: .present(version("999999999999999999999999.0")),
                targetVersion: version("1000000000000000000000000.0")
            ),
            .upgrade
        )
    }

    private func document(
        passed: Bool = true,
        blockers: [String] = [],
        artifactStates: [RuntimeInstallArtifactState] = [.absent(path: "/Applications/VitalServer Helper.app")],
        receiptStates: [RuntimePackageReceiptState] = [.absent(identifier: "ai.tirosh.vitalserver.helper")]
    ) -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightDocument(
            passed: passed,
            proxyPort: 80,
            blockers: blockers,
            settingsState: .loaded(path: "/private/tmp/install.json", proxyPort: 80),
            artifactStates: artifactStates,
            serviceStates: [],
            packageReceiptStates: receiptStates,
            proxyPortState: .clear(port: 80)
        )
    }

    private func version(_ value: String) -> RuntimePackageVersion {
        guard let version = RuntimePackageVersion(rawValue: value) else {
            fatalError("invalid test version: \(value)")
        }
        return version
    }
}
