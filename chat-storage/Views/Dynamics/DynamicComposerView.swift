//
//  DynamicComposerView.swift
//  chat-storage
//
//  动态发布面板：主流app风格，底部工具栏 + 选中媒体缩略图条
//

import SwiftUI
import AppKit
import AVFoundation
import Combine

struct DynamicComposerView: View {
    let repository: any DynamicRepository
    let transferManager: TransferTaskManager
    let authenticationService: AuthenticationService
    let onClose: () -> Void
    let onPublished: () -> Void

    @State private var content = ""
    @State private var selectedFiles: [PendingMedia] = []
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("发布动态")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TelegramTheme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(TelegramTheme.panelBackground, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // 文本输入区
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("分享新鲜事...")
                        .font(.system(size: 14))
                        .foregroundColor(TelegramTheme.textSecondary.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $content)
                    .font(.system(size: 14))
                    .foregroundColor(TelegramTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, -5)
                    .padding(.vertical, -8)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 100, maxHeight: 180)

            // 已选媒体缩略图条
            if !selectedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedFiles) { file in
                            mediaThumbnail(file)
                        }
                        // 添加按钮
                        Button(action: pickFiles) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                Text("添加")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(TelegramTheme.textSecondary)
                            .frame(width: 72, height: 72)
                            .background(TelegramTheme.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundColor(TelegramTheme.textSecondary.opacity(0.3))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .frame(height: 92)
            }

            Spacer(minLength: 0)

            // 错误提示
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(TelegramTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // 底部工具栏
            HStack {
                // 左侧：图片/视频按钮
                Button(action: pickFiles) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .help("添加图片")

                Button(action: pickFiles) {
                    Image(systemName: "film")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(TelegramTheme.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .help("添加视频")

                Spacer()

                // 字数
                Text("\(content.count)字")
                    .font(.system(size: 12))
                    .foregroundColor(TelegramTheme.textSecondary)
                    .padding(.trailing, 12)

                // 发布按钮
                Button(action: publish) {
                    if isPublishing {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 72, height: 32)
                    } else {
                        Text("发布")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 32)
                    }
                }
                .buttonStyle(.plain)
                .background(canPublish ? TelegramTheme.success : TelegramTheme.success.opacity(0.4))
                .clipShape(Capsule())
                .disabled(!canPublish || isPublishing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(TelegramTheme.panelBackground)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(TelegramTheme.textSecondary.opacity(0.15)),
                alignment: .top
            )
        }
        .frame(width: 560, height: 380)
        .background(TelegramTheme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 24, y: 6)
    }

    private var canPublish: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && selectedFiles.allSatisfy { if case .completed = $0.uploadState { return true } else { return false } }
        && !isPublishing
    }

    // MARK: - 媒体缩略图

    private func mediaThumbnail(_ file: PendingMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = file.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        TelegramTheme.panelBackground
                        Image(systemName: file.kind == .video ? "film" : "photo")
                            .font(.system(size: 18))
                            .foregroundColor(TelegramTheme.textSecondary.opacity(0.5))
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // 上传进度
            if case .uploading(let progress) = file.uploadState {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 3) {
                        ProgressView(value: progress)
                            .tint(TelegramTheme.success)
                            .frame(width: 44)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // 失败标记
            if case .failed = file.uploadState {
                ZStack {
                    Color.black.opacity(0.6)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // 视频标记
            if file.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.5), in: Circle())
                    .padding(3)
            }

            // 删除按钮
            Button(action: { removeFile(file) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.black.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }

    // MARK: - 文件选择

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择图片或视频"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "选择要发布的图片或视频文件"

        if panel.runModal() == .OK {
            for url in panel.urls {
                addFile(url)
            }
        }
    }

    private func addFile(_ url: URL) {
        let fileName = url.lastPathComponent
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ext = url.pathExtension.lowercased()
        let kind: DynamicMediaKind = ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) ? .video : .image

        let thumbnail = generateThumbnail(for: url, kind: kind)

        let pending = PendingMedia(
            url: url,
            fileName: fileName,
            fileSize: Int64(fileSize),
            kind: kind,
            mimeType: mimeType(for: ext),
            thumbnail: thumbnail,
            uploadState: .pending
        )
        selectedFiles.append(pending)
        startUpload(for: pending)
    }

    private func removeFile(_ file: PendingMedia) {
        selectedFiles.removeAll { $0.id == file.id }
    }

    private func generateThumbnail(for url: URL, kind: DynamicMediaKind) -> NSImage? {
        if kind == .image {
            return NSImage(contentsOf: url)
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: 144, height: 144))
        }
        return nil
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }

    // MARK: - 上传

    private func startUpload(for file: PendingMedia) {
        guard let user = authenticationService.currentUser else {
            updateFile(file.id, state: .failed("未登录"))
            return
        }

        let task = StorageTransferTask(
            taskType: .upload,
            name: file.fileName,
            fileUrl: file.url,
            targetDirId: 0,
            userId: user.id,
            userName: user.username,
            fileSize: file.fileSize,
            directoryName: "",
            directoryFullPath: "",
            remoteFileId: 0
        )

        let taskId = task.id.uuidString
        transferManager.submit(task: task)

        // 监听上传进度
        transferManager.$taskUpdates
            .receive(on: DispatchQueue.main)
            .sink { updates in
                if let update = updates[taskId] {
                    if update.stage.isCompleted {
                        // 等待 fileId 通知
                    } else if update.stage.isFailed {
                        self.updateFile(file.id, state: .failed(update.errorMessage ?? "上传失败"))
                    } else {
                        self.updateFile(file.id, state: .uploading(update.progress))
                    }
                }
            }
            .store(in: &cancellables)

        // 监听上传完成通知获取 fileId
        NotificationCenter.default.publisher(for: .uploadTaskDidComplete)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let notifiedTaskId = notification.userInfo?["taskId"] as? String,
                      notifiedTaskId == taskId else { return }
                if let fileId = notification.userInfo?["fileId"] as? Int64, fileId > 0 {
                    self.updateFile(file.id, state: .completed(fileId: fileId))
                } else {
                    self.updateFile(file.id, state: .failed("未获取到文件ID"))
                }
            }
            .store(in: &cancellables)
    }

    private func updateFile(_ id: UUID, state: PendingMedia.UploadState) {
        guard let index = selectedFiles.firstIndex(where: { $0.id == id }) else { return }
        selectedFiles[index].uploadState = state
    }

    // MARK: - 发布

    private func publish() {
        guard canPublish else { return }
        isPublishing = true
        errorMessage = nil

        let media = selectedFiles.compactMap { file -> DynamicMedia? in
            guard case .completed(let fileId) = file.uploadState else { return nil }
            return DynamicMedia(
                kind: file.kind,
                fileId: fileId,
                fileName: file.fileName,
                fileSize: file.fileSize,
                mimeType: file.mimeType
            )
        }

        let request = DynamicCreateRequest(content: content, media: media)

        Task {
            do {
                _ = try await repository.create(request)
                await MainActor.run {
                    isPublishing = false
                    onPublished()
                }
            } catch {
                await MainActor.run {
                    isPublishing = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "发布失败"
                }
            }
        }
    }
}

// MARK: - 待上传媒体

struct PendingMedia: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileSize: Int64
    let kind: DynamicMediaKind
    let mimeType: String
    let thumbnail: NSImage?
    var uploadState: UploadState

    enum UploadState: Equatable {
        case pending
        case uploading(Double)
        case completed(fileId: Int64)
        case failed(String)
    }
}
