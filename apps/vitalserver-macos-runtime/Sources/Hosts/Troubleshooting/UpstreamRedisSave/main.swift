import Foundation

enum RedisSaveError: Error, CustomStringConvertible {
    case invalidURL(String)
    case unsupportedScheme(String)
    case missingHost(String)
    case connectionFailed(String)
    case writeFailed
    case readFailed
    case redisError(String)
    case invalidResponse(String)

    var description: String {
        switch self {
        case .invalidURL(let value):
            return "invalid Redis URL: \(value)"
        case .unsupportedScheme(let scheme):
            return "unsupported Redis URL scheme: \(scheme)"
        case .missingHost(let value):
            return "Redis URL is missing a host: \(value)"
        case .connectionFailed(let target):
            return "failed to connect to Redis: \(target)"
        case .writeFailed:
            return "failed to write Redis command"
        case .readFailed:
            return "failed to read Redis response"
        case .redisError(let message):
            return "Redis command failed: \(message)"
        case .invalidResponse(let message):
            return "invalid Redis response: \(message)"
        }
    }
}

struct RedisEndpoint {
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let database: Int?

    static func parse(_ value: String) throws -> RedisEndpoint {
        guard let components = URLComponents(string: value) else {
            throw RedisSaveError.invalidURL(value)
        }
        let scheme = components.scheme ?? ""
        guard scheme == "redis" else {
            throw RedisSaveError.unsupportedScheme(scheme.isEmpty ? "<empty>" : scheme)
        }
        guard let host = components.host, !host.isEmpty else {
            throw RedisSaveError.missingHost(value)
        }

        let database = try parseDatabase(components.path, url: value)
        return RedisEndpoint(
            host: host,
            port: components.port ?? 6379,
            username: components.percentEncodedUser?.removingPercentEncoding,
            password: components.percentEncodedPassword?.removingPercentEncoding,
            database: database
        )
    }

    private static func parseDatabase(_ path: String, url: String) throws -> Int? {
        guard !path.isEmpty, path != "/" else {
            return nil
        }
        let value = String(path.dropFirst())
        guard let database = Int(value), database >= 0 else {
            throw RedisSaveError.invalidURL(url)
        }
        return database
    }
}

final class RedisConnection {
    private let input: InputStream
    private let output: OutputStream

    init(endpoint: RedisEndpoint) throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(
            nil,
            endpoint.host as CFString,
            UInt32(endpoint.port),
            &readStream,
            &writeStream
        )
        guard let readStream, let writeStream else {
            throw RedisSaveError.connectionFailed("\(endpoint.host):\(endpoint.port)")
        }
        input = readStream.takeRetainedValue()
        output = writeStream.takeRetainedValue()
        input.open()
        output.open()
    }

    deinit {
        input.close()
        output.close()
    }

    func command(_ parts: [String]) throws -> String {
        let payload = encode(parts)
        try write(payload)
        return try readResponse()
    }

    private func encode(_ parts: [String]) -> [UInt8] {
        var bytes = Array("*\(parts.count)\r\n".utf8)
        for part in parts {
            let data = Array(part.utf8)
            bytes.append(contentsOf: "$\(data.count)\r\n".utf8)
            bytes.append(contentsOf: data)
            bytes.append(contentsOf: "\r\n".utf8)
        }
        return bytes
    }

    private func write(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBufferPointer { buffer in
                output.write(
                    buffer.baseAddress!.advanced(by: offset),
                    maxLength: bytes.count - offset
                )
            }
            if written <= 0 {
                throw RedisSaveError.writeFailed
            }
            offset += written
        }
    }

    private func readResponse() throws -> String {
        let prefix = try readByte()
        switch prefix {
        case UInt8(ascii: "+"):
            return try readLine()
        case UInt8(ascii: "-"):
            throw RedisSaveError.redisError(try readLine())
        case UInt8(ascii: ":"):
            return try readLine()
        case UInt8(ascii: "$"):
            return try readBulkString()
        default:
            throw RedisSaveError.invalidResponse("unexpected prefix \(prefix)")
        }
    }

    private func readBulkString() throws -> String {
        let line = try readLine()
        guard let length = Int(line) else {
            throw RedisSaveError.invalidResponse("invalid bulk length \(line)")
        }
        if length == -1 {
            return ""
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(length)
        for _ in 0..<length {
            bytes.append(try readByte())
        }
        let cr = try readByte()
        let lf = try readByte()
        guard cr == 13, lf == 10 else {
            throw RedisSaveError.invalidResponse("bulk string missing CRLF")
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func readLine() throws -> String {
        var bytes = [UInt8]()
        while true {
            let byte = try readByte()
            bytes.append(byte)
            if bytes.count >= 2,
               bytes[bytes.count - 2] == 13,
               bytes[bytes.count - 1] == 10 {
                bytes.removeLast(2)
                return String(decoding: bytes, as: UTF8.self)
            }
        }
    }

    private func readByte() throws -> UInt8 {
        var byte: UInt8 = 0
        let count = input.read(&byte, maxLength: 1)
        if count != 1 {
            throw RedisSaveError.readFailed
        }
        return byte
    }
}

func run() throws {
    let rawURL = CommandLine.arguments.dropFirst().first ?? "redis://127.0.0.1:6379"
    let endpoint = try RedisEndpoint.parse(rawURL)
    let connection = try RedisConnection(endpoint: endpoint)

    if let password = endpoint.password, !password.isEmpty {
        if let username = endpoint.username, !username.isEmpty {
            _ = try connection.command(["AUTH", username, password])
        } else {
            _ = try connection.command(["AUTH", password])
        }
    }
    if let database = endpoint.database, database > 0 {
        _ = try connection.command(["SELECT", String(database)])
    }
    let response = try connection.command(["SAVE"])
    print(response)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
