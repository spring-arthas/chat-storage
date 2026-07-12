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
    private let playUrlEndpointBase = URL(string: "http://172.21.33.149:10188/media/play-url")!

    init(
        authenticationService: AuthenticationService = .shared,
        session: URLSession = .shared
    ) {
        self.authenticationService = authenticationService
        self.session = session
    }

    func requestPlayUrl(fileId: Int64) async throws -> VideoPlayInfo {
        let userName = authenticationService.currentUser?.username ?? "default"
        let url = try buildPlayUrlRequest(fileId: fileId, userName: userName)
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

    private func buildPlayUrlRequest(fileId: Int64, userName: String) throws -> URL {
        let base = playUrlEndpointBase.appendingPathComponent(String(fileId))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "userName", value: userName)
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
