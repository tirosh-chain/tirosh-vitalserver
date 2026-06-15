import Contracts
import Foundation

struct RuntimeHostProxyPortListenerScanner {
    var lsofPath: String
    var runProcess: (String, [String]) -> RuntimeProcessResult

    func scan(port: Int) -> RuntimeHostProxyListenerScanResult {
        let result = runProcess(lsofPath, ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        return RuntimeHostProxyListenerScanResultMapper.scanResult(from: result)
    }
}
