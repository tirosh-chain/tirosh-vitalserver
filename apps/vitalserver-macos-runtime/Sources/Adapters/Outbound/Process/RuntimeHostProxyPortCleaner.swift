import Application
import Contracts
import Foundation
import Errors

public typealias RuntimeProxyNginxPIDReadResult = Contracts.RuntimeProxyNginxPIDReadResult

public struct RuntimeHostProxyPortCleaner {
    private var proxyPort: () -> Int?
    private var proxyServiceState: () -> RuntimeServiceState
    private var expectedProxyNginxPID: () -> RuntimeProxyNginxPIDReadResult
    private var ownedNginxPathFragments: [String]
    private var lsofPath: String
    private var psPath: String
    private var killPath: String
    private var runProcess: (String, [String]) -> RuntimeProcessResult
    private var sleep: (TimeInterval) -> Void
    private var log: (String) -> Void
    private var listenerScanner: RuntimeHostProxyPortListenerScanner {
        RuntimeHostProxyPortListenerScanner(
            lsofPath: lsofPath,
            runProcess: runProcess
        )
    }
    private var nginxCommandLineReader: RuntimeHostProxyNginxCommandLineReader {
        RuntimeHostProxyNginxCommandLineReader(
            psPath: psPath,
            runProcess: runProcess
        )
    }
    public init(
        proxyPort: @escaping () -> Int?,
        proxyServiceState: @escaping () -> RuntimeServiceState,
        expectedProxyNginxPID: @escaping () -> RuntimeProxyNginxPIDReadResult,
        ownedNginxPathFragments: [String],
        lsofPath: String,
        psPath: String,
        killPath: String,
        runProcess: @escaping (String, [String]) -> RuntimeProcessResult,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        log: @escaping (String) -> Void
    ) {
        self.proxyPort = proxyPort
        self.proxyServiceState = proxyServiceState
        self.expectedProxyNginxPID = expectedProxyNginxPID
        self.ownedNginxPathFragments = ownedNginxPathFragments
        self.lsofPath = lsofPath
        self.psPath = psPath
        self.killPath = killPath
        self.runProcess = runProcess
        self.sleep = sleep
        self.log = log
    }

    public var operations: CleanRuntimeHostProxyPortOperations {
        CleanRuntimeHostProxyPortOperations(
            proxyPort: proxyPort,
            proxyServiceState: proxyServiceState,
            expectedProxyNginxPID: expectedProxyNginxPID,
            portListenerScan: { port in
                listenerScanner.scan(port: port)
            },
            ownedNginxPathFragments: ownedNginxPathFragments,
            nginxCommandLine: { pid in
                nginxCommandLineReader.read(pid: pid)
            },
            signalOwnedListener: { pid, signal in
                let signalArgument: String
                switch signal {
                case .terminate:
                    signalArgument = "-TERM"
                case .kill:
                    signalArgument = "-KILL"
                }
                _ = runProcess(killPath, [signalArgument, pid])
            },
            sleep: sleep,
            log: log
        )
    }
}
