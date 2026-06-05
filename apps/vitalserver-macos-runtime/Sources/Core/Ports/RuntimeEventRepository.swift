import Contracts

public protocol RuntimeEventRecording {
    func append(_ event: RuntimeEventDocument) throws
}

public protocol RuntimeEventHistoryReading {
    func query(_ query: RuntimeEventQuery) -> RuntimeEventPage
}

public protocol RuntimeEventRepository: RuntimeEventRecording, RuntimeEventHistoryReading {}
