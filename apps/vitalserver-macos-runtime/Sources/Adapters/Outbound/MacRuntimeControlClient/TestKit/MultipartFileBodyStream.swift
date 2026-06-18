import Foundation

final class MultipartFileBodyStream: InputStream {
    private let streams: [InputStream]
    private var currentIndex = 0
    private var currentStatus: Stream.Status = .notOpen
    private var currentError: Error?

    init(header: Data, fileURL: URL, footer: Data) throws {
        guard let fileStream = InputStream(url: fileURL) else {
            throw MacTestKitControllerError.requestFailed("Cannot open file stream: \(fileURL.path)")
        }
        streams = [
            InputStream(data: header),
            fileStream,
            InputStream(data: footer),
        ]
        super.init(data: Data())
    }

    override var streamStatus: Stream.Status {
        currentStatus
    }

    override var streamError: Error? {
        currentError
    }

    override var hasBytesAvailable: Bool {
        currentStatus == .open || currentStatus == .reading
    }

    override func open() {
        guard currentStatus == .notOpen else {
            return
        }
        currentStatus = .open
        streams.first?.open()
    }

    override func close() {
        for stream in streams {
            stream.close()
        }
        currentStatus = .closed
    }

    override func read(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        guard currentStatus != .closed,
              currentStatus != .error,
              currentStatus != .atEnd else {
            return 0
        }

        currentStatus = .reading

        while currentIndex < streams.count {
            let stream = streams[currentIndex]
            let bytesRead = stream.read(buffer, maxLength: len)
            if bytesRead > 0 {
                currentStatus = .open
                return bytesRead
            }
            if bytesRead < 0 {
                currentError = stream.streamError
                currentStatus = .error
                return -1
            }

            stream.close()
            currentIndex += 1
            if currentIndex < streams.count {
                streams[currentIndex].open()
            }
        }

        currentStatus = .atEnd
        return 0
    }
}
