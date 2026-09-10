import AVFoundation
import Foundation

struct VideoPlayInfo: Decodable {
    let playUrl: URL
    let fileId: Int64
    let fileSize: Int64
    let mimeType: String
    let expiresIn: Int
    let playable: Bool
}

// [修改] 媒体端口当前为 HTTP，只接受服务端明文播放地址。
final class PlainMediaAsset: @unchecked Sendable {
    let asset: AVURLAsset

    init?(url: URL) {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty else {
            return nil
        }

        asset = AVURLAsset(url: url)
    }

    func makePlayer() -> AVPlayer {
        AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }
}

final class VideoPlaybackService {
    static let shared = VideoPlaybackService()

    private let authenticationService: AuthenticationService
    private let session: URLSession
    private let endpointProvider: () -> ServerEndpoint

    init(
        authenticationService: AuthenticationService = .shared,
        session: URLSession? = nil,
        endpointProvider: @escaping () -> ServerEndpoint = {
            let (host, controlPort) = SocketManager.shared.getCurrentServer()
            let configuration = ServerEndpointStore.resolvedConfiguration(
                for: ServerEndpoint(host: host, port: controlPort)
            )
            return ServerEndpoint(host: host, port: configuration.mediaPort)
        }
    ) {
        self.authenticationService = authenticationService
        self.session = session ?? Self.makePlainSession()
        self.endpointProvider = endpointProvider
    }

    private static func makePlainSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    func requestPlayUrl(fileId: Int64, sessionId: String? = nil) async throws -> VideoPlayInfo {
        let endpoint = endpointProvider()
        let transferToken = try currentTransferToken()
        let url = try buildPlayUrlRequest(fileId: fileId, sessionId: sessionId, endpoint: endpoint)
        var request = URLRequest(url: url)
        // [修改] 媒体接口只接受传输令牌，禁止继续用 userName 查询参数冒充身份。
        request.setValue("Bearer \(transferToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoPlaybackError.invalidResponse
        }

        let wrapper = try JSONDecoder().decode(VideoPlayResponse.self, from: data)
        guard httpResponse.statusCode == 200 else {
            throw VideoPlaybackError.serverError(wrapper.message)
        }
        guard wrapper.code == 200, let info = wrapper.data else {
            throw VideoPlaybackError.serverError(wrapper.message)
        }
        guard info.playable else {
            throw VideoPlaybackError.serverError("该文件暂不支持在线播放，请下载后播放")
        }
        return try normalize(info, endpoint: endpoint)
    }

    func notifySeek(fileId: Int64, sessionId: String, targetSeconds: Double) async {
        do {
            let endpoint = endpointProvider()
            let transferToken = try currentTransferToken()
            let url = try buildSeekRequest(
                fileId: fileId,
                sessionId: sessionId,
                targetSeconds: targetSeconds,
                endpoint: endpoint
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 1
            // [修改] Seek 与播放地址请求必须使用同一份 Bearer 凭据。
            request.setValue("Bearer \(transferToken)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 204 else {
                print("⚠️ [VideoPlaybackService] Seek 通知未被服务端接受 fileId=\(fileId)")
                return
            }
        } catch is CancellationError {
            // 播放窗口关闭或切换文件时取消通知，属于正常生命周期。
        } catch {
            print("⚠️ [VideoPlaybackService] Seek 通知失败，继续本地跳转 fileId=\(fileId) error=\(error.localizedDescription)")
        }
    }

    private func buildPlayUrlRequest(
        fileId: Int64,
        sessionId: String?,
        endpoint: ServerEndpoint
    ) throws -> URL {
        var components = try endpointComponents(endpoint: endpoint, path: "/media/play-url/\(fileId)")
        var queryItems: [URLQueryItem] = []
        if let sessionId, !sessionId.isEmpty {
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw VideoPlaybackError.invalidPlayUrl
        }
        return url
    }

    private func buildSeekRequest(
        fileId: Int64,
        sessionId: String,
        targetSeconds: Double,
        endpoint: ServerEndpoint
    ) throws -> URL {
        var components = try endpointComponents(endpoint: endpoint, path: "/media/seek/\(fileId)")
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "targetSeconds", value: String(format: "%.3f", targetSeconds))
        ]
        guard let url = components.url else {
            throw VideoPlaybackError.invalidPlayUrl
        }
        return url
    }

    private func endpointComponents(endpoint: ServerEndpoint, path: String) throws -> URLComponents {
        let host = endpoint.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty, endpoint.port > 0, endpoint.port <= UInt32(UInt16.max) else {
            throw VideoPlaybackError.invalidPlayUrl
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(endpoint.port)
        components.path = path
        return components
    }

    private func currentTransferToken() throws -> String {
        let token = authenticationService.currentUser?.transferToken?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            throw VideoPlaybackError.missingCredential
        }
        return token
    }

    private func normalize(_ info: VideoPlayInfo, endpoint: ServerEndpoint) throws -> VideoPlayInfo {
        guard var components = URLComponents(url: info.playUrl, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http",
              let responseHost = components.host?.lowercased() else {
            throw VideoPlaybackError.invalidPlayUrl
        }

        // [修改] 服务端返回 localhost 时替换成当前配置主机，避免播放器请求用户自己的 Mac。
        if ["localhost", "127.0.0.1", "::1"].contains(responseHost) {
            let configuredHost = endpoint.host
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard !configuredHost.isEmpty else { throw VideoPlaybackError.invalidPlayUrl }
            components.host = configuredHost
            if components.port == nil {
                components.port = Int(endpoint.port)
            }
        }

        guard let normalizedURL = components.url else {
            throw VideoPlaybackError.invalidPlayUrl
        }
        return VideoPlayInfo(
            playUrl: normalizedURL,
            fileId: info.fileId,
            fileSize: info.fileSize,
            mimeType: info.mimeType,
            expiresIn: info.expiresIn,
            playable: info.playable
        )
    }
}

private struct VideoPlayResponse: Decodable {
    let code: Int
    let message: String
    let data: VideoPlayInfo?
}

enum VideoPlaybackError: LocalizedError, Equatable {
    case invalidPlayUrl
    case invalidResponse
    case missingCredential
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlayUrl:
            return "播放地址无效"
        case .invalidResponse:
            return "播放服务响应无效"
        case .missingCredential:
            return "文件传输凭证无效，请重新登录"
        case .serverError(let message):
            return message
        }
    }
}
