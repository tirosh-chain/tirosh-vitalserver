import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeProxyLaunchDaemonPortReader {
    let plistPath: String
    let fileStore: RuntimeFileReading

    func loadSettingsResult() -> RuntimeSettingsReadResult<Int> {
        switch loadPortState() {
        case .loaded(let port):
            return .loaded(port)
        case .missing:
            return .missing
        case .readFailed(let message), .invalid(let message):
            return .failed(message)
        case .outOfRange(let port):
            return .failed("VITALSERVER_PROXY_PORT is out of range: \(port)")
        }
    }

    func loadReadState() -> RuntimeProxyPortReadState {
        switch loadPortState() {
        case .loaded(let port):
            return .loaded(port)
        case .missing:
            return .missing("proxy launch daemon plist missing path=\(plistPath)")
        case .readFailed(let message):
            return .readFailed(message)
        case .invalid(let message):
            return .invalid(message)
        case .outOfRange(let port):
            return .outOfRange(port)
        }
    }

    private func loadPortState() -> RuntimeProxyLaunchDaemonPortState {
        let url = URL(fileURLWithPath: plistPath)
        switch runtimeSettingsReadableFileState(url, fileStore: fileStore) {
        case .loaded:
            break
        case .missing:
            return .missing
        case .failed(let message):
            return .readFailed(message)
        }
        do {
            let data = try fileStore.readData(url)
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
            guard let document = plist as? [String: Any],
                  let environment = document["EnvironmentVariables"] as? [String: Any],
                  let rawPort = environment["VITALSERVER_PROXY_PORT"] as? String
            else {
                return .invalid("VITALSERVER_PROXY_PORT is missing or invalid")
            }
            guard let port = Int(rawPort) else {
                return .invalid("VITALSERVER_PROXY_PORT is missing or invalid")
            }
            guard (1...65_535).contains(port) else {
                return .outOfRange(port)
            }
            return .loaded(port)
        } catch {
            return .readFailed(error.localizedDescription)
        }
    }
}

private enum RuntimeProxyLaunchDaemonPortState {
    case missing
    case loaded(Int)
    case readFailed(String)
    case invalid(String)
    case outOfRange(Int)
}
