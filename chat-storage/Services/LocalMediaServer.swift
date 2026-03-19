import Foundation
import Network

/// 本地 HTTP 视频代理。
/// AVPlayer 只和本地 127.0.0.1 进行 HTTP/Range 交互，代理再把请求翻译成远端自定义帧协议。
final class LocalMediaServer {
    static let shared = LocalMediaServer()

    private let queue = DispatchQueue(label: "com.chatstorage.local-media-server", qos: .userInitiated)
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var listenerReadySemaphore: DispatchSemaphore?

    private init() {}

    func getStreamURL(for fileId: Int64, fileSize: Int64, fileName: String) -> URL? {
        guard let port = serverPort() else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/stream"
        components.queryItems = [
            URLQueryItem(name: "fileId", value: String(fileId)),
            URLQueryItem(name: "size", value: String(fileSize)),
            URLQueryItem(name: "name", value: fileName),
        ]
        return components.url
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            port = nil

            let allConnections = Array(connections.values)
            connections.removeAll()
            allConnections.forEach { $0.cancel() }
        }
    }

    private func serverPort() -> Int? {
        if let port = validPort(from: port) {
            return port
        }

        startSync()
        return validPort(from: port)
    }

    private func startSync() {
        var readySemaphore: DispatchSemaphore?
        var shouldWaitForReady = false

        queue.sync {
            if listener != nil {
                if validPort(from: port) == nil {
                    readySemaphore = listenerReadySemaphore
                    shouldWaitForReady = true
                }
                return
            }

            do {
                let listener = try NWListener(using: .tcp)
                let semaphore = DispatchSemaphore(value: 0)
                listenerReadySemaphore = semaphore
                readySemaphore = semaphore
                shouldWaitForReady = true

                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }

                    switch state {
                    case .ready:
                        if let resolvedPort = self.validPort(from: listener?.port) {
                            self.port = NWEndpoint.Port(rawValue: UInt16(resolvedPort))
                            print("✅ [LocalMediaServer] started on port \(resolvedPort)")
                        } else {
                            self.port = nil
                            print("❌ [LocalMediaServer] listener became ready but no valid port was assigned")
                        }
                        semaphore.signal()
                    case .failed(let error):
                        self.port = nil
                        print("❌ [LocalMediaServer] failed to start: \(error)")
                        semaphore.signal()
                    case .cancelled:
                        semaphore.signal()
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleNewConnection(connection)
                }
                listener.start(queue: queue)

                self.listener = listener
            } catch {
                print("❌ [LocalMediaServer] failed to start: \(error)")
            }
        }

        guard shouldWaitForReady, let readySemaphore else {
            return
        }

        if readySemaphore.wait(timeout: .now() + 1.5) == .timedOut {
            queue.sync {
                self.listener?.cancel()
                self.listener = nil
                self.port = nil
                self.listenerReadySemaphore = nil
            }
            print("❌ [LocalMediaServer] timed out while waiting for listener to become ready")
            return
        }

        queue.sync {
            self.listenerReadySemaphore = nil
        }
    }

    private func validPort(from endpointPort: NWEndpoint.Port?) -> Int? {
        guard let rawValue = endpointPort?.rawValue, rawValue != 0 else {
            return nil
        }
        return Int(rawValue)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        connections[connectionID] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed(let error):
                print("❌ [LocalMediaServer] connection failed: \(error)")
                self.cleanupConnection(connection)
            case .cancelled:
                self.cleanupConnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func cleanupConnection(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("❌ [LocalMediaServer] receive error: \(error)")
                connection.cancel()
                return
            }

            let chunk = data ?? Data()
            let merged = buffer + chunk

            if let headerRange = merged.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = merged.subdata(in: 0..<headerRange.upperBound)
                guard let requestString = String(data: headerData, encoding: .utf8) else {
                    self.sendSimpleResponse(statusLine: "HTTP/1.1 400 Bad Request", on: connection)
                    return
                }

                self.processRequest(requestString, on: connection)
                return
            }

            if isComplete {
                self.sendSimpleResponse(statusLine: "HTTP/1.1 400 Bad Request", on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: merged)
        }
    }

    private func processRequest(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendSimpleResponse(statusLine: "HTTP/1.1 400 Bad Request", on: connection)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            sendSimpleResponse(statusLine: "HTTP/1.1 400 Bad Request", on: connection)
            return
        }

        let method = parts[0].uppercased()
        let rawPath = parts[1]

        guard method == "GET" || method == "HEAD" else {
            sendSimpleResponse(statusLine: "HTTP/1.1 405 Method Not Allowed", on: connection)
            return
        }

        guard let components = URLComponents(string: rawPath),
              components.path == "/stream",
              let fileIdString = components.queryItems?.first(where: { $0.name == "fileId" })?.value,
              let fileId = Int64(fileIdString),
              let sizeString = components.queryItems?.first(where: { $0.name == "size" })?.value,
              let totalSize = Int64(sizeString) else {
            sendSimpleResponse(statusLine: "HTTP/1.1 404 Not Found", on: connection)
            return
        }

        let fileName = components.queryItems?.first(where: { $0.name == "name" })?.value ?? "video.mp4"
        let mimeType = Self.mimeType(for: fileName)

        let rangeHeader = lines.first { $0.lowercased().starts(with: "range:") }
        let byteRange = Self.parseRange(rangeHeader, totalSize: totalSize)

        if byteRange.isInvalid {
            let body = "Requested Range Not Satisfiable"
            let response = """
            HTTP/1.1 416 Range Not Satisfiable\r
            Content-Range: bytes */\(totalSize)\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            sendData(Data(response.utf8), on: connection, closeAfter: true)
            return
        }

        let actualRange = byteRange.range ?? (0...(max(totalSize - 1, 0)))
        let statusLine = byteRange.isPartial ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 200 OK"
        let contentLength = actualRange.upperBound - actualRange.lowerBound + 1

        var header = "\(statusLine)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        if byteRange.isPartial {
            header += "Content-Range: bytes \(actualRange.lowerBound)-\(actualRange.upperBound)/\(totalSize)\r\n"
        }
        header += "Connection: close\r\n\r\n"

        if method == "HEAD" {
            sendData(Data(header.utf8), on: connection, closeAfter: true)
            return
        }

        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            if let error {
                print("❌ [LocalMediaServer] send header error: \(error)")
                connection.cancel()
                return
            }

            self.streamVideoData(
                fileId: fileId,
                startOffset: actualRange.lowerBound,
                endOffset: actualRange.upperBound,
                to: connection
            )
        })
    }

    private func streamVideoData(
        fileId: Int64,
        startOffset: Int64,
        endOffset: Int64,
        to connection: NWConnection
    ) {
        let streamingService = VideoStreamingService()
        let delegate = NWConnectionVideoStreamDelegate(
            connection: connection,
            requestedRange: startOffset...endOffset,
            onCompletion: { [weak connection] in
                connection?.cancel()
            },
            onCancelStream: {
                streamingService.cancel()
            }
        )

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                delegate.cancel()
                self.cleanupConnection(connection)
            default:
                break
            }
        }

        Task {
            do {
                try await streamingService.startCustomVideoStreaming(
                    fileId: fileId,
                    startOffset: startOffset,
                    delegate: delegate
                )
            } catch is CancellationError {
                // 连接取消或区间满足后主动停止，属于正常路径。
            } catch {
                delegate.didFail(with: error)
            }
        }
    }

    private func sendSimpleResponse(statusLine: String, on connection: NWConnection) {
        let response = "\(statusLine)\r\nConnection: close\r\n\r\n"
        sendData(Data(response.utf8), on: connection, closeAfter: true)
    }

    private func sendData(_ data: Data, on connection: NWConnection, closeAfter: Bool) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("❌ [LocalMediaServer] send error: \(error)")
            }
            if closeAfter {
                connection.cancel()
            }
        })
    }

    private static func parseRange(_ header: String?, totalSize: Int64) -> ParsedByteRange {
        guard totalSize > 0 else {
            return ParsedByteRange(range: nil, isPartial: false, isInvalid: false)
        }

        guard let header else {
            return ParsedByteRange(range: nil, isPartial: false, isInvalid: false)
        }

        let lowercased = header.lowercased()
        guard lowercased.starts(with: "range: bytes=") else {
            return ParsedByteRange(range: nil, isPartial: false, isInvalid: false)
        }

        let rawValue = header.components(separatedBy: "=").last ?? ""
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .invalid
        }

        let startString = parts[0].trimmingCharacters(in: .whitespaces)
        let endString = parts[1].trimmingCharacters(in: .whitespaces)

        guard let start = Int64(startString), start >= 0, start < totalSize else {
            return .invalid
        }

        let end: Int64
        if endString.isEmpty {
            end = totalSize - 1
        } else if let parsedEnd = Int64(endString), parsedEnd >= start {
            end = min(parsedEnd, totalSize - 1)
        } else {
            return .invalid
        }

        return ParsedByteRange(range: start...end, isPartial: true, isInvalid: false)
    }

    private static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
        case "mkv":
            return "video/x-matroska"
        default:
            return "application/octet-stream"
        }
    }
}

private struct ParsedByteRange {
    let range: ClosedRange<Int64>?
    let isPartial: Bool
    let isInvalid: Bool

    static let invalid = ParsedByteRange(range: nil, isPartial: false, isInvalid: true)
}

private final class NWConnectionVideoStreamDelegate: VideoStreamLoaderDelegate {
    private let connection: NWConnection
    private let requestedRange: ClosedRange<Int64>
    private let onCompletion: () -> Void
    private let onCancelStream: () -> Void
    private let lock = NSLock()

    private var hasCompleted = false

    init(
        connection: NWConnection,
        requestedRange: ClosedRange<Int64>,
        onCompletion: @escaping () -> Void,
        onCancelStream: @escaping () -> Void
    ) {
        self.connection = connection
        self.requestedRange = requestedRange
        self.onCompletion = onCompletion
        self.onCancelStream = onCancelStream
    }

    func cancel() {
        finishIfNeeded()
        onCancelStream()
    }

    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {
        // 本地代理已经在收到 HTTP 请求时返回了响应头，这里无需重复处理。
    }

    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        lock.lock()
        if hasCompleted {
            lock.unlock()
            return
        }

        guard range.lowerBound <= requestedRange.upperBound else {
            lock.unlock()
            finishIfNeeded()
            onCancelStream()
            return
        }

        let clampedStart = max(range.lowerBound, requestedRange.lowerBound)
        let clampedEndExclusive = min(range.upperBound, requestedRange.upperBound + 1)
        let bytesToSend = max(0, clampedEndExclusive - clampedStart)

        guard bytesToSend > 0 else {
            lock.unlock()
            return
        }

        let offsetInChunk = Int(clampedStart - range.lowerBound)
        let endInChunk = offsetInChunk + Int(bytesToSend)
        let subdata = data.subdata(in: offsetInChunk..<endInChunk)
        let shouldCompleteAfterSend = clampedEndExclusive > requestedRange.upperBound || clampedEndExclusive == requestedRange.upperBound + 1
        lock.unlock()

        connection.send(content: subdata, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                print("❌ [LocalMediaServer] write chunk failed: \(error)")
                self.finishIfNeeded()
                self.onCancelStream()
                self.connection.cancel()
                return
            }

            if shouldCompleteAfterSend {
                self.finishIfNeeded()
                self.onCancelStream()
                self.onCompletion()
            }
        })
    }

    func didFinishLoading() {
        finishIfNeeded()
        onCompletion()
    }

    func didFail(with error: Error) {
        print("❌ [LocalMediaServer] stream failure delegate: \(error)")
        finishIfNeeded()
        connection.cancel()
    }

    private func finishIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        hasCompleted = true
    }
}
