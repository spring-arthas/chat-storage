import Foundation

struct VideoPlayInfo: Decodable {
    let playUrl: URL
    let fileId: Int64
    let fileSize: Int64
    let mimeType: String
    let expiresIn: Int
    let playable: Bool
}

final class VideoPlaybackService {
    static let shared = VideoPlaybackService()

    private let authenticationService: AuthenticationService
    private let session: URLSession
    private let playUrlEndpointBase = URL(string: "http://localhost:10188/media/play-url")!
    private let seekEndpointBase = URL(string: "http://localhost:10188/media/seek")!

    init(
        authenticationService: AuthenticationService = .shared,
        session: URLSession = .shared
    ) {
        self.authenticationService = authenticationService
        self.session = session
    }

    func requestPlayUrl(fileId: Int64, sessionId: String? = nil) async throws -> VideoPlayInfo {
        let userName = authenticationService.currentUser?.username ?? "default"
        let url = try buildPlayUrlRequest(fileId: fileId, userName: userName, sessionId: sessionId)
        let (data, response) = try await session.data(from: url)

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
        return info
    }

    func notifySeek(fileId: Int64, sessionId: String, targetSeconds: Double) async {
        do {
            let userName = authenticationService.currentUser?.username ?? "default"
            let url = try buildSeekRequest(
                fileId: fileId,
                userName: userName,
                sessionId: sessionId,
                targetSeconds: targetSeconds
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 1
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

    private func buildPlayUrlRequest(fileId: Int64, userName: String, sessionId: String?) throws -> URL {
        let base = playUrlEndpointBase.appendingPathComponent(String(fileId))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "userName", value: userName)
        ]
        if let sessionId, !sessionId.isEmpty {
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw VideoPlaybackError.invalidPlayUrl
        }
        return url
    }

    private func buildSeekRequest(
        fileId: Int64,
        userName: String,
        sessionId: String,
        targetSeconds: Double
    ) throws -> URL {
        let base = seekEndpointBase.appendingPathComponent(String(fileId))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "userName", value: userName),
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "targetSeconds", value: String(format: "%.3f", targetSeconds))
        ]
        guard let url = components?.url else {
            throw VideoPlaybackError.invalidPlayUrl
        }
        return url
    }
}

private struct VideoPlayResponse: Decodable {
    let code: Int
    let message: String
    let data: VideoPlayInfo?
}

enum VideoPlaybackError: LocalizedError {
    case invalidPlayUrl
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlayUrl:
            return "播放地址无效"
        case .invalidResponse:
            return "播放服务响应无效"
        case .serverError(let message):
            return message
        }
    }
}
