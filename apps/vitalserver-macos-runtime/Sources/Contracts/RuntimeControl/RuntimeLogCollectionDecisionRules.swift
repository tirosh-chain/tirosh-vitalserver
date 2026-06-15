import Foundation

public struct RuntimeLogCollectionRefreshTargetInput: Equatable, Sendable {
    public let sourceID: RuntimeLogSource
    public let destinationFileName: String

    public init(sourceID: RuntimeLogSource, destinationFileName: String) {
        self.sourceID = sourceID
        self.destinationFileName = destinationFileName
    }
}

public struct RuntimeLogCollectionCopyRefreshInput: Equatable, Sendable {
    public let destinationPresent: Bool
    public let rotationRequired: Bool
    public let sourceSize: UInt64
    public let destinationSize: UInt64
    public let sourceModificationDate: Date
    public let destinationModificationDate: Date

    public init(
        destinationPresent: Bool,
        rotationRequired: Bool,
        sourceSize: UInt64,
        destinationSize: UInt64,
        sourceModificationDate: Date,
        destinationModificationDate: Date
    ) {
        self.destinationPresent = destinationPresent
        self.rotationRequired = rotationRequired
        self.sourceSize = sourceSize
        self.destinationSize = destinationSize
        self.sourceModificationDate = sourceModificationDate
        self.destinationModificationDate = destinationModificationDate
    }
}

public struct RuntimeLogCollectionRotationInput: Equatable, Sendable {
    public let destinationPresent: Bool
    public let fileSize: UInt64
    public let modificationDate: Date
    public let now: Date
    public let maxCentralLogBytes: UInt64

    public init(
        destinationPresent: Bool,
        fileSize: UInt64,
        modificationDate: Date,
        now: Date,
        maxCentralLogBytes: UInt64
    ) {
        self.destinationPresent = destinationPresent
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.now = now
        self.maxCentralLogBytes = maxCentralLogBytes
    }
}

public struct RuntimeLogCollectionAppendInput: Equatable, Sendable {
    public let destinationPresent: Bool
    public let sourceSize: UInt64
    public let destinationSize: UInt64
    public let sourceMatchesDestinationTail: Bool

    public init(
        destinationPresent: Bool,
        sourceSize: UInt64,
        destinationSize: UInt64,
        sourceMatchesDestinationTail: Bool
    ) {
        self.destinationPresent = destinationPresent
        self.sourceSize = sourceSize
        self.destinationSize = destinationSize
        self.sourceMatchesDestinationTail = sourceMatchesDestinationTail
    }
}

public struct RuntimeLogCollectionDecisionRules: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func shouldRefreshTarget(_ input: RuntimeLogCollectionRefreshTargetInput) -> Bool {
        guard let contract = RuntimeLogCollectionSourceContract.fileCopy(for: input.sourceID) else {
            return false
        }
        return input.destinationFileName == contract.destinationFileName
    }

    public func shouldRefreshCopy(_ input: RuntimeLogCollectionCopyRefreshInput) -> Bool {
        if !input.destinationPresent || input.rotationRequired {
            return true
        }
        if input.sourceSize != input.destinationSize {
            return true
        }
        return input.sourceModificationDate > input.destinationModificationDate
    }

    public func shouldRotateCentralLog(_ input: RuntimeLogCollectionRotationInput) -> Bool {
        guard input.destinationPresent else {
            return false
        }
        if input.fileSize >= input.maxCentralLogBytes {
            return true
        }
        return !calendar.isDate(input.modificationDate, inSameDayAs: input.now)
    }

    public func canAppendCopy(_ input: RuntimeLogCollectionAppendInput) -> Bool {
        input.destinationPresent
            && input.sourceSize > input.destinationSize
            && input.sourceMatchesDestinationTail
    }
}
