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
