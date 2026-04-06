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

    var body: some View {
        ZStack {
            Color.black

            if let player = viewModel.player {
                AVPlayerViewRepresentable(player: player)
            }

            // 缓冲中提示
            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("缓冲中...")
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
        Slider(
            value: Binding(
                get: { viewModel.sliderPosition },
                set: { newValue in
                    viewModel.seekToFraction(newValue)
                }
            ),
            in: 0...1
        )
        .accentColor(.white)
        .padding(.horizontal, 12)
        .disabled(viewModel.duration <= 0 || viewModel.playState == .stopped)
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

    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var currentFileId: Int64?

    // 记录是否正在 seek，防止 seek 期间时间观察者覆盖 slider 位置
    private var isSeeking = false

    // MARK: - Setup

    func setupPlayer(fileId: Int64, fileName: String, expectedSize: Int64) {
        stopPlaying()

        currentFileId = fileId
        VideoStreamCacheManager.shared.start(fileId: fileId, fileSize: expectedSize, fileName: fileName)

        isLoading = true
        errorMessage = nil
        playState = .idle
        currentTime = 0
        duration = 0
        sliderPosition = 0

        guard let url = LocalMediaServer.shared.getStreamURL(for: fileId, fileSize: expectedSize, fileName: fileName) else {
            errorMessage = "无法启动本地视频代理"
            isLoading = false
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

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
                case .failed:
                    self.isLoading = false
                    self.errorMessage = observedItem.error?.localizedDescription ?? "播放器加载失败"
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
            } else {
                self?.errorMessage = "视频播放中断"
            }
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
        player.play()
        playState = .playing
    }

    // MARK: - 播放控制

    func pause() {
        player?.pause()
        playState = .paused
    }

    func resume() {
        player?.play()
        playState = .playing
    }

    /// Seek 到进度比例 fraction（0...1），Seek 完成后若在播放状态则恢复播放。
    func seekToFraction(_ fraction: Double) {
        guard let player, duration > 0 else { return }
        let targetSeconds = fraction * duration
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)

        isSeeking = true
        sliderPosition = fraction

        // 使用宽容度为零的精确 seek，完成后恢复播放状态
        player.seek(
            to: targetTime,
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { [weak self] finished in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSeeking = false
                if finished && self.playState == .playing {
                    // seek 完成后保持播放状态（核心修复：避免 seek 后停留在暂停）
                    self.player?.play()
                }
            }
        }
    }

    /// 停止播放并释放所有资源（Issue 1 & 4）。
    func stopAndClearResources() {
        stopPlaying()
        playState = .stopped
    }

    // MARK: - 内部清理

    /// 释放播放器所有资源：AVPlayer、KVO、通知、缓存、socket。
    func stopPlaying() {
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

        if let fid = currentFileId {
            VideoStreamCacheManager.shared.stop(fileId: fid)
            currentFileId = nil
        }

        isLoading = false
    }

    deinit {
        // 确保 deinit 时 timeObserver 已移除（若 player 仍存在）
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        // stopPlaying 中其他清理也在此兜底
        if let fid = currentFileId {
            VideoStreamCacheManager.shared.stop(fileId: fid)
        }
    }
}
