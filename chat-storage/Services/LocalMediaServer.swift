import Foundation
import Network

/// 一个极简的本地 HTTP 视频代理服务器
/// 仅用于拦截 AVPlayer 的 Range 请求，并转化为 Socket 帧向远端拉取数据
class LocalMediaServer {
    static let shared = LocalMediaServer()
    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private let directoryService = VideoStreamingService(socketManager: SocketManager.shared)
    
    // Active connections
    private var connections: [NWConnection] = []
    
    init() {}
    
    /// 获取当前挂载的本地 URL
    func getStreamURL(for fileId: Int64, fileSize: Int64) -> URL? {
        guard let port = serverPort() else { return nil }
        // 构造虚拟的 http 地址交给 AVPlayer
        return URL(string: "http://127.0.0.1:\(port)/stream?fileId=\(fileId)&size=\(fileSize)")
    }
    
    private func serverPort() -> Int? {
        if let p = port?.rawValue { return Int(p) }
        startSync() // 确保启动
        return port.flatMap { Int($0.rawValue) }
    }
    
    func startSync() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        do {
            listener = try NWListener(using: parameters)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener?.start(queue: .global(qos: .userInteractive))
            
            // Wait briefly for port to be assigned
            var attempts = 0
            while listener?.port == nil && attempts < 10 {
                Thread.sleep(forTimeInterval: 0.1)
                attempts += 1
            }
            port = listener?.port
            if let p = port {
                print("✅ [LocalMediaServer] started on port \(p)")
            }
        } catch {
            print("❌ [LocalMediaServer] failed to start: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        print("🛑 [LocalMediaServer] stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .global(qos: .userInteractive))
        receiveHTTPHeaders(on: connection)
    }
    
    private func receiveHTTPHeaders(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }
            if let requestString = String(data: data, encoding: .utf8) {
                print("📥 [LocalMediaServer] Receive Request:\n\(requestString)")
                self.processRequest(requestString, on: connection)
            } else {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ request: String, on connection: NWConnection) {
        // 1. 解析 Request Line
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        
        // 格式: GET /stream?fileId=123&size=456 HTTP/1.1
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[1].starts(with: "/stream") else {
            // 返回 404
            let response = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
            sendResponse(response.data(using: .utf8)!, on: connection, closeAfter: true)
            return
        }
        
        let path = parts[1]
        guard let urlComponents = URLComponents(string: path) else {
            connection.cancel()
            return
        }
        
        // 2. 提取参数 fileId 和 size
        guard let fileIdStr = urlComponents.queryItems?.first(where: { $0.name == "fileId" })?.value,
              let fileId = Int64(fileIdStr),
              let sizeStr = urlComponents.queryItems?.first(where: { $0.name == "size" })?.value,
              let totalSize = Int64(sizeStr) else {
            connection.cancel()
            return
        }
        
        // 3. 解析 Range: bytes=X-Y
        var startOffset: Int64 = 0
        var isPartial = false
        for line in lines {
            if line.lowercased().starts(with: "range: bytes=") {
                let rangeStr = line.dropFirst("Range: bytes=".count)
                let rangeParts = rangeStr.components(separatedBy: "-")
                if let startStr = rangeParts.first, let start = Int64(startStr) {
                    startOffset = start
                    isPartial = true
                }
                break
            }
        }
        
        // 4. 返回 HTTP 头部
        let endOffset = totalSize - 1
        let contentLength = totalSize - startOffset
        
        var header = ""
        if isPartial {
            header += "HTTP/1.1 206 Partial Content\r\n"
            header += "Content-Range: bytes \(startOffset)-\(endOffset)/\(totalSize)\r\n"
        } else {
            header += "HTTP/1.1 200 OK\r\n"
        }
        
        header += "Accept-Ranges: bytes\r\n"
        header += "Content-Type: video/mp4\r\n" // 简单假设为 MP4，理论上需要从文件后缀取
        header += "Content-Length: \(contentLength)\r\n"
        header += "Connection: keep-alive\r\n\r\n"
        
        print("📤 [LocalMediaServer] Sending Header:\n\(header)")
        connection.send(content: header.data(using: .utf8)!, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ [LocalMediaServer] send header error: \(error)")
                connection.cancel()
            } else {
                // 5. 触发 Socket 拉取视频流数据！
                self.streamVideoData(fileId: fileId, startOffset: startOffset, to: connection)
            }
        }))
    }
    
    private func streamVideoData(fileId: Int64, startOffset: Int64, to connection: NWConnection) {
        // 创建一个单独的任务去拉取
        Task {
            do {
                let delegate = NWConnectionVideoStreamDelegate(connection: connection)
                // Need to use an isolated socket manager or the shared one carefully.
                // Assuming directoryService.startVideoStreaming is async and returns when finished.
                try await directoryService.startCustomVideoStreaming(fileId: fileId, startOffset: startOffset, delegate: delegate)
            } catch {
                print("❌ [LocalMediaServer] Socket Streaming failed: \(error)")
                connection.cancel()
            }
        }
    }
    private func sendResponse(_ data: Data, on connection: NWConnection, closeAfter: Bool) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("❌ [LocalMediaServer] send error: \(error)")
            }
            if closeAfter { connection.cancel() }
        })
    }
}

/// 代理协议用于向 HTTP Connection 中不断塞入数据
class NWConnectionVideoStreamDelegate: VideoStreamLoaderDelegate {
    private let connection: NWConnection
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {
        // 头部已经在外部拼接好发送了这里忽略
    }
    
    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        // 向 connection 中写入真实视频片段
        connection.send(content: data, completion: .contentProcessed({ error in
             if let e = error {
                 print("⚠️ [LocalMediaServer] fail to write data chunk to player: \(e)")
                 self.connection.cancel()
             }
        }))
    }
    
    func didFinishLoading() {
        print("🏁 [LocalMediaServer] All data sent to player.")
        // Do not explicitly close, AVPlayer sometimes re-uses keep-alive
    }
    
    func didFail(with error: Error) {
        print("❌ [LocalMediaServer] stream failure delegate: \(error)")
        connection.cancel()
    }
}
