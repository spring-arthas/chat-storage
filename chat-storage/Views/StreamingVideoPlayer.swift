import SwiftUI
import AVKit
import Network

/// SwiftUI 包装的视频播放界面
struct StreamingVideoPlayer: View {
    let fileId: Int64
    let fileName: String
    let fileSize: Int64
    
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = StreamingVideoViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    viewModel.stopPlaying()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(VisualEffectBlur(material: .headerView, blendingMode: .withinWindow))
            
            Divider()
            
            // Player
            ZStack {
                Color.black
                
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                }
                
                if viewModel.isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("缓冲中...")
                            .foregroundColor(.white)
                            .padding(.top, 10)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                }
                
                if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 40))
                        Text("播放失败")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Button("重试") {
                            viewModel.setupPlayer(fileId: fileId, expectedSize: fileSize)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            viewModel.setupPlayer(fileId: fileId, expectedSize: fileSize)
        }
        .onDisappear {
            viewModel.stopPlaying()
        }
    }
}

// MARK: - ViewModel

class StreamingVideoViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    
    // 我们必须保留对 loader delegate 的强引用，否则 delegate 会被释放
    private var resourceLoaderDelegate: CustomResourceLoaderDelegate?
    private var timeObserverToken: Any?
    
    // 初始化并构建 AVPlayer
    func setupPlayer(fileId: Int64, expectedSize: Int64) {
        self.isLoading = true
        self.errorMessage = nil
        self.player?.pause()
        self.player = nil
        
        // 构建伪造的 URL
        guard let url = URL(string: "cloudstream://video/\(fileId).mp4") else {
            self.errorMessage = "无效的视频URL"
            return
        }
        
        let asset = AVURLAsset(url: url)
        
        // 创建 ResourceLoaderDelegate
        let delegate = CustomResourceLoaderDelegate(fileId: fileId, expectedSize: expectedSize)
        self.resourceLoaderDelegate = delegate
        
        // 设置 Delegate 来拦截请求 (必须使用独立的 DispatchQueue)
        let queue = DispatchQueue(label: "com.cloud-drive.video-stream")
        asset.resourceLoader.setDelegate(delegate, queue: queue)
        
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // 观察状态变化以更新缓冲 UI
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new, .initial], context: nil)
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        self.player = player
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            if keyPath == "timeControlStatus", let player = self.player {
                self.isLoading = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            } else if keyPath == "status", let item = object as? AVPlayerItem {
                if item.status == .failed {
                    self.errorMessage = item.error?.localizedDescription ?? "播放器加载失败"
                    self.isLoading = false
                }
            }
        }
    }
    
    func stopPlaying() {
        if let player = player {
            player.pause()
            player.removeObserver(self, forKeyPath: "timeControlStatus")
            if let currentItem = player.currentItem {
                currentItem.removeObserver(self, forKeyPath: "status")
            }
        }
        player = nil
        // Cancel loading logic
        resourceLoaderDelegate?.cancelAll()
        resourceLoaderDelegate = nil
    }
    
    deinit {
        stopPlaying()
    }
}

// MARK: - Custom Resource Loader Delegate

class CustomResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    
    private let fileId: Int64
    private let expectedSize: Int64
    
    // 保存正在处理的请求
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    
    // 当前的活跃任务
    private var activeTaskInfo: RequestTaskInfo?
    
    init(fileId: Int64, expectedSize: Int64) {
        self.fileId = fileId
        self.expectedSize = expectedSize
        super.init()
    }
    
    // MARK: - AVAssetResourceLoaderDelegate Methods
    
    /// 当播放器需要数据时调用
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        print("▶️ [ResourceLoader] Received request: offset=\(loadingRequest.dataRequest?.requestedOffset ?? 0), length=\(loadingRequest.dataRequest?.requestedLength ?? 0)")
        
        pendingRequests.append(loadingRequest)
        processPendingRequests()
        
        return true
    }
    
    /// 当播放器取消某次数据请求时调用 (例如快进/快退/拖动进度条)
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        print("⏹ [ResourceLoader] Cancelled request: offset=\(loadingRequest.dataRequest?.requestedOffset ?? 0)")
        
        if let index = pendingRequests.firstIndex(of: loadingRequest) {
            pendingRequests.remove(at: index)
        }
        
        // 如果取消的是当前正在执行的请求，则中止当前的 Socket 任务
        if let currentInfo = activeTaskInfo, currentInfo.request == loadingRequest {
            print("⏹ [ResourceLoader] 正在中止活跃任务")
            currentInfo.isCancelled = true
            activeTaskInfo = nil
            // 稍等重新处理剩余请求
            processPendingRequests()
        }
    }
    
    // MARK: - Internal Processing
    
    private func processPendingRequests() {
        // 如果当前有任务正在执行且未被取消，就等待它完成
        if let current = activeTaskInfo, !current.isCancelled {
            // 但如果发现有一个请求的 offset 发生极大的跳跃，AVPlayer 会下发新的 LoadingRequest 并调用 didCancel 取消旧的，
            // 上面的 didCancel 已经负责清理 current 任务。
            return
        }
        
        guard let request = pendingRequests.first else { return }
        
        guard let dataRequest = request.dataRequest else {
            request.finishLoading()
            pendingRequests.removeFirst()
            return
        }
        
        // 填充 Content Information，让播放器知道大文件的总长度
        if let contentInfoRequest = request.contentInformationRequest {
            contentInfoRequest.contentType = "public.mpeg-4"
            contentInfoRequest.contentLength = expectedSize
            contentInfoRequest.isByteRangeAccessSupported = true
        }
        
        let requestedOffset = dataRequest.requestedOffset
        let requestedLength = Int64(dataRequest.requestedLength)
        
        print("🚀 [ResourceLoader] Start streaming for Offset: \(requestedOffset), length: \(requestedLength)")
        
        let taskInfo = RequestTaskInfo(request: request)
        self.activeTaskInfo = taskInfo
        
        // 使用 Task 启动网络请求
        Task {
            do {
                guard let ds = await self.getDirectoryService() else {
                    throw NSError(domain: "DirectoryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 Directory Service"])
                }
                
                try await ds.startCustomVideoStreaming(fileId: self.fileId, startOffset: requestedOffset, delegate: taskInfo)
                
            } catch {
                print("❌ [ResourceLoader] Socket 流式请求报错: \(error)")
                if !taskInfo.isCancelled {
                    request.finishLoading(with: error)
                    self.finishCurrentRequest(taskInfo)
                }
            }
        }
    }
    
    private func finishCurrentRequest(_ info: RequestTaskInfo) {
        if self.activeTaskInfo === info {
            self.activeTaskInfo = nil
            if let index = self.pendingRequests.firstIndex(of: info.request) {
                self.pendingRequests.remove(at: index)
            }
            // 接着处理下一个
            self.processPendingRequests()
        }
    }
    
    func cancelAll() {
        activeTaskInfo?.isCancelled = true
        for req in pendingRequests {
            req.finishLoading()
        }
        pendingRequests.removeAll()
        activeTaskInfo = nil
    }
    
    @MainActor
    private func getDirectoryService() -> DirectoryService? {
        return SocketManager.shared.directoryService
    }
}

// MARK: - Task Info Holder
class RequestTaskInfo: VideoStreamLoaderDelegate {
    let request: AVAssetResourceLoadingRequest
    var isCancelled = false
    
    init(request: AVAssetResourceLoadingRequest) {
        self.request = request
    }
    
    func didReceiveContentInfo(totalSize: Int64, mimeType: String) {
        guard !isCancelled else { return }
        if let contentInfoRequest = request.contentInformationRequest {
            contentInfoRequest.contentType = "public.mpeg-4"
            contentInfoRequest.contentLength = totalSize
            contentInfoRequest.isByteRangeAccessSupported = true
        }
    }
    
    func didReceiveVideoData(_ data: Data, range: Range<Int64>) {
        guard !isCancelled else { return }
        request.dataRequest?.respond(with: data)
        
        // 如果已经响应了所有请求的长度，则结束请求
        if let dataRequest = request.dataRequest {
            if dataRequest.currentOffset >= dataRequest.requestedOffset + Int64(dataRequest.requestedLength) {
                print("✅ [ResourceLoader] AVPlayer 请求的数据长度已经满足，提前完成")
                request.finishLoading()
                isCancelled = true // 阻止后续回调
            }
        }
    }
    
    func didFinishLoading() {
        guard !isCancelled else { return }
        print("✅ [ResourceLoader] 服务端所有数据发送完成")
        request.finishLoading()
        isCancelled = true
    }
    
    func didFail(with error: Error) {
        guard !isCancelled else { return }
        print("❌ [ResourceLoader] 发生错误: \(error)")
        request.finishLoading(with: error)
        isCancelled = true
    }
}
