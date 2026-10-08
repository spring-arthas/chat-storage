//
//  RemoteDynamicRepository.swift
//  chat-storage
//
//  动态功能网络层：基于 SocketManager 帧协议的请求-响应
//

import Foundation

protocol DynamicRepository: Sendable {
    func create(_ request: DynamicCreateRequest) async throws -> DynamicCreateResult
    func timeline(scope: DynamicTimelineScope, beforeId: Int64?, limit: Int) async throws -> DynamicTimelinePage
    func action(dynamicId: Int64, action: DynamicAction) async throws -> DynamicActionResult
    func detail(dynamicId: Int64, beforeReplyId: Int64?, limit: Int) async throws -> DynamicPostDetail
    func delete(dynamicId: Int64) async throws
}

enum DynamicRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case server(message: String, code: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message, _):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "动态操作失败" : normalized
        case .invalidResponse:
            return "动态操作失败"
        }
    }
}

actor RemoteDynamicRepository: DynamicRepository {
    private let socketManager: SocketManager
    private let timeout: TimeInterval

    init(socketManager: SocketManager, timeout: TimeInterval = 15.0) {
        self.socketManager = socketManager
        self.timeout = timeout
    }

    func create(_ request: DynamicCreateRequest) async throws -> DynamicCreateResult {
        try await requestData(
            frame: try buildFrame(type: .dynamicCreateReq, payload: request),
            expecting: .dynamicCreateResp,
            as: DynamicCreateResult.self
        )
    }

    func timeline(scope: DynamicTimelineScope, beforeId: Int64?, limit: Int) async throws -> DynamicTimelinePage {
        let request = DynamicTimelineRequest(scope: scope.rawValue, beforeId: beforeId, limit: limit)
        return try await requestData(
            frame: try buildFrame(type: .dynamicTimelineReq, payload: request),
            expecting: .dynamicTimelineResp,
            as: DynamicTimelinePage.self
        )
    }

    func action(dynamicId: Int64, action: DynamicAction) async throws -> DynamicActionResult {
        let request = DynamicActionRequest(dynamicId: dynamicId, action: action.wireValue, content: action.content, parentId: action.parentId)
        return try await requestData(
            frame: try buildFrame(type: .dynamicActionReq, payload: request),
            expecting: .dynamicActionResp,
            as: DynamicActionResult.self
        )
    }

    func detail(dynamicId: Int64, beforeReplyId: Int64?, limit: Int) async throws -> DynamicPostDetail {
        let request = DynamicDetailRequest(dynamicId: dynamicId, beforeReplyId: beforeReplyId, limit: limit)
        return try await requestData(
            frame: try buildFrame(type: .dynamicDetailReq, payload: request),
            expecting: .dynamicDetailResp,
            as: DynamicPostDetail.self
        )
    }

    func delete(dynamicId: Int64) async throws {
        let response = try await socketManager.sendFrameAndWait(
            try buildFrame(type: .dynamicDeleteReq, payload: DynamicIDRequest(dynamicId: dynamicId)),
            expecting: .dynamicDeleteResp,
            timeout: timeout
        )
        let envelope: DynamicEnvelope<DynamicEmptyData> = try decodeEnvelope(response)
        try validate(envelope)
    }

    // MARK: - Private

    private func buildFrame<T: Encodable>(type: FrameTypeEnum, payload: T) throws -> Frame {
        let data = try JSONEncoder().encode(payload)
        return FrameBuilder.build(type: type, jsonData: data)
    }

    private func requestData<T: Decodable & Sendable>(
        frame: Frame,
        expecting responseType: FrameTypeEnum,
        as type: T.Type
    ) async throws -> T {
        let response = try await socketManager.sendFrameAndWait(
            frame,
            expecting: responseType,
            timeout: timeout
        )
        let envelope: DynamicEnvelope<T> = try decodeEnvelope(response)
        try validate(envelope)
        guard let data = envelope.data else { throw DynamicRepositoryError.invalidResponse }
        return data
    }

    private func decodeEnvelope<T: Decodable & Sendable>(_ frame: Frame) throws -> DynamicEnvelope<T> {
        do {
            return try JSONDecoder().decode(DynamicEnvelope<T>.self, from: frame.data)
        } catch {
            throw DynamicRepositoryError.invalidResponse
        }
    }

    private func validate<T>(_ envelope: DynamicEnvelope<T>) throws {
        guard envelope.isSuccess else {
            throw DynamicRepositoryError.server(message: envelope.message, code: envelope.errorCode)
        }
    }
}

// MARK: - Request Types

private struct DynamicTimelineRequest: Encodable, Sendable {
    let scope: String
    let beforeId: Int64?
    let limit: Int
}

private struct DynamicActionRequest: Encodable, Sendable {
    let dynamicId: Int64
    let action: String
    let content: String?
    let parentId: Int64?
}

private struct DynamicDetailRequest: Encodable, Sendable {
    let dynamicId: Int64
    let beforeReplyId: Int64?
    let limit: Int
}

private struct DynamicIDRequest: Encodable, Sendable {
    let dynamicId: Int64
}

private struct DynamicEmptyData: Decodable, Sendable {}

// MARK: - Response Envelope

private struct DynamicEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool?
    let code: Int
    let message: String
    let errorCode: String?
    let data: T?

    var isSuccess: Bool { success ?? (code == 200) }

    private enum CodingKeys: String, CodingKey {
        case success
        case code
        case message
        case msg
        case errorCode
        case data
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decodeIfPresent(Bool.self, forKey: .success)
        code = try values.decodeIfPresent(Int.self, forKey: .code) ?? (success == true ? 200 : 400)
        message = try values.decodeIfPresent(String.self, forKey: .message)
            ?? values.decodeIfPresent(String.self, forKey: .msg)
            ?? ""
        errorCode = try values.decodeIfPresent(String.self, forKey: .errorCode)
        data = try values.decodeIfPresent(T.self, forKey: .data)
    }
}
