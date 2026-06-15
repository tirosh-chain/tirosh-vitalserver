import Foundation
import RuntimeControl

@MainActor
struct RuntimeControlHTTPStreamRoutes {
    let handler: any RuntimeControlAPIReadHandler
    let configuration: RuntimeControlAPIStreamConfiguration
    let now: @Sendable () -> Date

    func streamResponse(
        _ endpoint: RuntimeControlAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPStreamResponse {
        switch endpoint {
        case .overviewStream:
            return makeStream { [handler, configuration] continuation in
                await pollSnapshot(
                    id: "runtime-overview",
                    event: "runtime-overview",
                    interval: configuration.pollIntervalNanoseconds,
                    heartbeatInterval: configuration.heartbeatIntervalNanoseconds,
                    now: now,
                    continuation: continuation
                ) {
                    try await RuntimeControlOverviewAssembler(handler: handler).load()
                }
            }
        case .statusStream:
            return makeStream { [handler, configuration] continuation in
                await pollSnapshot(
                    id: "runtime-status",
                    event: "runtime-status",
                    interval: configuration.pollIntervalNanoseconds,
                    heartbeatInterval: configuration.heartbeatIntervalNanoseconds,
                    now: now,
                    continuation: continuation
                ) {
                    try await handler.loadStatus()
                }
            }
        case .eventStream:
            do {
                let query = try request.runtimeEventQuery()
                let lastEventID = request.headerValue(named: "Last-Event-ID")
                return makeStream { [handler, configuration] continuation in
                    await pollEvents(
                        lastEventID: lastEventID,
                        interval: configuration.pollIntervalNanoseconds,
                        heartbeatInterval: configuration.heartbeatIntervalNanoseconds,
                        now: now,
                        continuation: continuation
                    ) {
                        try await handler.loadEvents(query: query)
                    }
                }
            } catch let queryError as RuntimeControlHTTPQueryError {
                return errorStreamResponse(queryError.localizedDescription)
            } catch {
                return errorStreamResponse(error.localizedDescription)
            }
        case .vitalDBObservationStream:
            return makeStream { [handler, configuration] continuation in
                await pollSnapshot(
                    id: "vitaldb-observation",
                    event: "vitaldb-observed",
                    interval: configuration.pollIntervalNanoseconds,
                    heartbeatInterval: configuration.heartbeatIntervalNanoseconds,
                    now: now,
                    continuation: continuation
                ) {
                    try await handler.loadVitalDBObservationSnapshot()
                }
            }
        case .logStream:
            do {
                let logRequest = try request.runtimeLogTextRequest()
                return makeStream { [handler, configuration] continuation in
                    await pollSnapshot(
                        id: "runtime-log-\(logRequest.source.rawValue)",
                        event: "runtime-log",
                        interval: configuration.pollIntervalNanoseconds,
                        heartbeatInterval: configuration.heartbeatIntervalNanoseconds,
                        now: now,
                        continuation: continuation
                    ) {
                        try await handler.loadLogText(request: logRequest)
                    }
                }
            } catch let queryError as RuntimeControlHTTPQueryError {
                return errorStreamResponse(queryError.localizedDescription)
            } catch {
                return errorStreamResponse(error.localizedDescription)
            }
        default:
            return errorStreamResponse("Endpoint does not support streaming.")
        }
    }

    private func makeStream(
        _ operation: @escaping @MainActor @Sendable (
            AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation
        ) async -> Void
    ) -> RuntimeControlHTTPStreamResponse {
        let events = AsyncThrowingStream<RuntimeControlServerSentEvent, Error> { continuation in
            let task = Task { @MainActor in
                await operation(continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return RuntimeControlHTTPStreamResponse(
            status: .ok,
            headers: RuntimeControlServerSentEventCodec.streamHeaders,
            events: events
        )
    }

    private func errorStreamResponse(_ message: String) -> RuntimeControlHTTPStreamResponse {
        RuntimeControlHTTPStreamResponse(
            status: .badRequest,
            headers: RuntimeControlServerSentEventCodec.streamHeaders,
            events: AsyncThrowingStream { continuation in
                continuation.yield(RuntimeControlServerSentEvent(
                    id: "runtime-control-error",
                    event: "runtime-control-error",
                    data: RuntimeControlErrorResponseEncoder.encode(code: .badRequest, message: message)
                ))
                continuation.finish()
            }
        )
    }
}
