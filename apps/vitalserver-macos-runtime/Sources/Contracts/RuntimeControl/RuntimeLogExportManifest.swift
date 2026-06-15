import Foundation

public struct RuntimeLogExportManifest: Codable, Equatable {
    public struct SupplementalItem: Codable, Equatable {
        public let source: String
        public let relativeDestination: String
        public let sourcePathState: String
        public let sourcePresent: Bool
        public let included: Bool
        public let status: String
        public let error: String?

        public init(
            source: String,
            relativeDestination: String,
            sourcePathState: String,
            sourcePresent: Bool,
            included: Bool,
            status: String,
            error: String?
        ) {
            self.source = source
            self.relativeDestination = relativeDestination
            self.sourcePathState = sourcePathState
            self.sourcePresent = sourcePresent
            self.included = included
            self.status = status
            self.error = error
        }

        public static func statusValue(sourcePresent: Bool, included: Bool, error: String?) -> String {
            if included {
                return "included"
            }
            if error != nil {
                return "failed"
            }
            if sourcePresent {
                return "not-included"
            }
            return "missing"
        }
    }

    public struct RotatedSupplementalSet: Codable, Equatable {
        public let sourceDirectory: String
        public let sourceFilePrefix: String
        public let relativeDestinationDirectory: String
        public let destinationFilePrefix: String
        public let sourcePathState: String
        public let copiedCount: Int
        public let status: String
        public let error: String?

        public init(
            sourceDirectory: String,
            sourceFilePrefix: String,
            relativeDestinationDirectory: String,
            destinationFilePrefix: String,
            sourcePathState: String,
            copiedCount: Int,
            status: String,
            error: String?
        ) {
            self.sourceDirectory = sourceDirectory
            self.sourceFilePrefix = sourceFilePrefix
            self.relativeDestinationDirectory = relativeDestinationDirectory
            self.destinationFilePrefix = destinationFilePrefix
            self.sourcePathState = sourcePathState
            self.copiedCount = copiedCount
            self.status = status
            self.error = error
        }

        public static func statusValue(sourcePresent: Bool, copiedCount: Int, error: String?) -> String {
            if error != nil {
                return "failed"
            }
            if !sourcePresent {
                return "missing"
            }
            if copiedCount > 0 {
                return "included"
            }
            return "no-matching-files"
        }
    }

    public let generatedAt: String
    public let productLogsDirectory: String
    public let collectionIssue: String?
    public let supplementalItems: [SupplementalItem]
    public let rotatedSupplementalSets: [RotatedSupplementalSet]

    public init(
        generatedAt: String,
        productLogsDirectory: String,
        collectionIssue: String?,
        supplementalItems: [SupplementalItem],
        rotatedSupplementalSets: [RotatedSupplementalSet]
    ) {
        self.generatedAt = generatedAt
        self.productLogsDirectory = productLogsDirectory
        self.collectionIssue = collectionIssue
        self.supplementalItems = supplementalItems
        self.rotatedSupplementalSets = rotatedSupplementalSets
    }
}
