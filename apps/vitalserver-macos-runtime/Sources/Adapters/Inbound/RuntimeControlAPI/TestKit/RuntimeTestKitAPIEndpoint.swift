import RuntimeControl
import Errors

public enum RuntimeTestKitAPIEndpoint: String, CaseIterable, Codable, Equatable, Sendable {
    case status
    case createBeds
    case deleteBeds
    case resetBeds
    case startVirtualRecorders
    case pauseVirtualRecorders
    case resumeVirtualRecorders
    case stopVirtualRecorders
    case restartVirtualRecorders
    case deleteVirtualRecorders
    case deleteVirtualRecorder
    case resetVirtualRecorders

    public var method: RuntimeControlHTTPMethod {
        switch self {
        case .status:
            return .get
        case .createBeds, .deleteBeds, .resetBeds,
             .startVirtualRecorders, .pauseVirtualRecorders,
             .resumeVirtualRecorders, .stopVirtualRecorders,
             .restartVirtualRecorders,
             .deleteVirtualRecorders, .deleteVirtualRecorder,
             .resetVirtualRecorders:
            return .post
        }
    }

    public var path: String {
        switch self {
        case .status:
            return "/dev/testkit/status"
        case .createBeds:
            return "/dev/testkit/beds/create"
        case .deleteBeds:
            return "/dev/testkit/beds/delete"
        case .resetBeds:
            return "/dev/testkit/beds/reset"
        case .startVirtualRecorders:
            return "/dev/testkit/virtual-recorders/start"
        case .pauseVirtualRecorders:
            return "/dev/testkit/virtual-recorders/pause"
        case .resumeVirtualRecorders:
            return "/dev/testkit/virtual-recorders/resume"
        case .stopVirtualRecorders:
            return "/dev/testkit/virtual-recorders/stop"
        case .restartVirtualRecorders:
            return "/dev/testkit/virtual-recorders/restart"
        case .deleteVirtualRecorders:
            return "/dev/testkit/virtual-recorders/delete"
        case .deleteVirtualRecorder:
            return "/dev/testkit/virtual-recorders/delete-orphan"
        case .resetVirtualRecorders:
            return "/dev/testkit/virtual-recorders/reset"
        }
    }

    public static func matching(method: RuntimeControlHTTPMethod, path: String) -> RuntimeTestKitAPIEndpoint? {
        let normalizedPath = normalizedPath(path)
        return allCases.first { endpoint in
            endpoint.method == method && endpoint.path == normalizedPath
        }
    }

    public static func matches(path: String) -> Bool {
        let normalizedPath = normalizedPath(path)
        return allCases.contains { endpoint in
            endpoint.path == normalizedPath
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return path
        }
        return String(path[..<queryIndex])
    }
}
