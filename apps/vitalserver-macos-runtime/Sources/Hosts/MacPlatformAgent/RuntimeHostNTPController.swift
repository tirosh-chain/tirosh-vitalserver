import Contracts
import Domain
import Foundation

@MainActor
final class RuntimeHostNTPController {
    private let guestAddress: () -> RuntimeGuestAddressReadResult
    private let interfaces: () throws -> [RuntimeIPv4InterfaceAddress]
    private let writeContract: (RuntimeTimeAuthorityDocument) throws -> Void
    private let now: @Sendable () -> Date
    private let interval: TimeInterval
    private let serverPort: UInt16
    private let makeServer: (
        RuntimeHostNTPServerConfiguration,
        @escaping @Sendable () -> Date,
        @escaping @Sendable (RuntimeHostNTPServerState) -> Void
    ) -> any RuntimeHostNTPServing
    private var timer: Timer?
    private var server: (any RuntimeHostNTPServing)?
    private var selection: RuntimeHostNTPListenerSelection?
    private(set) var currentDocument: RuntimeTimeAuthorityDocument?

    init(
        guestAddress: @escaping () -> RuntimeGuestAddressReadResult,
        interfaces: @escaping () throws -> [RuntimeIPv4InterfaceAddress],
        writeContract: @escaping (RuntimeTimeAuthorityDocument) throws -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        interval: TimeInterval,
        serverPort: UInt16 = 123,
        makeServer: @escaping (
            RuntimeHostNTPServerConfiguration,
            @escaping @Sendable () -> Date,
            @escaping @Sendable (RuntimeHostNTPServerState) -> Void
        ) -> any RuntimeHostNTPServing = { configuration, now, handler in
            RuntimeHostNTPServer(
                configuration: configuration,
                now: now,
                stateHandler: handler
            )
        }
    ) {
        self.guestAddress = guestAddress
        self.interfaces = interfaces
        self.writeContract = writeContract
        self.now = now
        self.interval = interval
        self.serverPort = serverPort
        self.makeServer = makeServer
    }

    func start() {
        guard timer == nil else {
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        server?.stop()
        server = nil
        selection = nil
    }

    func refresh() {
        let guestRead = guestAddress()
        guard let guest = guestRead.loadedAddress else {
            transitionToUnavailable(
                state: .unavailable,
                reason: "Guest address state is \(guestRead.state.rawValue): \(guestRead.reason ?? "no detail")"
            )
            return
        }

        let interfaceReads: [RuntimeIPv4InterfaceAddress]
        do {
            interfaceReads = try interfaces()
        } catch {
            transitionToUnavailable(
                state: .failed,
                reason: "Host interface read failed: \(error)"
            )
            return
        }

        switch RuntimeHostNTPListenerPolicy.select(
            guestAddress: guest,
            interfaces: interfaceReads
        ) {
        case .unavailable(let reason):
            transitionToUnavailable(state: .unavailable, reason: reason)
        case .selected(let selected):
            startServerIfRequired(selected)
        }
    }

    private func startServerIfRequired(_ selected: RuntimeHostNTPListenerSelection) {
        guard selection != selected || server == nil else {
            return
        }
        server?.stop()
        server = nil
        selection = selected
        publish(
            document(
                state: .synchronizing,
                selection: selected,
                issue: nil
            )
        )

        let nextServer = makeServer(
            RuntimeHostNTPServerConfiguration(
                bindAddress: selected.hostAddress,
                port: serverPort,
                allowedClientAddress: selected.allowedGuestAddress
            ),
            now,
            { [weak self] state in
                Task { @MainActor in
                    self?.handle(state, selection: selected)
                }
            }
        )
        server = nextServer
        do {
            try nextServer.start()
        } catch {
            handle(.failed(String(describing: error)), selection: selected)
        }
    }

    private func handle(
        _ state: RuntimeHostNTPServerState,
        selection selected: RuntimeHostNTPListenerSelection
    ) {
        guard selection == selected else {
            return
        }
        switch state {
        case .starting:
            publish(document(state: .synchronizing, selection: selected, issue: nil))
        case .ready:
            publish(document(state: .hostClockOnly, selection: selected, issue: nil))
        case .failed(let reason):
            server = nil
            publish(document(state: .failed, selection: selected, issue: reason))
        case .stopped:
            break
        }
    }

    private func transitionToUnavailable(
        state: RuntimeClockQualityState,
        reason: String
    ) {
        server?.stop()
        server = nil
        selection = nil
        publish(RuntimeTimeAuthorityDocument(
            profile: .helperNTP,
            sourceId: "helper-host-clock",
            serverAddress: nil,
            serverPort: nil,
            state: state,
            stratum: nil,
            allowedClientAddress: nil,
            updatedAt: timestamp(),
            issue: reason
        ))
    }

    private func document(
        state: RuntimeClockQualityState,
        selection: RuntimeHostNTPListenerSelection,
        issue: String?
    ) -> RuntimeTimeAuthorityDocument {
        RuntimeTimeAuthorityDocument(
            profile: .helperNTP,
            sourceId: "helper-host-clock",
            serverAddress: selection.hostAddress,
            serverPort: Int(serverPort),
            state: state,
            stratum: Int(RuntimeNTPPacketPolicy.helperClockStratum),
            allowedClientAddress: selection.allowedGuestAddress,
            updatedAt: timestamp(),
            issue: issue
        )
    }

    private func publish(_ document: RuntimeTimeAuthorityDocument) {
        guard document != currentDocument else {
            return
        }
        do {
            try writeContract(document)
            currentDocument = document
        } catch {
            FileHandle.standardError.write(Data(
                "Host NTP contract write failed: \(error)\n".utf8
            ))
        }
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: now())
    }
}
