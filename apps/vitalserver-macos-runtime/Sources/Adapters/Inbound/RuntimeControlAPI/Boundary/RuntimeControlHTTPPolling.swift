import Foundation
import RuntimeControl

@MainActor
func pollSnapshot<T: Encodable & Sendable>(
    id: String,
    event: String,
    interval: UInt64,
    heartbeatInterval: UInt64,
    now: @escaping @Sendable () -> Date,
    continuation: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation,
    load: @escaping @MainActor @Sendable () async throws -> T
) async {
    var previousPayload: Data?
    var lastHeartbeat = now()
    do {
        while !Task.isCancelled {
            let currentTime = now()
            let value = try await load()
            let payload = try await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                return try encoder.encode(value)
            }.value
            if payload != previousPayload {
                previousPayload = payload
                lastHeartbeat = currentTime
                continuation.yield(RuntimeControlServerSentEvent(id: id, event: event, data: payload))
            } else if currentTime.timeIntervalSince(lastHeartbeat) >= Double(heartbeatInterval) / 1_000_000_000 {
                lastHeartbeat = currentTime
                continuation.yield(.heartbeat)
            }
            try await Task.sleep(nanoseconds: interval)
        }
    } catch is CancellationError {
        continuation.finish()
    } catch {
        continuation.finish(throwing: error)
    }
}

@MainActor
func pollEvents(
    lastEventID: String?,
    interval: UInt64,
    heartbeatInterval: UInt64,
    now: @escaping @Sendable () -> Date,
    continuation: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation,
    load: @escaping @MainActor @Sendable () async throws -> RuntimeEventHistory
) async {
    var deliveredIDs = Set<String>()
    var hasAppliedReconnectCursor = lastEventID == nil
    var lastHeartbeat = now()
    do {
        while !Task.isCancelled {
            let currentTime = now()
            let history = try await load()
            if let issueEvent = try RuntimeControlServerSentEvent.eventHistoryReadIssue(history) {
                continuation.yield(issueEvent)
                lastHeartbeat = currentTime
            }
            let currentIDs = Set(history.events.map(\.id))
            deliveredIDs.formIntersection(currentIDs)
            if !hasAppliedReconnectCursor, let lastEventID, !currentIDs.contains(lastEventID) {
                hasAppliedReconnectCursor = true
            }
            for event in history.events {
                if !hasAppliedReconnectCursor {
                    if event.id == lastEventID {
                        hasAppliedReconnectCursor = true
                    }
                    continue
                }
                guard !deliveredIDs.contains(event.id) else {
                    continue
                }
                deliveredIDs.insert(event.id)
                lastHeartbeat = currentTime
                continuation.yield(try .event(event))
            }
            if currentTime.timeIntervalSince(lastHeartbeat) >= Double(heartbeatInterval) / 1_000_000_000 {
                lastHeartbeat = currentTime
                continuation.yield(.heartbeat)
            }
            try await Task.sleep(nanoseconds: interval)
        }
    } catch is CancellationError {
        continuation.finish()
    } catch {
        continuation.finish(throwing: error)
    }
}
