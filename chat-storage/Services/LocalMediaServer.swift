import Foundation
import Network

/// 本地 HTTP 视频代理（混合架构版）。
///
/// 数据服务三条路径：
///   1. 磁盘缓存命中  → 直接读盘，无网络请求
///   2. 顺序小幅未命中 → 注册 RangeWaiter，等后台流写到该位置（不新建连接）
///   3. 非顺序访问    → 专用 VideoStreamingService（moov 探针、大幅 seek 等）
///
/// 后台流（VideoStreamCache）与播放状态解耦，暂停不停流。
final class LocalMediaServer {
    static let shared = LocalMediaServer()

    private let queue = DispatchQueue(label: "com.chatstorage.local-media-server", qos: .userInitiated)
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// 专用流 Task，仅用于路径 3（非顺序访问）的清理。
    private var dedicatedStreamTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
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
            dedicatedStreamTasks.values.forEach { $0.cancel() }
            dedicatedStreamTasks.removeAll()

            listener?.cancel()
            listener = nil
            port = nil

            let allConnections = Array(connections.values)
            connections.removeAll()
            allConnections.forEach { $0.cancel() }
        }
    }

    // MARK: - Listener 启动

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
                        }
                        semaphore.signal()
                    case .failed(let error):
                        self.port = nil
                        print("❌ [LocalMediaServer] failed: \(error)")
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

        guard shouldWaitForReady, let readySemaphore else { return }

        if readySemaphore.wait(timeout: .now() + 1.5) == .timedOut {
            queue.sync {
                self.listener?.cancel()
                self.listener = nil
                self.port = nil
                self.listenerReadySemaphore = nil
            }
            print("❌ [LocalMediaServer] timed out waiting for listener")
            return
        }

        queue.sync { self.listenerReadySemaphore = nil }
    }

    private func validPort(from endpointPort: NWEndpoint.Port?) -> Int? {
        guard let rawValue = endpointPort?.rawValue, rawValue != 0 else { return nil }
        return Int(rawValue)
    }

    // MARK: - 连接管理

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
        let id = ObjectIdentifier(connection)
        dedicatedStreamTasks[id]?.cancel()
        dedicatedStreamTasks.removeValue(forKey: id)
        connections.removeValue(forKey: id)
    }

    // MARK: - HTTP 请求处理

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
            let response = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(totalSize)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
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

    // MARK: - 数据服务（混合架构）

    private func streamVideoData(
        fileId: Int64,
        startOffset: Int64,
        endOffset: Int64,
        to connection: NWConnection
    ) {
        // 尝试获取后台缓存
        let cache = VideoStreamCacheManager.shared.cache(for: fileId)

        // 路径 1：磁盘缓存命中 → 直接读盘
        if let cache, !cache.isInvalid, cache.isRangeAvailable(startOffset...endOffset) {
            serveFromCache(cache, range: startOffset...endOffset, to: connection)
            return
        }

        // 判断是否需要专用流（路径 3）：
        //   a. 无可用缓存（初次建立或缓存失效）
        //   b. 起点在后台流当前位置之前（向前跳）
        //   c. 距后台流当前位置超过阈值（大幅 seek / moov atom 探针）
        //   d. 请求区间过大（如 Range: bytes=0- 或无 Range Header 的全文件请求）
        //      — 此类 Waiter 需等全文件缓存完才能触发，实际永远不会触发，会导致 20s 后超时
        let needsDedicatedStream: Bool
        if let cache, !cache.isInvalid {
            let currentPos = cache.currentDownloadPosition
            let seekThreshold: Int64 = 50 * 1024 * 1024  // 50MB
            let isBackwardAccess = startOffset < cache.downloadStartOffset
            let isLargeForwardJump = startOffset > currentPos && (startOffset - currentPos) >= seekThreshold
            let rangeSize = endOffset - startOffset + 1
            let isVeryLargeRange = rangeSize > 50 * 1024 * 1024  // 超过 50MB 的区间不走 Waiter
            needsDedicatedStream = isBackwardAccess || isLargeForwardJump || isVeryLargeRange
        } else {
            needsDedicatedStream = true
        }

        if needsDedicatedStream {
            // 路径 3：专用短生命周期流（处理 moov 探针、大幅 seek、无缓存等情形）
            //         不影响后台流，不重启后台流，仅服务这一个 Range。
            print("🔀 [LocalMediaServer] 专用流: bytes=\(startOffset)-\(endOffset)")
            createDedicatedStream(fileId: fileId, startOffset: startOffset, endOffset: endOffset, to: connection)
        } else {
            // 路径 2：小幅顺序未命中 → 注册 Waiter，等后台流写到该位置
            let currentPos = cache?.currentDownloadPosition ?? 0
            print("⏳ [LocalMediaServer] Waiter: bytes=\(startOffset)-\(endOffset)（后台位置=\(currentPos)）")

            guard let cache, !cache.isInvalid else {
                connection.cancel()
                return
            }

            let serve: () -> Void = { [weak self, weak cache] in
                guard let self, let cache, !cache.isInvalid else {
                    connection.cancel()
                    return
                }
                self.queue.async {
                    do {
                        let data = try cache.readData(range: startOffset...endOffset)
                        self.sendData(data, on: connection, closeAfter: true)
                    } catch {
                        print("❌ [LocalMediaServer] Waiter 读盘失败 [\(startOffset)-\(endOffset)]: \(error)")
                        connection.cancel()
                    }
                }
            }
            cache.registerWaiter(for: startOffset...endOffset, serve: serve, cancel: { connection.cancel() })
        }
    }

    /// 创建专用 VideoStreamingService 服务指定 Range（路径 3）。
    /// 仅服务所请求的字节区间，完成后自动释放。
    private func createDedicatedStream(
        fileId: Int64,
        startOffset: Int64,
        endOffset: Int64,
        to connection: NWConnection
    ) {
        let streamingService = VideoStreamingService()
        let delegate = RangeStreamDelegate(
            connection: connection,
            requestedRange: startOffset...endOffset,
            onCancelStream: { [weak streamingService] in streamingService?.cancel() }
        )

        // 当连接失败/关闭时，取消专用流
        let connectionID = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self, weak connection, weak delegate] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                delegate?.cancel()
                self.cleanupConnection(connection)
            default:
                break
            }
        }

        let task = Task { [weak self] in
            defer {
                self?.queue.async {
                    self?.dedicatedStreamTasks.removeValue(forKey: connectionID)
                }
            }
            do {
                try await streamingService.startCustomVideoStreaming(
                    fileId: fileId,
                    startOffset: startOffset,
                    delegate: delegate
                )
            } catch is CancellationError {
                // 正常路径：Range 满足或连接关闭
            } catch {
                delegate.didFail(with: error)
            }
        }
        queue.async { [weak self] in
            self?.dedicatedStreamTasks[connectionID] = task
        }
    }

    // MARK: - 缓存读取与发送

    private func serveFromCache(
        _ cache: VideoStreamCache,
        range: ClosedRange<Int64>,
        to connection: NWConnection
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try cache.readData(range: range)
                self.sendData(data, on: connection, closeAfter: true)
            } catch {
                print("❌ [LocalMediaServer] 缓存读取失败: \(error)")
                connection.cancel()
            }
        }
    }

    private func sendSimpleResponse(statusLine: String, on connection: NWConnection) {
        let response = "\(statusLine)\r\nConnection: close\r\n\r\n"
        sendData(Data(response.utf8), on: connection, closeAfter: true)
    }

    private func sendData(_ data: Data, on connection: NWConnection, closeAfter: Bool) {
        connection.send(
            content: data,
            contentContext: .defaultMessage,
            isComplete: closeAfter,
            completion: .contentProcessed { error in
                if let error {
                    print("❌ [LocalMediaServer] send error: \(error)")
                    connection.cancel()
                }
            }
        )
    }

    // MARK: - Range 解析

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
        guard parts.count == 2 else { return .invalid }

        let startString = parts[0].trimmingCharacters(in: .whitespaces)
        let endString = parts[1].trimmingCharacters(in: .whitespaces)

        guard let start = Int64(startString), start >= 0, start < totalSize else { return .invalid }

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
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - ParsedByteRange

private struct ParsedByteRange {
    let range: ClosedRange<Int64>?
    let isPartial: Bool
    let isInvalid: Bool
    static let invalid = ParsedByteRange(range: nil, isPartial: false, isInvalid: true)
}

// MARK: - RangeStreamDelegate（专用流代理）

/// 将 VideoStreamingService 的数据回调转发给指定的 NWConnection。
/// 仅转发 requestedRange 内的字节，区间满足后主动取消流。
private final class RangeStreamDelegate: VideoStreamLoaderDelegate {
    private let connection: NWConnection
    private let requestedRange: ClosedRange<Int64>
    private let onCancelStream: () -> Void
    private let lock = NSLock()
    private var hasCompleted = false

    init(
        connection: NWConnection,
        requestedRange: ClosedRange<Int64>,
        onCancelStream: @escaping () -> Void
    ) {
        self.connection = connection
        self.requestedRange = requestedRange
        self.onCancelStream = onCancelStream
    }

    func cancel() {
        markCompleted()
        onCancelStream()
    }

    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {}

    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        lock.lock()
        guard !hasCompleted else { lock.unlock(); return }

        guard range.lowerBound <= requestedRange.upperBound else {
            lock.unlock()
            markCompleted()
            onCancelStream()
            return
        }

        let clampedStart = max(range.lowerBound, requestedRange.lowerBound)
        let clampedEnd = min(range.upperBound, requestedRange.upperBound + 1)
        let bytesToSend = clampedEnd - clampedStart
        guard bytesToSend > 0 else { lock.unlock(); return }

        let offsetInChunk = Int(clampedStart - range.lowerBound)
        let subdata = data.subdata(in: offsetInChunk..<(offsetInChunk + Int(bytesToSend)))
        let isLast = clampedEnd > requestedRange.upperBound
        lock.unlock()

        connection.send(
            content: subdata,
            contentContext: .defaultMessage,
            isComplete: isLast,
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    print("❌ [RangeStreamDelegate] 发送失败: \(error)")
                    self.markCompleted()
                    self.onCancelStream()
                    self.connection.cancel()
                    return
                }
                if isLast {
                    self.markCompleted()
                    self.onCancelStream()
                }
            }
        )
    }

    func didFinishLoading() {
        lock.lock()
        guard !hasCompleted else { lock.unlock(); return }
        hasCompleted = true
        lock.unlock()
        // 若最后一个 dataFrame 已经以 isComplete:true 发出（isLast=true 路径），
        // 此处调用会是在 connection 关闭后，直接忽略即可。
        connection.send(content: nil, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in })
    }

    func didFail(with error: Error) {
        print("❌ [RangeStreamDelegate] 流失败: \(error)")
        markCompleted()
        connection.cancel()
    }

    private func markCompleted() {
        lock.lock()
        defer { lock.unlock() }
        hasCompleted = true
    }
}
