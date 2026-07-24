//
//  ChatAttachmentTransferCoordinator.swift
//  chat-storage
//

import Foundation

/// 聊天附件后台批次协调器。
/// - 同一 clientMsgId 的首次上传与重传严格串行。
/// - 不同消息批次有限并发，每个活跃批次由上传会话独占一条 10087 连接。
/// - 该协调器不持有聊天输入草稿状态，因此不会锁定输入框。
@MainActor
final class ChatAttachmentTransferCoordinator {
    static let shared = ChatAttachmentTransferCoordinator()

    typealias Operation = @MainActor () async -> Void

    private struct Job {
        let requestId: String
        let operation: Operation
    }

    private let maxConcurrentBatches: Int
    private var queuedJobs: [String: [Job]] = [:]
    private var batchOrder: [String] = []
    private var activeBatchIds: Set<String> = []
    private var activeRequestIds: [String: String] = [:]

    init(maxConcurrentBatches: Int = 2) {
        self.maxConcurrentBatches = max(1, maxConcurrentBatches)
    }

    /// 清理缓存时用于保护已经排队或正在执行的聊天附件批次。
    var hasPendingOrActiveJobs: Bool {
        !activeBatchIds.isEmpty || queuedJobs.values.contains { !$0.isEmpty }
    }

    func enqueue(
        batchId: String,
        requestId: String,
        operation: @escaping Operation
    ) {
        let alreadyQueued = queuedJobs[batchId]?.contains { $0.requestId == requestId } == true
        guard !alreadyQueued else { return }

        queuedJobs[batchId, default: []].append(Job(requestId: requestId, operation: operation))
        if !batchOrder.contains(batchId) {
            batchOrder.append(batchId)
        }
        drain()
    }

    func cancelQueued(batchId: String) {
        queuedJobs.removeValue(forKey: batchId)
        batchOrder.removeAll { $0 == batchId }
    }

    private func drain() {
        while activeBatchIds.count < maxConcurrentBatches,
              let batchId = batchOrder.first(where: {
                  !activeBatchIds.contains($0) && !(queuedJobs[$0]?.isEmpty ?? true)
              }) {
            startNextJob(batchId: batchId)
        }
    }

    private func startNextJob(batchId: String) {
        guard var jobs = queuedJobs[batchId], !jobs.isEmpty else {
            removeBatchFromQueue(batchId)
            return
        }

        let job = jobs.removeFirst()
        queuedJobs[batchId] = jobs
        activeBatchIds.insert(batchId)
        activeRequestIds[batchId] = job.requestId

        Task { [weak self] in
            await job.operation()
            self?.finishJob(batchId: batchId)
        }
    }

    private func finishJob(batchId: String) {
        activeBatchIds.remove(batchId)
        activeRequestIds.removeValue(forKey: batchId)

        if queuedJobs[batchId]?.isEmpty == false {
            startNextJob(batchId: batchId)
        } else {
            removeBatchFromQueue(batchId)
            drain()
        }
    }

    private func removeBatchFromQueue(_ batchId: String) {
        queuedJobs.removeValue(forKey: batchId)
        batchOrder.removeAll { $0 == batchId }
    }
}
