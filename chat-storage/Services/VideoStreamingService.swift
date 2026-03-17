//
//  VideoStreamingService.swift
//  chat-storage
//
//  Created by HLJY on 2026/3/17.
//

import Foundation

/// 视频流服务 — 不绑定 MainActor，可从任意 async 上下文调用
class VideoStreamingService {
    private let socketManager: SocketManager

    init(socketManager: SocketManager) {
        self.socketManager = socketManager
    }

    /// 从指定 offset 开始流式拉取视频数据
    func startCustomVideoStreaming(fileId: Int64,
                                   startOffset: Int64,
                                   delegate: VideoStreamLoaderDelegate) async throws {
        print("🎥 [Stream] 请求视频流: fileId=\(fileId) range-start=\(startOffset)")

        let taskId = UUID().uuidString

        let request: [String: Any] = [
            "fileId": fileId,
            "taskId": taskId,
            "startOffset": startOffset
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw DirectoryError.invalidData
        }

        let requestFrame = Frame(type: .metaFrame, data: requestData, flags: 0x00)
        try socketManager.sendFrame(requestFrame)

        return try await withCheckedThrowingContinuation { continuation in
            var receivedSize: Int64 = startOffset

            let types: Set<FrameTypeEnum> = [.metaFrame, .dataFrame, .endFrame, .fileResponse, .ackFrame]

            socketManager.registerStreamHandler(for: types) { [self] frame in
                switch frame.type {
                case .ackFrame, .metaFrame:
                    if let jsonString = String(data: frame.data, encoding: .utf8),
                       let data = jsonString.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                        if let status = dict["status"] as? String, (status == "error" || status == "fail") {
                            let msg = dict["message"] as? String ?? "未知错误"
                            let err = DirectoryError.serverError(code: -1, message: msg)
                            delegate.didFail(with: err)
                            continuation.resume(throwing: err)
                            return false
                        }

                        if let size = dict["fileSize"] as? Int64 {
                            delegate.didReceiveContentInfo(totalSize: size, mimeType: "video/mp4")

                            let readyAck: [String: Any] = ["taskId": taskId, "status": "ready"]
                            if let readyData = try? JSONSerialization.data(withJSONObject: readyAck) {
                                let readyFrame = Frame(type: .ackFrame, data: readyData, flags: 0x00)
                                try? self.socketManager.sendFrame(readyFrame)
                            }
                        }
                    }
                    return true

                case .dataFrame:
                    let data = frame.data
                    let range = receivedSize..<receivedSize + Int64(data.count)
                    delegate.didReceiveVideoData(data, range: range)
                    receivedSize += Int64(data.count)
                    return true

                case .endFrame:
                    print("✅ [Stream] 视频流片段发送结束")
                    delegate.didFinishLoading()
                    continuation.resume()
                    return false

                case .fileResponse:
                    if let dict = try? FrameParser.decodeAsDictionary(frame),
                       let code = dict["code"] as? Int, code != 200 {
                        let msg = dict["message"] as? String ?? "Stream Fail"
                        let error = DirectoryError.serverError(code: code, message: msg)
                        delegate.didFail(with: error)
                        continuation.resume(throwing: error)
                        return false
                    }
                    return true

                default:
                    return true
                }
            }
        }
    }
}
