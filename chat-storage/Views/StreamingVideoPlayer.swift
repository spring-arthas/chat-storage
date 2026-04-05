import SwiftUI
import AVKit

/// SwiftUI 包装的视频播放界面（独立窗口版）
struct StreamingVideoPlayer: View {
    let fileId: Int64
    let fileName: String
    let fileSize: Int64

    @StateObject private var viewModel = StreamingVideoViewModel()

    var body: some View {
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
                        viewModel.setupPlayer(fileId: fileId, fileName: fileName, expectedSize: fileSize)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
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
}

// MARK: - ViewModel

class StreamingVideoViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil

    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var currentFileId: Int64?

    func setupPlayer(fileId: Int64, fileName: String, expectedSize: Int64) {
        stopPlaying()

        currentFileId = fileId
        VideoStreamCacheManager.shared.start(fileId: fileId, fileSize: expectedSize, fileName: fileName)

        isLoading = true
        errorMessage = nil

        guard let url = LocalMediaServer.shared.getStreamURL(for: fileId, fileSize: expectedSize, fileName: fileName) else {
            errorMessage = "无法启动本地视频代理"
            isLoading = false
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        let playerObservationOptions: NSKeyValueObservingOptions = [.initial, .new]
        playerStatusObservation = player.observe(\AVPlayer.timeControlStatus, options: playerObservationOptions) { [weak self] (observedPlayer: AVPlayer, _: NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = observedPlayer.timeControlStatus == AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate
            }
        }

        let itemObservationOptions: NSKeyValueObservingOptions = [.initial, .new]
        itemStatusObservation = item.observe(\AVPlayerItem.status, options: itemObservationOptions) { [weak self] (observedItem: AVPlayerItem, _: NSKeyValueObservedChange<AVPlayerItem.Status>) in
            DispatchQueue.main.async {
                guard let self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.isLoading = false
                case .failed:
                    self.isLoading = false
                    self.errorMessage = observedItem.error?.localizedDescription ?? "播放器加载失败"
                default:
                    break
                }
            }
        }

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

        self.player = player
    }

    func stopPlaying() {
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
    }

    deinit {
        stopPlaying()
    }
}
