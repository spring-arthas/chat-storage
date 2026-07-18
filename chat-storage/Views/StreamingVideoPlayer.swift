import SwiftUI
import AVKit
import CoreMedia

// MARK: - AVPlayerView Wrapper

/// 将 AppKit AVPlayerView 包装为 SwiftUI View，禁用内置控件以使用自定义控件层。
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - StreamingVideoPlayer

/// 视频播放界面（独立窗口版），使用自定义控件层。
struct StreamingVideoPlayer: View {
    let fileId: Int64
    let fileName: String
    let fileSize: Int64
    @ObservedObject var viewModel: StreamingVideoViewModel
    @State private var draggingProgress: Double? = nil

    var body: some View {
        ZStack {
            Color.black

            if let player = viewModel.player {
                AVPlayerViewRepresentable(player: player)
            }

            // 缓冲中提示（seek 缓冲与起播缓冲文案区分）
            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(viewModel.isSeekBuffering ? "跳转中..." : "缓冲中...")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
            }

            // 停止后的重播提示
            if viewModel.playState == .stopped {
                VStack(spacing: 12) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.8))
                    Text("已停止")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("点击播放按钮从头开始")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // 错误提示
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
                        viewModel.setupPlayer(fileId: fileId, fileName: fileName, expectedSize: fileSize)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }

            // 自定义控件层（底部）
            VStack {
                Spacer()
                controlBar
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            viewModel.setupPlayer(fileId: fileId, fileName: fileName, expectedSize: fileSize)
        }
        .onDisappear {
            viewModel.stopPlaying()
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 6) {
            // 进度条
            progressSlider

            // 按钮行
            HStack(spacing: 16) {
                // 播放 / 暂停 / 从停止恢复
                Button(action: handlePlayPause) {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading && viewModel.playState == .idle)

                // 停止按钮
                Button(action: {
                    viewModel.stopAndClearResources()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.playState == .stopped ? .gray : .white)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.playState == .stopped || viewModel.playState == .idle)

                // 时间显示
                Text(timeLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var progressSlider: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let progress = min(max(draggingProgress ?? viewModel.sliderPosition, 0), 1)
                let thumbX = max(6, min(width - 6, width * progress))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color(red: 0.23, green: 0.67, blue: 0.98))
                        .frame(width: width * progress, height: 6)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: thumbX - 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard viewModel.duration > 0, viewModel.playState != .stopped else { return }
                            let x = min(max(0, value.location.x), width)
                            draggingProgress = x / width
                        }
                        .onEnded { value in
                            guard viewModel.duration > 0, viewModel.playState != .stopped else {
                                draggingProgress = nil
                                return
                            }
                            let x = min(max(0, value.location.x), width)
                            let fraction = x / width
                            draggingProgress = nil
                            viewModel.seekToFraction(fraction)
                        }
                )
            }
            .frame(height: 18)
            .padding(.horizontal, 12)

            HStack {
                let preview = draggingProgress.map { $0 * max(viewModel.duration, 0) } ?? viewModel.currentTime
                Text(formatTime(preview))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                Text(formatTime(viewModel.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(.horizontal, 12)
        }
    }

    private var playPauseIcon: String {
        switch viewModel.playState {
        case .stopped, .idle:
            return "play.fill"
        case .paused:
            return "play.fill"
        case .playing:
            return "pause.fill"
        }
    }

    private var timeLabel: String {
        "\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))"
    }

    private func handlePlayPause() {
        switch viewModel.playState {
        case .playing:
            viewModel.pause()
        case .paused:
            viewModel.resume()
        case .stopped:
            // 从停止状态重新开始播放
            viewModel.setupPlayer(fileId: fileId, fileName: fileName, expectedSize: fileSize)
        case .idle:
            viewModel.resume()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - ViewModel

enum VideoPlayState {
    case idle       // 初始/未开始
    case playing    // 正在播放
    case paused     // 用户暂停
    case stopped    // 用户停止（资源已释放）
}

final class StreamingVideoViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var playState: VideoPlayState = .idle
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var sliderPosition: Double = 0  // 0...1，用于 Slider 绑定
    @Published var isSeekBuffering: Bool = false

    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackFinishedObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var currentFileId: Int64?
    private var fileSize: Int64 = 0
    private var setupTask: Task<Void, Never>?
    private var seekNotificationTask: Task<Void, Never>?
    private var playbackSessionId: String?
    var onPlaybackSessionTerminated: (() -> Void)?

    // seek 状态机：保证同一时间只有一个活跃 player.seek，Chase Time 防抖
    private var isSeeking = false
    private var chaseTime: CMTime = .zero
    private var isSeekInProgress: Bool = false

    // MARK: - Setup

    func setupPlayer(fileId: Int64, fileName: String, expectedSize: Int64) {
        print("🎬 [StreamingVideoPlayer] 组件启动 fileId=\(fileId) fileName=\(fileName) fileSize=\(expectedSize)")
        stopPlaying()

        currentFileId = fileId
        fileSize = expectedSize
        let sessionId = UUID().uuidString
        playbackSessionId = sessionId

        isLoading = true
        errorMessage = nil
        playState = .idle
        currentTime = 0
        duration = 0
        sliderPosition = 0

        setupTask = Task { [weak self] in
            do {
                let playInfo = try await VideoPlaybackService.shared.requestPlayUrl(
                    fileId: fileId,
                    sessionId: sessionId
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.currentFileId == fileId,
                          self.playbackSessionId == sessionId else { return }
                    self.fileSize = playInfo.fileSize
                    self.startPlayer(url: playInfo.playUrl)
                }
            } catch is CancellationError {
                // 新文件打开或窗口关闭时会取消旧请求，这是正常生命周期。
            } catch {
                await MainActor.run {
                    guard let self, self.currentFileId == fileId else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    print("❌ [StreamingVideoPlayer] 获取播放地址失败 fileId=\(fileId) error=\(error.localizedDescription)")
                }
            }
        }
    }

    private func startPlayer(url: URL) {
        print("🔗 [StreamingVideoPlayer] 资源调配完成 fileId=\(currentFileId ?? -1) playURL=\(url)")

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // 优先响应用户播放/暂停操作，避免继续播放需要较长等待
        player.automaticallyWaitsToMinimizeStalling = false

        // 观察缓冲状态
        playerStatusObservation = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let isWaiting = observedPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.isLoading = isWaiting
            }
        }

        // 观察 Item 加载状态
        itemStatusObservation = item.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.isLoading = false
                    // 获取时长
                    let dur = observedItem.duration
                    if dur.isValid && !dur.isIndefinite {
                        self.duration = dur.seconds
                    }
                    print("✅ [StreamingVideoPlayer] 播放器就绪 fileId=\(self.currentFileId ?? -1) duration=\(String(format: "%.1f", self.duration))s")
                case .failed:
                    self.isLoading = false
                    let errMsg = observedItem.error?.localizedDescription ?? "播放器加载失败"
                    self.errorMessage = errMsg
                    print("❌ [StreamingVideoPlayer] 播放器加载失败 fileId=\(self.currentFileId ?? -1) error=\(errMsg)")
                default:
                    break
                }
            }
        }

        // 播放失败通知
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            self?.isLoading = false
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
                self?.errorMessage = error.localizedDescription
                print("❌ [StreamingVideoPlayer] 播放中断 fileId=\(self?.currentFileId ?? -1) error=\(error.localizedDescription)")
            } else {
                self?.errorMessage = "视频播放中断"
                print("❌ [StreamingVideoPlayer] 播放中断 fileId=\(self?.currentFileId ?? -1)")
            }
            self?.stopAndClearResources()
        }

        // 播放完成通知：会话结束后强制释放本次播放资源。
        playbackFinishedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            print("✅ [StreamingVideoPlayer] 播放完成 fileId=\(self.currentFileId ?? -1)")
            self.stopAndClearResources()
            self.onPlaybackSessionTerminated?()
        }

        // 周期性时间观察（更新进度条）
        let interval = CMTime(seconds: 0.3, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isSeeking else { return }
            let seconds = time.seconds
            if seconds.isFinite && seconds >= 0 {
                self.currentTime = seconds
                if self.duration > 0 {
                    self.sliderPosition = min(seconds / self.duration, 1.0)
                }
            }
        }

        self.player = player
        player.playImmediately(atRate: 1.0)
        playState = .playing
    }

    // MARK: - 播放控制

    func pause() {
        print("⏸️ [StreamingVideoPlayer] 用户暂停 fileId=\(currentFileId ?? -1) currentTime=\(String(format: "%.1f", currentTime))s")
        player?.rate = 0
        player?.pause()
        playState = .paused
    }

    func resume() {
        print("▶️ [StreamingVideoPlayer] 用户恢复播放 fileId=\(currentFileId ?? -1)")
        player?.playImmediately(atRate: 1.0)
        playState = .playing
    }

    /// Seek 到进度比例 fraction（0...1）。
    /// 使用 Chase Time 模式：快速多次调用只会追最新目标，不产生并发 seek。
    func seekToFraction(_ fraction: Double) {
        guard let player, duration > 0 else { return }

        let targetSeconds = fraction * duration
        let targetOffset = fileSize > 0 ? Int64(fraction * Double(fileSize)) : 0
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        print("⏩ [StreamingVideoPlayer] 进度跳转 fileId=\(currentFileId ?? -1) fraction=\(String(format: "%.3f", fraction)) targetTime=\(String(format: "%.1f", targetSeconds))s targetOffset=\(targetOffset)")

        chaseTime = targetTime
        sliderPosition = fraction

        guard !isSeekInProgress else { return }
        performChaseSeek(player: player)
    }

    /// 递归执行 seek，直到 chaseTime 不再变化（Chase Time 模式）。
    private func performChaseSeek(player: AVPlayer) {
        isSeekInProgress = true
        isSeeking = true
        isSeekBuffering = true
        let target = chaseTime

        guard let fileId = currentFileId,
              let sessionId = playbackSessionId else {
            executePlayerSeek(player: player, target: target)
            return
        }

        seekNotificationTask?.cancel()
        seekNotificationTask = Task { [weak self, weak player] in
            await VideoPlaybackService.shared.notifySeek(
                fileId: fileId,
                sessionId: sessionId,
                targetSeconds: target.seconds
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      let player,
                      self.player === player,
                      self.currentFileId == fileId,
                      self.playbackSessionId == sessionId else { return }
                self.seekNotificationTask = nil
                if CMTimeCompare(self.chaseTime, target) != 0 {
                    self.performChaseSeek(player: player)
                    return
                }
                self.executePlayerSeek(player: player, target: target)
            }
        }
    }

    private func executePlayerSeek(player: AVPlayer, target: CMTime) {
        player.seek(
            to: target,
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { [weak self] finished in
            guard let self else { return }
            DispatchQueue.main.async {
                if CMTimeCompare(self.chaseTime, target) != 0 {
                    // 目标时间在 seek 过程中已更新，继续追最新目标
                    self.performChaseSeek(player: player)
                } else {
                    self.isSeekInProgress = false
                    self.isSeeking = false
                    self.isSeekBuffering = false
                    print("✅ [StreamingVideoPlayer] seek完成 fileId=\(self.currentFileId ?? -1) time=\(String(format: "%.1f", target.seconds))s")
                    if finished && self.playState == .playing {
                        player.playImmediately(atRate: 1.0)
                    }
                }
            }
        }
    }

    /// 停止播放并释放所有资源（Issue 1 & 4）。
    func stopAndClearResources() {
        print("⏹️ [StreamingVideoPlayer] 用户停止播放 fileId=\(currentFileId ?? -1)")
        stopPlaying()
        playState = .stopped
    }

    // MARK: - 内部清理

    /// 释放播放器所有资源：AVPlayer、KVO、通知、缓存、socket。
    func stopPlaying() {
        setupTask?.cancel()
        setupTask = nil
        seekNotificationTask?.cancel()
        seekNotificationTask = nil

        // 移除时间观察者（必须在 player 释放前）
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        playerStatusObservation?.invalidate()
        playerStatusObservation = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
            self.playbackFinishedObserver = nil
        }

        if let fid = currentFileId {
            print("🧹 [StreamingVideoPlayer] 释放播放资源 fileId=\(fid)")
            currentFileId = nil
        }

        isSeekInProgress = false
        isSeeking = false
        isSeekBuffering = false
        chaseTime = .zero
        playbackSessionId = nil
        fileSize = 0
        isLoading = false
    }

    deinit {
        setupTask?.cancel()
        // 确保 deinit 时 timeObserver 已移除（若 player 仍存在）
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
    }
}
