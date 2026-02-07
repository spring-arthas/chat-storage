//
//  VideoPlayerView.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let params: VideoPlayerParams
    
    @EnvironmentObject var socketManager: SocketManager
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var progress: Double = 0.0
    @State private var errorMessage: String?
    
    // 独立的 DirectoryService Used for download tasks
    @State private var directoryService: DirectoryService?
    
    // Resource Loader Keep alive
    @State private var resourceLoader: VideoResourceLoader?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Unable to play video")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Button("Retry") {
                        errorMessage = nil
                        startStreaming()
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .accentColor(.white)
                    
                    Text("Loading video stream...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Button("Cancel") {
                        // Close window? Currently cannot directly close window, only show cancel state
                        // actual scenario, closing window destroys View, disconnecting (deinit)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            startStreaming()
        }
    }
    
    private func startStreaming() {
        isLoading = true
        progress = 0.0
        
        // 1. Initialize Independent Socket Service
        let newSocket = SocketManager()
        let (host, _) = socketManager.getCurrentServer() // Keep host, ignore current port
        // User requested Port 10088 for streaming download
        newSocket.switchConnection(host: host, port: 10088)
        
        self.directoryService = DirectoryService(socketManager: newSocket)
        
        // 2. Wait for connection (Simple polling)
        Task {
            do {
                var attempts = 0
                while newSocket.connectionState != .connected && attempts < 50 { // 5s
                    try await Task.sleep(nanoseconds: 100_000_000)
                    attempts += 1
                }
                
                if newSocket.connectionState != .connected {
                    throw DirectoryError.serverError(code: -1, message: "Connection failed")
                }
                
                guard let service = directoryService else { return }
                
                // 3. Initialize Resource Loader
                let loader = VideoResourceLoader(directoryService: service, fileId: params.fileId)
                self.resourceLoader = loader // Hold reference
                
                // 4. Create AVAsset with custom scheme
                // The URL doesn't matter much as long as scheme is custom, but we use valid format
                let customUrl = URL(string: "chat-storage-stream://video-\(params.fileId)")!
                let asset = AVURLAsset(url: customUrl)
                asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
                
                // 5. Create Player Item & Player
                let item = AVPlayerItem(asset: asset)
                
                await MainActor.run {
                    self.player = AVPlayer(playerItem: item)
                    self.isLoading = false
                    self.player?.play()
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

//
//  VideoPlayerParams.swift
//  chat-storage
//
//  Created by HLJY on 2026/2/7.
//

import Foundation

/// Video Player Parameters
struct VideoPlayerParams: Codable, Hashable {
    let fileId: Int64
    let fileName: String
}

// MARK: - VideoResourceLoader

/// 视频资源加载器 - 负责对接 AVPlayer 和 Socket 下载流
class VideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    
    // MARK: - Properties
    
    private let directoryService: DirectoryService
    private let fileId: Int64
    private var downloadTask: Task<Void, Error>?
    
    // 积压的加载请求 (来自 AVPlayer)
    private var pendingRequests = [AVAssetResourceLoadingRequest]()
    
    // 缓存数据 (生产环境建议使用文件映射或更高效的缓存结构)
    private var downloadedData = Data()
    private var totalSize: Int64 = 0
    private var startOffset: Int64 = 0
    private var mimeType: String = "video/mp4"
    private var isInfoReceived = false
    private var isDownloadFinished = false
    
    private let queue = DispatchQueue(label: "com.chatstorage.videoloader")
    
    // MARK: - Init
    
    init(directoryService: DirectoryService, fileId: Int64) {
        self.directoryService = directoryService
        self.fileId = fileId
    }
    
    deinit {
        downloadTask?.cancel()
    }
    
    // MARK: - AVAssetResourceLoaderDelegate
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 保存请求
            self.pendingRequests.append(loadingRequest)
            
            // 2. 如果还没开始下载，启动 Socket 任务
            if self.downloadTask == nil {
                self.startSocketDownload()
            }
            
            // 3. 尝试处理积压请求
            self.processLoadingRequests()
        }
        
        return true // 告诉播放器：请等待，我们会手动处理
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if let index = self.pendingRequests.firstIndex(of: loadingRequest) {
                self.pendingRequests.remove(at: index)
            }
        }
    }
    
    // MARK: - Logic
    
    private func startSocketDownload() {
        print("🚀 [Loader] 启动流式下载任务")
        
        downloadTask = Task {
            do {
                _ = try await directoryService.startStreamDownload(fileId: fileId, delegate: self)
                print("✅ [Loader] 任务正常结束")
            } catch {
                print("❌ [Loader] 任务失败: \(error)")
                self.didFail(with: error)
            }
        }
    }
    
    private func processLoadingRequests() {
        // 必须在 queue 中执行
        
        // 过滤掉已完成或取消的请求
        pendingRequests.removeAll { request in
            if request.isFinished { return true }
            if request.isCancelled { return true }
            return false
        }
        
        for request in pendingRequests {
            var shouldFinish = false
            
            // 1. 处理 ContentInfoRequest (元数据)
            if let contentInfoRequest = request.contentInformationRequest {
                // 如果已收到 metaFrame，填充信息
                if totalSize > 0 {
                    contentInfoRequest.contentType = self.mimeType
                    contentInfoRequest.contentLength = self.totalSize
                    contentInfoRequest.isByteRangeAccessSupported = true
                    isInfoReceived = true
                    
                    // 如果请求仅需 ContentInfo，不需要 Data，则可以结束
                    if request.dataRequest == nil {
                        shouldFinish = true
                    }
                }
            }
            
            // 2. 处理 DataRequest (数据)
            if let dataRequest = request.dataRequest {
                let requestedOffset = Int64(dataRequest.requestedOffset)
                let requestedLength = Int64(dataRequest.requestedLength)
                let currentOffset = dataRequest.currentOffset
                
                let downloadedLength = Int64(downloadedData.count)
                
                // 只有当有数据时才尝试响应
                if downloadedLength > 0 && currentOffset < downloadedLength {
                    let availableLength = downloadedLength - currentOffset
                    let bytesNeeded = (requestedOffset + requestedLength) - currentOffset
                    
                    // 关键修改: 如果请求的数据还没下载到，不要响应部分数据然后直接结束
                    // 对于 MP4 头部移到了尾部的情况 (MOOV atom)，AVPlayer 会请求文件末尾
                    // 我们只需提供当前有的数据，但因数据不足，不能 finishLoading，让 AVPlayer 等待
                    
                    let bytesCanProvide = min(availableLength, bytesNeeded)
                    
                    if bytesCanProvide > 0 {
                        let rangeStart = Int(currentOffset)
                        let rangeEnd = rangeStart + Int(bytesCanProvide)
                        
                        // 边界检查
                        if rangeStart < downloadedData.count && rangeEnd <= downloadedData.count {
                            let dataChunk = downloadedData.subdata(in: rangeStart..<rangeEnd)
                            dataRequest.respond(with: dataChunk)
                            print("📦 [Loader] 响应数据: Offset \(currentOffset) Size \(dataChunk.count)")
                        }
                        
                        // 检查是否已满足请求长度
                        // 注意：respond 后 currentOffset 会自动增加
                        if (currentOffset + bytesCanProvide) >= (requestedOffset + requestedLength) {
                            shouldFinish = true
                        }
                    }
                }
                
                // 特殊情况处理：如果文件已全部下载完成
                if isDownloadFinished && !shouldFinish {
                     // 如果已经下载完，且 currentOffset 已经到了此时缓冲区的末尾（无论是否满请求长度），都应结束
                     // 因为不可能再有新数据了
                     if currentOffset >= downloadedLength {
                         shouldFinish = true
                     } else {
                         // 还有剩余数据没读完（理论上上面的 if 块会处理），让下次循环继续
                     }
                }
            }
            
            // 3. 完成请求
            if shouldFinish {
                request.finishLoading()
            }
        }
        
        // 再次清理
        pendingRequests.removeAll { $0.isFinished }
    }
}

// MARK: - VideoStreamLoaderDelegate Implementation

extension VideoResourceLoader: VideoStreamLoaderDelegate {
    
    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {
        queue.async { [weak self] in
            self?.totalSize = totalSize
            self?.mimeType = mimeType
            self?.processLoadingRequests()
        }
    }
    
    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        queue.async { [weak self] in
            self?.downloadedData.append(data)
            self?.processLoadingRequests()
        }
    }
    
    func didFinishLoading() {
        queue.async { [weak self] in
            guard let self = self else { return }
            print("🏁 [Loader] 所有数据接收完毕")
            self.isDownloadFinished = true
            self.processLoadingRequests()
            
            // 下面的强制结束逻辑移到 processLoadingRequests 中统一处理
            // self.pendingRequests.forEach { $0.finishLoading() }
            // self.pendingRequests.removeAll()
        }
    }
    
    func didFail(with error: Error) {
        queue.async { [weak self] in
            self?.pendingRequests.forEach { $0.finishLoading(with: error) }
            self?.pendingRequests.removeAll()
        }
    }
}
