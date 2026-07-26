import Contracts
import Foundation

public enum RuntimePackageInstallDisposition: Equatable, Sendable {
    case fresh
    case blocked([String])
}

public enum RuntimeInstalledPackageVersion: Equatable, Sendable {
    case absent
    case present(RuntimePackageVersion)
}

public enum RuntimePackageInstallIntentPolicy {
    public static func classify(
        installed: RuntimeInstalledPackageVersion,
        targetVersion: RuntimePackageVersion
    ) -> RuntimePackageInstallIntent {
        switch installed {
        case .absent:
            return .fresh
        case .present(let installedVersion):
            switch compare(installedVersion, targetVersion) {
            case .orderedAscending:
                return .upgrade
            case .orderedSame:
                return .sameVersionRepair
            case .orderedDescending:
                return .downgrade
            }
        }
    }

    private static func compare(
        _ installedVersion: RuntimePackageVersion,
        _ targetVersion: RuntimePackageVersion
    ) -> ComparisonResult {
        let installedComponents = installedVersion.rawValue.split(separator: ".").map(String.init)
        let targetComponents = targetVersion.rawValue.split(separator: ".").map(String.init)
        let count = max(installedComponents.count, targetComponents.count)

        for index in 0..<count {
            let installed = index < installedComponents.count ? installedComponents[index] : "0"
            let target = index < targetComponents.count ? targetComponents[index] : "0"
            let result = compareNumericComponent(installed, target)
            if result != .orderedSame {
                return result
            }
        }
        return .orderedSame
    }

    private static func compareNumericComponent(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let normalizedLeft = normalizedNumericComponent(lhs)
        let normalizedRight = normalizedNumericComponent(rhs)
        if normalizedLeft.count < normalizedRight.count {
            return .orderedAscending
        }
        if normalizedLeft.count > normalizedRight.count {
            return .orderedDescending
        }
        if normalizedLeft < normalizedRight {
            return .orderedAscending
        }
        if normalizedLeft > normalizedRight {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func normalizedNumericComponent(_ value: String) -> String {
        let normalized = value.drop(while: { $0 == "0" })
        return normalized.isEmpty ? "0" : String(normalized)
    }
}

public enum RuntimePackageInstallPreflightPolicy {
    public static func disposition(
        document: RuntimeFreshInstallPreflightDocument,
        targetVersion: RuntimePackageVersion
    ) -> RuntimePackageInstallDisposition {
        var receiptFailures: [String] = []
        var existingReceipts: [(identifier: String, version: RuntimePackageVersion)] = []

        guard !document.packageReceiptStates.isEmpty else {
            return .blocked(["package-receipt-state-missing"])
        }

        for state in document.packageReceiptStates {
            switch state {
            case .present(let identifier, let version):
                existingReceipts.append((identifier, version))
            case .absent:
                continue
            case .readFailed(let identifier, let reason):
                receiptFailures.append("package-receipt-read-failed:identifier=\(identifier) reason=\(reason)")
            case .forgetFailed(let identifier, let reason):
                receiptFailures.append("package-receipt-state-invalid:identifier=\(identifier) reason=\(reason)")
            case .unknown(let value):
                receiptFailures.append("package-receipt-state-unknown:value=\(value)")
            }
        }

        if !receiptFailures.isEmpty {
            return .blocked(receiptFailures)
        }
        if !existingReceipts.isEmpty {
            let blockers = existingReceipts.map { receipt in
                let intent = RuntimePackageInstallIntentPolicy.classify(
                    installed: .present(receipt.version),
                    targetVersion: targetVersion
                )
                return [
                    "package-install-intent-unsupported:intent=\(intent.rawValue)",
                    "identifier=\(receipt.identifier)",
                    "installedVersion=\(receipt.version.rawValue)",
                    "targetVersion=\(targetVersion.rawValue)",
                ].joined(separator: " ")
            }
            return .blocked(blockers)
        }
        return document.passed ? .fresh : .blocked(document.blockers)
    }
}
