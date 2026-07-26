import Application
import Foundation

@MainActor
final class RuntimeEndpointSynchronizationLoop {
    private let bootstrapReader: any RuntimeGuestAddressBootstrapReading
    private let lifecycleReader: any RuntimeVMLifecycleStateReading
    private let endpointRepository: any RuntimeEndpointStateRepository
    private let useCase: SynchronizeRuntimeEndpointUseCase
    private let timestamp: @Sendable () -> String
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastReport: String?

    init(
        bootstrapReader: any RuntimeGuestAddressBootstrapReading,
        lifecycleReader: any RuntimeVMLifecycleStateReading,
        endpointRepository: any RuntimeEndpointStateRepository,
        useCase: SynchronizeRuntimeEndpointUseCase,
        timestamp: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        },
        interval: TimeInterval
    ) {
        self.bootstrapReader = bootstrapReader
        self.lifecycleReader = lifecycleReader
        self.endpointRepository = endpointRepository
        self.useCase = useCase
        self.timestamp = timestamp
        self.interval = interval
    }

    func start() {
        guard timer == nil else { return }
        synchronize()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.synchronize()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func synchronize() {
        let decision = useCase.decide(
            bootstrap: bootstrapReader.readBootstrapGuestAddress(),
            lifecycleRead: lifecycleReader.loadVMLifecycleState(),
            endpointRead: endpointRepository.loadRuntimeEndpointState(),
            observedAt: timestamp()
        )
        let report: String?
        switch decision {
        case .unchanged:
            report = nil
        case .persist(let mutation):
            do {
                let endpoint = try endpointRepository.saveRuntimeEndpointState(mutation)
                report = "runtime endpoint synchronized runID=\(endpoint.runID) lifecycleRevision=\(endpoint.lifecycleRevision) address=\(endpoint.address) revision=\(endpoint.revision)"
            } catch {
                report = "runtime endpoint synchronization failed reason=\(error)"
            }
        case .bootstrapUnavailable(let read):
            report = "runtime endpoint bootstrap unavailable state=\(read.state.rawValue) reason=\(read.reason ?? "not-reported")"
        case .lifecycleUnavailable(let reason):
            report = "runtime endpoint lifecycle unavailable reason=\(reason)"
        case .failed(let reason):
            report = "runtime endpoint synchronization failed reason=\(reason)"
        }
        guard let report, report != lastReport else { return }
        lastReport = report
        FileHandle.standardError.write(Data("\(report)\n".utf8))
    }
}
