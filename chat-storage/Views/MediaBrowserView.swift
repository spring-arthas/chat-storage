//
//  MediaBrowserView.swift
//  chat-storage
//
//  通用媒体预览器：图片缩放 + 左右切换 + 视频播放
//  云盘图片预览和动态媒体浏览共用
//

import SwiftUI
import AppKit

// MARK: - 预览器状态

struct MediaBrowserState: Identifiable, Equatable {
    let items: [DirectoryItem]
    var selectedIndex: Int

    var id: String {
        "\(selectedIndex)-" + items.map { String($0.id) }.joined(separator: ",")
    }

    init(items: [DirectoryItem], selectedFileId: Int64) {
        // 只保留图片和可播放视频
        self.items = items.filter { $0.isImageFile || $0.isPlayableVideoFile }
        self.selectedIndex = max(0, self.items.firstIndex(where: { $0.id == selectedFileId }) ?? 0)
    }
}

// MARK: - 媒体预览器

struct MediaBrowserView: View {
    let state: MediaBrowserState
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var image: NSImage?
    @State private var isLoadingImage = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var toastMessage: String?
    @State private var videoViewModel: StreamingVideoViewModel?

    private var currentItem: DirectoryItem { state.items[currentIndex] }
    private var isVideo: Bool { currentItem.isPlayableVideoFile }

    init(state: MediaBrowserState, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
        _currentIndex = State(initialValue: state.selectedIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                contentArea
                Spacer(minLength: 0)
                bottomBar
            }

            if let toast = toastMessage {
                toastView(toast)
            }
        }
        .background(KeyEventHandlingView(
            onLeftArrow: { goPrevious() },
            onRightArrow: { goNext() },
            onEscape: { onClose() }
        ))
        .onAppear { loadMedia(for: currentIndex) }
        .onChange(of: currentIndex) { newValue in
            resetTransform()
            loadMedia(for: newValue)
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack {
            Text(currentItem.fileName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(currentIndex + 1) / \(state.items.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭预览 (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        if isVideo {
            videoContent
        } else {
            imageContent
        }
    }

    private var imageContent: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 5)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1.01 { resetTransform() }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.01 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                if scale > 1.01 { lastOffset = offset }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if scale > 1.01 {
                                resetTransform()
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
            } else if isLoadingImage {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("加载图片...")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.4))
                    Text("无法预览此图片")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoContent: some View {
        Group {
            if let vm = videoViewModel {
                StreamingVideoPlayer(
                    fileId: currentItem.id,
                    fileName: currentItem.fileName,
                    fileSize: currentItem.fileSize ?? 0,
                    viewModel: vm
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("加载视频...")
                    .tint(.white)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - 底部栏

    private var bottomBar: some View {
        HStack {
            Button(action: goPrevious) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("上一张")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 100, height: 36)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)
            .help("上一张 (←)")

            Spacer()

            if isVideo {
                Text("视频模式")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("滚轮或捏合缩放 · 双击复位")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button(action: goNext) {
                HStack(spacing: 6) {
                    Text("下一张")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 100, height: 36)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == state.items.count - 1)
            .help("下一张 (→)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.18), in: Capsule())
            .transition(.opacity.combined(with: .scale))
            .zIndex(10)
    }

    // MARK: - 逻辑

    private func goPrevious() {
        guard currentIndex > 0 else {
            showToast("已经是第一张")
            return
        }
        currentIndex -= 1
    }

    private func goNext() {
        guard currentIndex < state.items.count - 1 else {
            showToast("已经是最后一张")
            return
        }
        currentIndex += 1
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }

    private func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func loadMedia(for index: Int) {
        let item = state.items[index]

        // 清理旧视频资源
        videoViewModel?.stopPlaying()
        videoViewModel = nil

        image = nil
        isLoadingImage = false

        if item.isPlayableVideoFile {
            let vm = StreamingVideoViewModel()
            videoViewModel = vm
        } else if item.isImageFile {
            isLoadingImage = true
            Task {
                let loaded = await FileThumbnailService.shared.previewImage(for: item)
                await MainActor.run {
                    guard currentIndex == index else { return }
                    self.image = loaded
                    self.isLoadingImage = false
                }
            }
        }
    }
}

// MARK: - 键盘事件监听

struct KeyEventHandlingView: NSViewRepresentable {
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onEscape = onEscape
    }
}

final class KeyEventView: NSView {
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            onLeftArrow?()
        case 124: // Right arrow
            onRightArrow?()
        case 53: // Escape
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
