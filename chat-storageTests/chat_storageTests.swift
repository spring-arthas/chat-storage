//
//  chat_storageTests.swift
//  chat-storageTests
//
//  Created by HLJY on 2026/1/29.
//

import XCTest
import Network
@testable import chat_storage

final class chat_storageTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testTelegramPaletteUsesExpectedAccent() throws {
        XCTAssertEqual(TelegramTheme.accentHex, "#2AABEE")
    }

    func testTelegramPaletteSurfaceColorsStayStable() throws {
        XCTAssertEqual(TelegramTheme.appBackgroundHex, "#17212B")
        XCTAssertEqual(TelegramTheme.panelBackgroundHex, "#1F2936")
        XCTAssertEqual(TelegramTheme.elevatedBackgroundHex, "#253142")
    }

    func testTransferStatusColorMapping() throws {
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "已完成"), "#4BCB8A")
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "上传中"), "#2AABEE")
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "失败"), "#FF5C5C")
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "暂停"), "#F3B15E")
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "未知状态"), "#9DB0C8")
    }

    func testLightPaletteSurfaceColorsStayStable() throws {
        XCTAssertEqual(TelegramTheme.lightAppBackgroundHex, "#EEF3F8")
        XCTAssertEqual(TelegramTheme.lightPanelBackgroundHex, "#F7FAFD")
        XCTAssertEqual(TelegramTheme.lightElevatedBackgroundHex, "#E3EBF4")
        XCTAssertEqual(TelegramTheme.lightTextPrimaryHex, "#132338")
    }

    func testTransferStatusColorMappingInLightMode() throws {
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "暂停", isDark: false), "#C88A1A")
        XCTAssertEqual(TelegramTheme.statusColorHex(for: "未知状态", isDark: false), "#51657F")
    }

    func testMainWindowLayoutSupportsResponsiveGrowth() throws {
        XCTAssertEqual(AppWindowLayout.mainDefaultWidth, 1240)
        XCTAssertEqual(AppWindowLayout.mainDefaultHeight, 760)
        XCTAssertEqual(AppWindowLayout.mainMinWidth, 1240)
        XCTAssertEqual(AppWindowLayout.mainMinHeight, 760)
        XCTAssertEqual(AppWindowLayout.loginWidth, 720)
        XCTAssertEqual(AppWindowLayout.loginHeight, 456)
    }

    func testFileDetailDirectoryNameOnlyReturnsDirectParent() throws {
        let detail = FileDto(
            id: 1,
            pId: 2,
            fileName: "movie.mp4",
            filePath: "/Users/demo/storages/account/电影/欧美/movie.mp4",
            fileSize: 1024,
            fileType: "mp4",
            isFile: "Y",
            isExist: "Y",
            hasChild: "N",
            userName: "demo",
            gmtCreated: nil,
            gmtModified: nil,
            del: "N",
            delTime: nil,
            childFileList: nil
        )

        XCTAssertEqual(detail.directoryName, "欧美")
    }

    func testFileDetailLayoutCompactsForMinimumWindowHeight() throws {
        let compact = FileDetailLayoutMetrics(availableHeight: 650)
        let regular = FileDetailLayoutMetrics(availableHeight: 900)

        XCTAssertLessThan(compact.previewHeight, regular.previewHeight)
        XCTAssertLessThanOrEqual(compact.sectionSpacing, regular.sectionSpacing)
        XCTAssertEqual(compact.actionButtonHeight, 38)
    }

    func testAppAppearanceModesMapToExpectedColorSchemes() throws {
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }

    func testAppSettingsCategoriesStayStable() throws {
        XCTAssertEqual(AppSettingsCategory.allCases.map(\.title), ["外观", "文件传输", "网络连接"])
    }

    func testDirectoryTreeTreatsEmptyDirectoryChildrenAsNotExpandable() throws {
        let directory = FileDto(
            id: 100,
            pId: 1,
            fileName: "工作",
            filePath: "/tmp/工作",
            fileSize: nil,
            fileType: "NOT_FILE",
            isFile: "N",
            isExist: "Y",
            hasChild: "Y",
            userName: "18806504525",
            gmtCreated: nil,
            gmtModified: nil,
            del: "N",
            delTime: nil,
            childFileList: []
        )

        let item = directory.toDirectoryItem()

        XCTAssertFalse(item.hasChild)
        XCTAssertEqual(item.childFileList, [])
    }

    func testLocalMediaServerTreatsConnectionResetAsClientAbort() throws {
        XCTAssertTrue(LocalMediaServer.isClientClosedConnectionError(NWError.posix(.ECONNRESET)))
        XCTAssertTrue(LocalMediaServer.isClientClosedConnectionError(POSIXError(.EPIPE)))
    }

    func testLocalMediaServerKeepsRealConnectionFailuresVisible() throws {
        XCTAssertFalse(LocalMediaServer.isClientClosedConnectionError(NWError.posix(.ETIMEDOUT)))
        XCTAssertFalse(LocalMediaServer.isClientClosedConnectionError(SocketError.connectionFailed))
    }

    func testVideoStreamCacheCompletionLogOnlyForSequentialFullLoad() throws {
        XCTAssertNotNil(
            VideoStreamCache.completionLogMessage(
                fileName: "demo.mp4",
                fileSize: 1024,
                writtenBytes: 1024,
                downloadStartOffset: 0,
                allowsSequentialCompletionLog: true
            )
        )

        XCTAssertNil(
            VideoStreamCache.completionLogMessage(
                fileName: "demo.mp4",
                fileSize: 1024,
                writtenBytes: 768,
                downloadStartOffset: 0,
                allowsSequentialCompletionLog: true
            )
        )

        XCTAssertNil(
            VideoStreamCache.completionLogMessage(
                fileName: "demo.mp4",
                fileSize: 1024,
                writtenBytes: 1024,
                downloadStartOffset: 512,
                allowsSequentialCompletionLog: true
            )
        )

        XCTAssertNil(
            VideoStreamCache.completionLogMessage(
                fileName: "demo.mp4",
                fileSize: 1024,
                writtenBytes: 1024,
                downloadStartOffset: 0,
                allowsSequentialCompletionLog: false
            )
        )
    }

    func testVideoStreamCacheCompletionLogIncludesExactByteCounts() throws {
        let message = try XCTUnwrap(
            VideoStreamCache.completionLogMessage(
                fileName: "movie.mov",
                fileSize: 4096,
                writtenBytes: 4096,
                downloadStartOffset: 0,
                allowsSequentialCompletionLog: true
            )
        )

        XCTAssertTrue(message.contains("文件名称=movie.mov"))
        XCTAssertTrue(message.contains("文件总流字节大小=4096"))
        XCTAssertTrue(message.contains("已拉取的大小=4096"))
    }

    func testTransferHeaderUsesPrimaryTextContrastInBothThemes() throws {
        XCTAssertEqual(TelegramTheme.transferHeaderTextHex(isDark: true), TelegramTheme.textPrimaryHex)
        XCTAssertEqual(TelegramTheme.transferHeaderTextHex(isDark: false), TelegramTheme.lightTextPrimaryHex)
    }

    func testThumbnailPrefetchRangesUsesHeadAndTailForLargeFile() throws {
        let ranges = VideoThumbnailResourceLoader.prefetchRanges(fileSize: 10 * 1024 * 1024, maxBytesPerRequest: 4 * 1024 * 1024)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].offset, 0)
        XCTAssertEqual(ranges[0].length, 4 * 1024 * 1024)
        XCTAssertEqual(ranges[1].offset, 6 * 1024 * 1024)
        XCTAssertEqual(ranges[1].length, 4 * 1024 * 1024)
    }

    func testThumbnailLedgerRecordsReadyAndUploadSuccessForRemap() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let service = FileThumbnailService(testDiskCacheDir: tempRoot)
        let taskId = UUID().uuidString

        await service.debugMarkThumbnailReady(taskId: taskId)
        await service.debugMarkUploadSucceeded(taskId: taskId, fileId: 123456)

        let recordValue = await service.debugLedgerRecord(taskId: taskId)
        let record = try XCTUnwrap(recordValue)
        XCTAssertEqual(record.fileId, 123456)
        XCTAssertEqual(record.state, .uploadSucceeded)

        let pending = await service.debugPendingRemapTaskIds()
        XCTAssertTrue(pending.contains(taskId))
    }

    func testThumbnailLedgerCanReloadPendingRecordFromDisk() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let taskId = UUID().uuidString
        do {
            let service = FileThumbnailService(testDiskCacheDir: tempRoot)
            await service.debugMarkThumbnailReady(taskId: taskId)
            await service.debugMarkUploadSucceeded(taskId: taskId, fileId: 888)
        }

        let restored = FileThumbnailService(testDiskCacheDir: tempRoot)
        let pending = await restored.debugPendingRemapTaskIds()
        XCTAssertTrue(pending.contains(taskId))
    }

    func testFFmpegThumbnailArgsUseFastSeekAndSingleFrame() throws {
        let args = FileThumbnailService.debugFFmpegArguments(
            inputPath: "/tmp/input.mp4",
            outputPath: "/tmp/output.jpg",
            seekSeconds: 3,
            outputWidth: 1920,
            outputHeight: 1080,
            quality: 2
        )

        XCTAssertTrue(args.contains("-ss"))
        XCTAssertTrue(args.contains("-frames:v"))
        XCTAssertTrue(args.contains("1"))
        XCTAssertTrue(args.contains("-vf"))
        XCTAssertTrue(args.contains("scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black"))
        XCTAssertTrue(args.contains("-q:v"))
        XCTAssertTrue(args.contains("2"))
        XCTAssertEqual(args.last, "/tmp/output.jpg")
    }

    func testFFmpegCandidatePathsIncludeHomebrewAndUsrLocal() throws {
        let candidates = FileThumbnailService.debugFFmpegCandidatePaths(pathEnv: nil)
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/ffmpeg"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/ffmpeg"))
    }

    func testFFmpegCandidatePathsPreferBundledBinary() throws {
        let candidates = FileThumbnailService.debugFFmpegCandidatePaths(
            bundleResourcePath: "/Applications/chat-storage.app/Contents/Resources",
            bundlePath: "/Applications/chat-storage.app",
            privateFrameworksPath: "/Applications/chat-storage.app/Contents/Frameworks",
            pathEnv: nil
        )
        XCTAssertEqual(candidates.first, "/Applications/chat-storage.app/Contents/Resources/ffmpeg")
        XCTAssertTrue(candidates.contains("/Applications/chat-storage.app/Contents/Resources/tools/ffmpeg"))
        XCTAssertTrue(candidates.contains("/Applications/chat-storage.app/Contents/Frameworks/ffmpeg"))
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/ffmpeg"))
    }

    func testLocalVideoThumbnailProfileUsesHigherQualityForLargeMov() throws {
        let profile = FileThumbnailService.debugLocalVideoThumbnailProfile(
            fileSize: 3_500_000_000,
            fileExtension: "mov"
        )
        XCTAssertEqual(profile.outputWidth, 1920)
        XCTAssertEqual(profile.outputHeight, 1080)
        XCTAssertEqual(profile.ffmpegQuality, 2)
        XCTAssertEqual(profile.seekPoints, [5, 12, 20])
        XCTAssertEqual(profile.timeoutSeconds, 45)
    }

    func testLocalVideoThumbnailProfileKeepsFullHDForSmallMp4() throws {
        let profile = FileThumbnailService.debugLocalVideoThumbnailProfile(
            fileSize: 10_000_000,
            fileExtension: "mp4"
        )
        XCTAssertEqual(profile.outputWidth, 1920)
        XCTAssertEqual(profile.outputHeight, 1080)
    }

    func testIsFullHDChecker() throws {
        XCTAssertTrue(FileThumbnailService.debugIsFullHD(width: 1920, height: 1080))
        XCTAssertFalse(FileThumbnailService.debugIsFullHD(width: 1919.4, height: 1080))
        XCTAssertFalse(FileThumbnailService.debugIsFullHD(width: 1920, height: 1079))
    }

    func testVideoThumbnailCompletedLogContainsRequiredFields() throws {
        let message = FileThumbnailService.debugThumbnailProcessingCompletedLog(
            fileName: "demo.mp4",
            thumbnailPath: "/tmp/task_abc.jpg",
            taskId: "ABC-123"
        )
        XCTAssertTrue(message.contains("文件名称: demo.mp4"))
        XCTAssertTrue(message.contains("缩略图文件位置: /tmp/task_abc.jpg"))
        XCTAssertTrue(message.contains("上传任务Id: ABC-123"))
    }

    func testChatActionFrameTypesDoNotConflictWithFriendAliasFrames() throws {
        XCTAssertEqual(FrameTypeEnum.friendUpdateAliasReq.rawValue, 0x57)
        XCTAssertEqual(FrameTypeEnum.friendUpdateAliasResp.rawValue, 0x58)
        XCTAssertEqual(FrameTypeEnum.chatMessageActionReq.rawValue, 0x59)
        XCTAssertEqual(FrameTypeEnum.chatMessageActionResp.rawValue, 0x5A)
        XCTAssertEqual(FrameTypeEnum.chatMessageActionPush.rawValue, 0x5B)
    }

    func testChatSendRequestDecodesOptionalReliabilityAndQuoteFields() throws {
        let json = """
        {
          "receiverId": 1001,
          "content": "你好 😀",
          "msgType": "TEXT",
          "clientMsgId": "client-001",
          "quoteMsgId": 9001,
          "quoteMsgContent": "上一条消息",
          "quoteMsgSenderName": "张三"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ChatSendRequestDto.self, from: json)

        XCTAssertEqual(dto.receiverId, 1001)
        XCTAssertEqual(dto.content, "你好 😀")
        XCTAssertEqual(dto.msgType, "TEXT")
        XCTAssertEqual(dto.clientMsgId, "client-001")
        XCTAssertEqual(dto.quoteMsgId, 9001)
        XCTAssertEqual(dto.quoteMsgContent, "上一条消息")
        XCTAssertEqual(dto.quoteMsgSenderName, "张三")
    }

    func testChatReceiptDecodesClientMessageIdForReliableMatching() throws {
        let json = """
        {
          "messageId": 7788,
          "clientMsgId": "client-7788",
          "status": "SUCCESS",
          "message": "发送成功"
        }
        """.data(using: .utf8)!

        let receipt = try JSONDecoder().decode(ChatReceiptDto.self, from: json)

        XCTAssertEqual(receipt.messageId, 7788)
        XCTAssertEqual(receipt.clientMsgId, "client-7788")
        XCTAssertEqual(receipt.status, "SUCCESS")
        XCTAssertEqual(receipt.message, "发送成功")
    }

    func testChatReceiptMatchesClientMessageIdBeforeNilMessageIdFallback() throws {
        let firstPending = ChatMessage(
            messageId: nil,
            clientMsgId: "client-first",
            content: "第一条待发送",
            isMe: true,
            timestamp: Date(timeIntervalSince1970: 1),
            type: "TEXT",
            sendStatus: .sending
        )
        let targetPending = ChatMessage(
            messageId: nil,
            clientMsgId: "client-target",
            content: "目标待发送",
            isMe: true,
            timestamp: Date(timeIntervalSince1970: 2),
            type: "TEXT",
            sendStatus: .sending
        )
        let receiptJson = """
        {
          "messageId": 8801,
          "clientMsgId": "client-target",
          "status": "SUCCESS"
        }
        """.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(ChatReceiptDto.self, from: receiptJson)

        let updated = ChatReceiptMatcher.apply(receipt: receipt, to: [firstPending, targetPending])

        XCTAssertNil(updated[0].messageId)
        XCTAssertEqual(updated[0].sendStatus, .sending)
        XCTAssertEqual(updated[1].messageId, 8801)
        XCTAssertEqual(updated[1].sendStatus, .success)
    }

    func testChatTextInsertionUsesCurrentSelectionRange() throws {
        let result = ChatTextInsertion.insert("😀", into: "你好世界", selectedRange: NSRange(location: 2, length: 0))

        XCTAssertEqual(result.text, "你好😀世界")
        XCTAssertEqual(result.selectedRange.location, 4)
        XCTAssertEqual(result.selectedRange.length, 0)
    }

    func testChatImageAttachmentContentRoundTrips() throws {
        let attachment = ChatImageAttachment(
            fileId: 90001,
            fileName: "chat-image-90001.png",
            fileSize: 123_456,
            mimeType: "image/png"
        )

        let content = try attachment.contentString()
        let parsed = ChatImageAttachment.parse(content)

        XCTAssertEqual(parsed, attachment)
        XCTAssertTrue(content.contains("\"kind\":\"image\""))
    }

    func testChatImageAttachmentBuildsImageDirectoryItem() throws {
        let attachment = ChatImageAttachment(
            fileId: 90002,
            fileName: "paste.png",
            fileSize: 2048,
            mimeType: "image/png"
        )

        let item = attachment.directoryItem()

        XCTAssertEqual(item.id, 90002)
        XCTAssertEqual(item.fileName, "paste.png")
        XCTAssertEqual(item.fileSize, 2048)
        XCTAssertTrue(item.isFile)
        XCTAssertTrue(item.isImageFile)
    }

    func testChatImageAttachmentUsesDerivedFilesForThumbnailAndPreview() throws {
        let attachment = ChatImageAttachment(
            fileId: 90003,
            fileName: "large.heic",
            fileSize: 20_000_000,
            mimeType: "image/heic",
            thumbnailFileId: 91003,
            thumbnailFileSize: 80_000,
            previewFileId: 92003,
            previewFileSize: 1_200_000
        )

        let thumbnailItem = attachment.thumbnailDirectoryItem()
        let previewItem = attachment.previewDirectoryItem()

        XCTAssertEqual(thumbnailItem.id, 91003)
        XCTAssertEqual(thumbnailItem.fileSize, 80_000)
        XCTAssertEqual(previewItem.id, 92003)
        XCTAssertEqual(previewItem.fileSize, 1_200_000)
    }

    func testChatAttachmentUploadServicePreparesPngTempFile() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()

        let service = ChatAttachmentUploadService()
        let prepared = try service.prepareImageFile(image, taskId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        XCTAssertEqual(prepared.fileName, "chat-image-11111111-1111-1111-1111-111111111111.png")
        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.fileURL.path))
        XCTAssertGreaterThan(prepared.fileSize, 0)

        try? FileManager.default.removeItem(at: prepared.fileURL)
    }

    func testChatAttachmentUploadServicePreservesSelectedImageFormat() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let image = NSImage(size: NSSize(width: 10, height: 6))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 6).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try jpeg.write(to: tempFile)

        let service = ChatAttachmentUploadService()
        let prepared = try service.prepareImageFile(fileURL: tempFile, taskId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

        XCTAssertNotEqual(prepared.fileURL, tempFile)
        XCTAssertEqual(prepared.fileName, tempFile.lastPathComponent)
        XCTAssertEqual(prepared.fileURL.lastPathComponent, tempFile.lastPathComponent)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.width, 10)
        XCTAssertEqual(prepared.height, 6)

        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(at: prepared.fileURL.deletingLastPathComponent())
    }

    func testChatAttachmentUploadServiceCopiesSelectedImageForStableUpload() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let image = NSImage(size: NSSize(width: 12, height: 8))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 8).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try jpeg.write(to: tempFile)

        let service = ChatAttachmentUploadService()
        let prepared = try service.prepareImageFile(fileURL: tempFile, taskId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)

        XCTAssertNotEqual(prepared.fileURL, tempFile)
        XCTAssertEqual(prepared.fileName, tempFile.lastPathComponent)
        XCTAssertEqual(prepared.fileURL.lastPathComponent, tempFile.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        try FileManager.default.removeItem(at: tempFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        try? FileManager.default.removeItem(at: prepared.fileURL.deletingLastPathComponent())
    }

    func testChatAttachmentUploadFallsBackWhenDerivedImageUploadFails() async throws {
        let image = NSImage(size: NSSize(width: 16, height: 10))
        image.lockFocus()
        NSColor.orange.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 10).fill()
        image.unlockFocus()

        var uploadPurposes: [String] = []
        let service = ChatAttachmentUploadService(uploadExecutor: { prepared, _, _, _, uploadPurpose in
            uploadPurposes.append(uploadPurpose)
            if prepared.fileName.hasPrefix("chat-thumb") || prepared.fileName.hasPrefix("chat-preview") {
                throw ChatAttachmentUploadError.uploadConnectionTimeout
            }
            return 70001
        })

        let pending = PendingChatImage.pasted(image, id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let attachment = try await service.uploadPendingImage(pending, userId: 188, userName: "18806504525")

        XCTAssertEqual(attachment.fileId, 70001)
        XCTAssertNil(attachment.thumbnailFileId)
        XCTAssertNil(attachment.previewFileId)
        XCTAssertEqual(uploadPurposes, ["CHAT_ATTACHMENT", "CHAT_ATTACHMENT", "CHAT_ATTACHMENT"])
    }

    func testChatInputBarUsesUnifiedSendForTextAndImages() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatInputBar.swift")

        XCTAssertTrue(source.contains("@Binding var pendingImages: [PendingChatImage]"))
        XCTAssertTrue(source.contains("let onRemovePendingImage: (UUID) -> Void"))
        XCTAssertTrue(source.contains("Button(action: onSendMessage)"))
        XCTAssertFalse(source.contains("let onSendImage: () -> Void"))
    }

    func testChatMixedImageSendUsesOptimisticBubbleBeforeUpload() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let socketSource = try sourceFileContents("chat-storage/SocketManager.swift")

        XCTAssertTrue(source.contains("appendLocalChatMessage"))
        XCTAssertTrue(source.contains("updateLocalChatMessage"))
        XCTAssertTrue(source.contains("appendLocalMessage: false"))
        XCTAssertTrue(source.contains("pendingMediaMessages"))
        XCTAssertTrue(socketSource.contains("appendLocalMessage: Bool = true"))
    }

    func testPendingChatImagesUseLocalPreviewStore() throws {
        let modelSource = try sourceFileContents("chat-storage/Services/Chat/ChatAttachmentModels.swift")
        let rowSource = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")

        XCTAssertTrue(modelSource.contains("ChatPendingImageStore"))
        XCTAssertTrue(modelSource.contains("localAttachment()"))
        XCTAssertTrue(rowSource.contains("attachment.isLocalPending"))
        XCTAssertTrue(rowSource.contains("ChatPendingImageStore.shared.image"))
    }

    func testChatMessageRowRendersMixedMediaBubble() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")
        let detailSource = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(source.contains("ChatMediaBubbleView"))
        XCTAssertTrue(source.contains("ChatImageGridView"))
        XCTAssertFalse(source.contains("message.type == \"IMAGE\" ? \"[图片]\" : message.content"))
        XCTAssertFalse(source.contains("@State private var previewContext: ChatImagePreviewContext?"))
        XCTAssertFalse(source.contains(".sheet(item: $previewContext)"))
        XCTAssertTrue(source.contains("onPreviewImage"))
        XCTAssertTrue(source.contains(".highPriorityGesture(TapGesture(count: 1)"))
        XCTAssertTrue(source.contains("previewDirectoryItem()"))
        XCTAssertTrue(source.contains("previewTapNavigationZones"))
        XCTAssertTrue(source.contains("previewNavigationControls"))
        XCTAssertFalse(source.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
        XCTAssertFalse(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertFalse(source.contains(".sheet(item: $selectedAttachment)"))
        XCTAssertTrue(detailSource.contains("@State private var imagePreviewContext: ChatImagePreviewContext?"))
        XCTAssertTrue(detailSource.contains("ChatImagePreviewOverlay"))
        XCTAssertTrue(detailSource.contains("onPreviewImage: openImagePreview"))
    }

    func testSocketManagerCanReuseClientMessageIdForRetry() throws {
        let socketManager = SocketManager()
        let clientMsgId = "retry-client-msg-id"

        socketManager.sendChatMessage(
            receiverId: 7788,
            content: "重试消息",
            clientMsgId: clientMsgId
        )

        XCTAssertEqual(socketManager.chatHistory[7788]?.last?.clientMsgId, clientMsgId)
    }

    func testRetryMessagePassesOriginalClientMessageId() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(source.contains("clientMsgId: msg.clientMsgId"))
    }

    func testRemoteImageThumbnailFetchUsesFullKnownFileSize() throws {
        let fileSize: Int64 = 1_048_576

        XCTAssertEqual(FileThumbnailService.debugRemoteImageFetchLength(fileSize: fileSize), fileSize)
        XCTAssertGreaterThan(FileThumbnailService.debugRemoteImageFetchLength(fileSize: fileSize), 262_144)
    }

    func testVideoStreamingServiceHasTimeoutForUnfinishedImagePreviewLoad() throws {
        let source = try sourceFileContents("chat-storage/Services/VideoStreamingService.swift")

        XCTAssertTrue(source.contains("streamTimeoutSeconds"))
        XCTAssertTrue(source.contains("startStreamTimeout"))
        XCTAssertTrue(source.contains("SocketError.timeout"))
    }

    func testChatImagePreviewUsesIndependentDiskCache() throws {
        let source = try sourceFileContents("chat-storage/Services/FileThumbnailService.swift")

        XCTAssertTrue(source.contains("image-previews"))
        XCTAssertTrue(source.contains("previewMemCache"))
        XCTAssertTrue(source.contains("cachedPreviewImage"))
        XCTAssertTrue(source.contains("savePreviewImageData"))
    }

    func testChatImagePreviewFailureCanBeRetried() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")

        XCTAssertTrue(source.contains("reloadPreviewImage"))
        XCTAssertTrue(source.contains("重新加载"))
    }

    func testChatAttachmentUploadDoesNotPersistTransferTask() throws {
        let uploadServiceSource = try sourceFileContents("chat-storage/Services/Chat/ChatAttachmentUploadService.swift")
        let transferServiceSource = try sourceFileContents("chat-storage/Services/DirectoryService.swift")

        XCTAssertTrue(transferServiceSource.contains("persistTransferTask: Bool = true"))
        XCTAssertTrue(uploadServiceSource.contains("persistTransferTask: false"))
    }

    func testUploadProgressAckWindowAlwaysConfirmsFinalChunk() throws {
        XCTAssertFalse(
            FileTransferService.debugShouldRequestUploadAck(
                nextOffset: 8 * 1024,
                fileSize: 100 * 1024,
                lastAckOffset: 0
            )
        )

        XCTAssertTrue(
            FileTransferService.debugShouldRequestUploadAck(
                nextOffset: 4 * 1024 * 1024,
                fileSize: 100 * 1024 * 1024,
                lastAckOffset: 0
            )
        )

        XCTAssertTrue(
            FileTransferService.debugShouldRequestUploadAck(
                nextOffset: 100 * 1024,
                fileSize: 100 * 1024,
                lastAckOffset: 0
            )
        )
    }

    func testUploadProgressAckWindowUsesDynamicThreshold() throws {
        XCTAssertFalse(
            FileTransferService.debugShouldRequestUploadAck(
                nextOffset: 2 * 1024 * 1024,
                fileSize: 100 * 1024 * 1024,
                lastAckOffset: 0,
                ackWindowBytes: 4 * 1024 * 1024
            )
        )
        XCTAssertTrue(
            FileTransferService.debugShouldRequestUploadAck(
                nextOffset: 4 * 1024 * 1024,
                fileSize: 100 * 1024 * 1024,
                lastAckOffset: 0,
                ackWindowBytes: 4 * 1024 * 1024
            )
        )
    }

    func testUploadProgressAckDecodesAdaptiveFields() throws {
        let json = """
        {
          "status": "progress",
          "taskId": "task-123",
          "uploadedSize": 1048576,
          "serverState": "slow_down",
          "recommendedChunkSize": 65536,
          "recommendedAckWindow": 1048576,
          "serverWriteMillis": 42,
          "retryAfterMs": 120
        }
        """.data(using: .utf8)!

        let ack = try JSONDecoder().decode(StandardAckResponse.self, from: json)

        XCTAssertEqual(ack.serverState, "slow_down")
        XCTAssertEqual(ack.recommendedChunkSize, 65_536)
        XCTAssertEqual(ack.recommendedAckWindow, 1_048_576)
        XCTAssertEqual(ack.serverWriteMillis, 42)
        XCTAssertEqual(ack.retryAfterMs, 120)
    }

    func testResumeAckDecodesInitialAdaptiveStrategy() throws {
        let json = """
        {
          "status": "resume",
          "taskId": "task-123",
          "uploadedSize": 4096,
          "initialChunkSize": 131072,
          "minChunkSize": 32768,
          "maxChunkSize": 524288,
          "initialAckWindow": 2097152,
          "maxAckWindow": 8388608
        }
        """.data(using: .utf8)!

        let ack = try JSONDecoder().decode(ResumeAckResponse.self, from: json)

        XCTAssertEqual(ack.initialChunkSize, 131_072)
        XCTAssertEqual(ack.initialAckWindow, 2_097_152)
        XCTAssertEqual(ack.maxChunkSize, 524_288)
        XCTAssertEqual(ack.maxAckWindow, 8_388_608)
    }

    func testUploadFinalizeTimeoutScalesForLargeFiles() throws {
        XCTAssertEqual(
            FileTransferService.debugUploadFinalizeTimeout(fileSize: 10 * 1024 * 1024),
            60,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            FileTransferService.debugUploadFinalizeTimeout(fileSize: 10 * 1024 * 1024 * 1024),
            60
        )
        XCTAssertEqual(
            FileTransferService.debugUploadFinalizeTimeout(fileSize: 100 * 1024 * 1024 * 1024),
            600,
            accuracy: 0.001
        )
    }

    func testUploadDataFramePayloadIncludesBigEndianOffsetPrefix() throws {
        let payload = FileTransferService.debugBuildUploadDataPayload(
            offset: 8192,
            data: Data([0xAA, 0xBB, 0xCC])
        )

        XCTAssertEqual(Frame.FLAG_HAS_OFFSET, 0x04)
        XCTAssertEqual(payload.count, 11)
        XCTAssertEqual(Array(payload.prefix(8)), [0, 0, 0, 0, 0, 0, 0x20, 0])
        XCTAssertEqual(Array(payload.suffix(3)), [0xAA, 0xBB, 0xCC])
    }

    func testUploadProgressAckBehindRewindsAndRetriesFromServerOffset() throws {
        let source = try sourceFileContents("chat-storage/Services/DirectoryService.swift")

        XCTAssertTrue(source.contains("confirmedOffset < nextOffset"))
        XCTAssertTrue(source.contains("fileHandle.seek(toOffset: UInt64(confirmedOffset))"))
        XCTAssertTrue(source.contains("currentOffset = confirmedOffset"))
        XCTAssertTrue(source.contains("lastAckOffset = confirmedOffset"))
    }

    func testUploadProgressAckRejectsNegativeOrAdvancedOffset() throws {
        XCTAssertThrowsError(
            try FileTransferService.debugValidateUploadAckOffset(
                uploadedSize: -1,
                expectedOffset: 1024
            )
        )
        XCTAssertThrowsError(
            try FileTransferService.debugValidateUploadAckOffset(
                uploadedSize: 2048,
                expectedOffset: 1024
            )
        )
        XCTAssertNoThrow(
            try FileTransferService.debugValidateUploadAckOffset(
                uploadedSize: 512,
                expectedOffset: 1024
            )
        )
    }

    func testUploadRecoveryRetriesOnlyTransientNetworkErrors() throws {
        XCTAssertTrue(TransferTaskManager.isRecoverableUploadError(SocketError.timeout))
        XCTAssertTrue(TransferTaskManager.isRecoverableUploadError(SocketError.connectionClosed))
        XCTAssertTrue(TransferTaskManager.isRecoverableUploadError(FileTransferError.connectionLost))

        XCTAssertFalse(TransferTaskManager.isRecoverableUploadError(SocketError.invalidResponse))
        XCTAssertFalse(
            TransferTaskManager.isRecoverableUploadError(
                FileTransferError.serverError("MD5 校验失败")
            )
        )
    }

    func testUserResponseDecodesTransferToken() throws {
        let json = """
        {"userId":1001,"userName":"18806504525","transferToken":"signed-transfer-token"}
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(UserDO.self, from: json)

        XCTAssertEqual(user.transferToken, "signed-transfer-token")
    }

    func testSocketManagerSupportsResponseMatcherAndWriteDeadline() throws {
        let source = try sourceFileContents("chat-storage/SocketManager.swift")

        XCTAssertTrue(source.contains("continuationMatchers"))
        XCTAssertTrue(source.contains("matching responseMatcher"))
        XCTAssertTrue(source.contains("writeDeadline"))
        XCTAssertTrue(source.contains("SocketError.timeout"))
    }

    func testUploadProtocolUsesCanonicalTaskIdAndTransferToken() throws {
        let source = try sourceFileContents("chat-storage/Services/DirectoryService.swift")

        XCTAssertTrue(source.contains("transferToken"))
        XCTAssertTrue(source.contains("resumeInfo.status == \"complete\""))
        XCTAssertFalse(source.contains("将优先使用服务端的"))
    }

    func testUploadTaskUsesCurrentAuthenticatedIdentityInsteadOfPersistedIdentity() throws {
        let currentUser = UserDO(
            id: 7,
            username: "18806504525",
            nickname: nil,
            avatar: nil,
            email: nil,
            phone: nil,
            createTime: nil,
            updateTime: nil,
            status: nil,
            transferToken: "transfer-token"
        )

        let identity = try TransferTaskManager.resolveUploadIdentity(currentUser: currentUser)

        XCTAssertEqual(identity.userId, 7)
        XCTAssertEqual(identity.userName, "18806504525")
    }

    func testUploadTaskRejectsResumeWhenLoginStateIsMissing() throws {
        XCTAssertThrowsError(try TransferTaskManager.resolveUploadIdentity(currentUser: nil))
    }

    func testPartialTransferTaskUpdateDoesNotOverwritePersistedUserName() throws {
        let source = try sourceFileContents("chat-storage/Persistence.swift")

        XCTAssertTrue(source.contains("userName: String? = nil"))
        XCTAssertFalse(source.contains("userName: String? = \"default\""))
    }

    func testUploadResponseMatcherAcceptsTaskScopedResponse() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "taskId": "task-123",
            "status": "resume"
        ])
        let frame = Frame(type: .resumeAck, data: data)

        XCTAssertTrue(FileTransferService.debugFrame(frame, matchesTaskId: "task-123"))
        XCTAssertFalse(FileTransferService.debugFrame(frame, matchesTaskId: "task-456"))
    }

    func testUploadResponseMatcherAcceptsUnscopedServerError() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "error",
            "message": "上传用户身份不一致"
        ])
        let frame = Frame(type: .resumeAck, data: data)

        XCTAssertTrue(FileTransferService.debugFrame(frame, matchesTaskId: "task-123"))
    }

    func testDownloadResumeUsesActualPartFileSize() throws {
        XCTAssertEqual(
            FileDownloadService.debugResolveResumeOffset(
                persistedOffset: 800,
                localPartSize: 640,
                remoteFileSize: 1_000
            ),
            640
        )
        XCTAssertEqual(
            FileDownloadService.debugResolveResumeOffset(
                persistedOffset: 400,
                localPartSize: 700,
                remoteFileSize: 1_000
            ),
            700
        )
    }

    func testDownloadCompletionRequiresExactFinalSize() throws {
        XCTAssertTrue(FileDownloadService.debugIsComplete(localSize: 1_000, remoteFileSize: 1_000))
        XCTAssertFalse(FileDownloadService.debugIsComplete(localSize: 999, remoteFileSize: 1_000))
        XCTAssertFalse(FileDownloadService.debugIsComplete(localSize: 1_001, remoteFileSize: 1_000))
    }

    func testDownloadWritesPartFileWithoutDroppingBackpressureFrames() throws {
        let source = try sourceFileContents("chat-storage/Services/FileDownloadService.swift")

        XCTAssertTrue(source.contains("partFileURL"))
        XCTAssertTrue(source.contains("pauseInputEvents"))
        XCTAssertTrue(source.contains("resumeInputEvents"))
        XCTAssertFalse(source.contains("Thread.sleep(forTimeInterval: 0.05)"))
        XCTAssertTrue(source.contains("sentBytes"))
        XCTAssertTrue(source.contains("replaceItemAt"))
    }

    func testChatMixedImageMessageContentRoundTripsTextAndImages() throws {
        let attachments = [
            ChatImageAttachment(
                fileId: 10001,
                fileName: "IMG_10001.HEIC",
                fileSize: 18_500_000,
                mimeType: "image/heic",
                width: 4032,
                height: 3024
            ),
            ChatImageAttachment(
                fileId: 10002,
                fileName: "sticker.webp",
                fileSize: 980_000,
                mimeType: "image/webp",
                width: 1200,
                height: 900
            )
        ]
        let payload = try ChatMixedMessageContent(text: "图片下面的文字", attachments: attachments)

        let content = try payload.contentString()
        let parsed = try XCTUnwrap(ChatMixedMessageContent.parse(content))

        XCTAssertEqual(parsed.text, "图片下面的文字")
        XCTAssertEqual(parsed.attachments, attachments)
        XCTAssertEqual(ChatMessagePayload.parse(content: content, msgType: "MIXED").displayText, "[2张图片] 图片下面的文字")
    }

    func testChatMessagePayloadKeepsExplicitTextJsonAsText() throws {
        let attachment = ChatImageAttachment(
            fileId: 10003,
            fileName: "json-looking-image.png",
            fileSize: 4096,
            mimeType: "image/png"
        )
        let payload = try ChatMixedMessageContent(text: "这是一段 JSON 文本", attachments: [attachment])
        let content = try payload.contentString()

        XCTAssertEqual(ChatMessagePayload.parse(content: content, msgType: "TEXT"), .text(content))
        XCTAssertEqual(ChatMessagePayload.parse(content: content, msgType: "").displayText, "[图片] 这是一段 JSON 文本")
    }

    func testChatMixedImageMessageRejectsMoreThanNineImages() throws {
        let attachments = (1...10).map { index in
            ChatImageAttachment(
                fileId: Int64(index),
                fileName: "image-\(index).jpg",
                fileSize: 1024,
                mimeType: "image/jpeg"
            )
        }

        XCTAssertThrowsError(try ChatMixedMessageContent(text: "", attachments: attachments)) { error in
            XCTAssertEqual(error as? ChatMixedMessageError, .tooManyImages)
        }
    }

    func testChatImageFormatSupportsCommonModernFormats() throws {
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "photo.JPG"), "image/jpeg")
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "live.HEIC"), "image/heic")
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "graphic.webp"), "image/webp")
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "scan.tiff"), "image/tiff")
        XCTAssertTrue(ChatImageFormat.isSupported(fileName: "paste.png"))
        XCTAssertFalse(ChatImageFormat.isSupported(fileName: "archive.zip"))
    }

    private func sourceFileContents(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func testAdaptiveUploadControllerStartsWithConservativeParameters() throws {
        let decision = AdaptiveUploadController().currentDecision

        XCTAssertEqual(decision.chunkSize, 65_536)
        XCTAssertEqual(decision.ackWindowBytes, 1_048_576)
        XCTAssertEqual(decision.ackTimeout, 30, accuracy: 0.001)
        XCTAssertFalse(decision.isCoolingDown)
        XCTAssertFalse(decision.shouldPause)
        XCTAssertNil(decision.retryAfterMs)
    }

    func testAdaptiveUploadControllerRaisesAfterTwoHealthyWindows() throws {
        var controller = AdaptiveUploadController()

        let first = controller.record(adaptiveObservation())
        let second = controller.record(adaptiveObservation())

        XCTAssertEqual(first.chunkSize, 65_536)
        XCTAssertEqual(first.ackWindowBytes, 1_048_576)
        XCTAssertEqual(second.chunkSize, 131_072)
        XCTAssertEqual(second.ackWindowBytes, 2_097_152)
    }

    func testAdaptiveUploadControllerAppliesMetricEWMAsAndDynamicTimeout() throws {
        var controller = AdaptiveUploadController()

        _ = controller.record(adaptiveObservation(rtt: 0.1, windowBytes: 1_048_576, windowDuration: 1))
        let decision = controller.record(
            adaptiveObservation(
                rtt: 0.5,
                windowBytes: 1_048_576,
                windowDuration: 0.5,
                serverState: .pause,
                retryAfterMs: 250
            )
        )

        XCTAssertEqual(controller.smoothedRTT, 0.18, accuracy: 0.000_001)
        XCTAssertEqual(controller.smoothedGoodput, 1_310_720, accuracy: 0.001)
        XCTAssertEqual(decision.ackTimeout, 10, accuracy: 0.001)
    }

    func testAdaptiveUploadControllerCalculatesUnclampedTimeoutFromGoodput() throws {
        var controller = AdaptiveUploadController()

        let decision = controller.record(
            adaptiveObservation(rtt: 0.5, windowBytes: 131_072, windowDuration: 1)
        )

        XCTAssertEqual(decision.ackTimeout, 18, accuracy: 0.001)
    }

    func testAdaptiveUploadControllerStaysWithinMaximumParametersAndTimeout() throws {
        var controller = AdaptiveUploadController()
        var decision = controller.currentDecision

        for _ in 0..<10 {
            decision = controller.record(
                adaptiveObservation(rtt: 0.1, windowBytes: 65_536, windowDuration: 1)
            )
        }

        XCTAssertEqual(decision.chunkSize, 524_288)
        XCTAssertEqual(decision.ackWindowBytes, 8_388_608)
        XCTAssertEqual(decision.ackTimeout, 60, accuracy: 0.001)
    }

    func testAdaptiveUploadControllerTreatsServerRecommendationsAsOutputCaps() throws {
        var controller = AdaptiveUploadController()

        let capped = controller.record(
            adaptiveObservation(
                recommendedChunkSize: 49_152,
                recommendedAckWindowBytes: 1_048_576
            )
        )
        let uncapped = controller.record(adaptiveObservation())

        XCTAssertEqual(capped.chunkSize, 49_152)
        XCTAssertEqual(capped.ackWindowBytes, 1_048_576)
        XCTAssertEqual(uncapped.chunkSize, 131_072)
        XCTAssertEqual(uncapped.ackWindowBytes, 2_097_152)
    }

    func testAdaptiveUploadControllerPausesForRecommendationsBelowProtocolMinimums() throws {
        var controller = AdaptiveUploadController()

        let invalidChunk = controller.record(
            adaptiveObservation(
                recommendedChunkSize: 1,
                recommendedAckWindowBytes: 1_048_576,
                retryAfterMs: 750
            )
        )
        let resumed = controller.record(adaptiveObservation())

        var ackController = AdaptiveUploadController()
        let invalidAckWindow = ackController.record(
            adaptiveObservation(recommendedAckWindowBytes: 1)
        )

        XCTAssertTrue(invalidChunk.shouldPause)
        XCTAssertEqual(invalidChunk.retryAfterMs, 750)
        XCTAssertEqual(invalidChunk.chunkSize, 32_768)
        XCTAssertEqual(invalidChunk.ackWindowBytes, 1_048_576)
        XCTAssertEqual(resumed.chunkSize, 65_536)

        XCTAssertTrue(invalidAckWindow.shouldPause)
        XCTAssertGreaterThan(invalidAckWindow.retryAfterMs ?? 0, 0)
        XCTAssertEqual(invalidAckWindow.chunkSize, 32_768)
        XCTAssertEqual(invalidAckWindow.ackWindowBytes, 1_048_576)
    }

    func testAdaptiveUploadControllerHalvesImmediatelyForEveryCongestionSignal() throws {
        let signals: [AdaptiveUploadController.Observation] = [
            adaptiveObservation(serverState: .slowDown),
            adaptiveObservation(serverState: .error),
            adaptiveObservation(isOffsetBehind: true),
            adaptiveObservation(rtt: nil, windowBytes: 0, windowDuration: 0, didTimeout: true),
            adaptiveObservation(rtt: nil, windowBytes: 0, windowDuration: 0, didDisconnect: true),
            adaptiveObservation(rtt: 1.0),
            adaptiveObservation(socketWriteWaitRatio: 0.41)
        ]

        for (index, signal) in signals.enumerated() {
            var controller = AdaptiveUploadController()
            _ = controller.record(adaptiveObservation())
            _ = controller.record(adaptiveObservation())

            let decision = controller.record(signal)

            XCTAssertEqual(decision.chunkSize, 65_536, "signal index \(index)")
            XCTAssertEqual(decision.ackWindowBytes, 1_048_576, "signal index \(index)")
            XCTAssertTrue(decision.isCoolingDown, "signal index \(index)")
        }
    }

    func testAdaptiveUploadControllerCooldownRequiresThreeHealthyWindowsBeforeGrowthResumes() throws {
        var controller = AdaptiveUploadController()
        _ = controller.record(adaptiveObservation())
        _ = controller.record(adaptiveObservation())
        let reduced = controller.record(adaptiveObservation(serverState: .slowDown))

        let cooldownOne = controller.record(adaptiveObservation())
        let cooldownTwo = controller.record(adaptiveObservation())
        let cooldownThree = controller.record(adaptiveObservation())
        let probeOne = controller.record(adaptiveObservation())
        let promoted = controller.record(adaptiveObservation())

        XCTAssertEqual(reduced.chunkSize, 65_536)
        XCTAssertTrue(cooldownOne.isCoolingDown)
        XCTAssertTrue(cooldownTwo.isCoolingDown)
        XCTAssertFalse(cooldownThree.isCoolingDown)
        XCTAssertEqual(probeOne.chunkSize, 65_536)
        XCTAssertEqual(promoted.chunkSize, 131_072)
        XCTAssertEqual(promoted.ackWindowBytes, 2_097_152)
    }

    func testAdaptiveUploadControllerPauseWaitsWithoutAdvancingHealthyCount() throws {
        var controller = AdaptiveUploadController()
        _ = controller.record(adaptiveObservation())

        let paused = controller.record(
            adaptiveObservation(serverState: .pause, retryAfterMs: 750)
        )
        let resumed = controller.record(adaptiveObservation())

        XCTAssertTrue(paused.shouldPause)
        XCTAssertEqual(paused.retryAfterMs, 750)
        XCTAssertEqual(paused.chunkSize, 65_536)
        XCTAssertEqual(resumed.chunkSize, 131_072)
        XCTAssertEqual(resumed.ackWindowBytes, 2_097_152)
    }

    func testAdaptiveUploadControllerPauseStillHalvesForCongestionSignals() throws {
        let pauseSignals: [AdaptiveUploadController.Observation] = [
            adaptiveObservation(serverState: .pause, retryAfterMs: 500, isOffsetBehind: true),
            adaptiveObservation(serverState: .pause, retryAfterMs: 500, socketWriteWaitRatio: 0.41),
            adaptiveObservation(serverState: .pause, retryAfterMs: 500, didTimeout: true),
            adaptiveObservation(serverState: .pause, retryAfterMs: 500, didDisconnect: true),
            adaptiveObservation(rtt: 1.0, serverState: .pause, retryAfterMs: 500)
        ]

        for (index, signal) in pauseSignals.enumerated() {
            var controller = AdaptiveUploadController()
            _ = controller.record(adaptiveObservation())
            _ = controller.record(adaptiveObservation())

            let decision = controller.record(signal)

            XCTAssertTrue(decision.shouldPause, "signal index \(index)")
            XCTAssertEqual(decision.retryAfterMs, 500, "signal index \(index)")
            XCTAssertEqual(decision.chunkSize, 65_536, "signal index \(index)")
            XCTAssertEqual(decision.ackWindowBytes, 1_048_576, "signal index \(index)")
            XCTAssertTrue(decision.isCoolingDown, "signal index \(index)")
        }
    }

    func testAdaptiveUploadControllerRejectsInvalidMetricsWithoutPollutingEWMAs() throws {
        let invalidObservations: [AdaptiveUploadController.Observation] = [
            adaptiveObservation(rtt: nil, windowBytes: 524_288, windowDuration: 2),
            adaptiveObservation(rtt: -0.1, windowBytes: 524_288, windowDuration: 2),
            adaptiveObservation(rtt: .nan, windowBytes: 524_288, windowDuration: 2),
            adaptiveObservation(rtt: .infinity, windowBytes: 524_288, windowDuration: 2),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: 0),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: -1),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: .nan),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: .infinity),
            adaptiveObservation(rtt: 0.5, windowBytes: 0, windowDuration: 2),
            adaptiveObservation(rtt: 0.5, windowBytes: -1, windowDuration: 2),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: 2, socketWriteWaitRatio: -0.1),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: 2, socketWriteWaitRatio: 1.1),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: 2, socketWriteWaitRatio: .nan),
            adaptiveObservation(rtt: 0.5, windowBytes: 524_288, windowDuration: 2, socketWriteWaitRatio: .infinity),
            adaptiveObservation(
                rtt: 0.5,
                windowBytes: Int.max,
                windowDuration: .leastNonzeroMagnitude
            )
        ]

        for (index, observation) in invalidObservations.enumerated() {
            var controller = AdaptiveUploadController()
            _ = controller.record(adaptiveObservation())
            _ = controller.record(adaptiveObservation())
            let baselineRTT = controller.smoothedRTT
            let baselineGoodput = controller.smoothedGoodput

            let decision = controller.record(observation)

            XCTAssertEqual(decision.chunkSize, 65_536, "observation index \(index)")
            XCTAssertEqual(decision.ackWindowBytes, 1_048_576, "observation index \(index)")
            XCTAssertTrue(decision.isCoolingDown, "observation index \(index)")
            XCTAssertEqual(controller.smoothedRTT, baselineRTT, accuracy: 0.000_001, "observation index \(index)")
            XCTAssertEqual(controller.smoothedGoodput, baselineGoodput, accuracy: 0.001, "observation index \(index)")
        }
    }

    func testAdaptiveUploadControllerRepeatedFailuresRespectMinimumParameters() throws {
        var controller = AdaptiveUploadController()
        _ = controller.record(adaptiveObservation())
        _ = controller.record(adaptiveObservation())

        _ = controller.record(adaptiveObservation(serverState: .slowDown))
        _ = controller.record(adaptiveObservation(serverState: .slowDown))
        let minimum = controller.record(adaptiveObservation(serverState: .slowDown))

        XCTAssertEqual(minimum.chunkSize, 32_768)
        XCTAssertEqual(minimum.ackWindowBytes, 1_048_576)
    }

    private func adaptiveObservation(
        rtt: TimeInterval? = 0.1,
        windowBytes: Int = 1_048_576,
        windowDuration: TimeInterval = 0.4,
        serverState: AdaptiveUploadController.ServerState = .normal,
        recommendedChunkSize: Int? = nil,
        recommendedAckWindowBytes: Int? = nil,
        retryAfterMs: Int? = nil,
        isOffsetBehind: Bool = false,
        socketWriteWaitRatio: Double = 0,
        didTimeout: Bool = false,
        didDisconnect: Bool = false
    ) -> AdaptiveUploadController.Observation {
        AdaptiveUploadController.Observation(
            ackRTT: rtt,
            windowBytes: windowBytes,
            windowDuration: windowDuration,
            serverState: serverState,
            recommendedChunkSize: recommendedChunkSize,
            recommendedAckWindowBytes: recommendedAckWindowBytes,
            retryAfterMs: retryAfterMs,
            isOffsetBehind: isOffsetBehind,
            socketWriteWaitRatio: socketWriteWaitRatio,
            didTimeout: didTimeout,
            didDisconnect: didDisconnect
        )
    }

    func testFileDtoDecodesServerParentDirectoryFields() throws {
        let json = """
        {
          "id": 7475479260124168192,
          "parentId": 7428297864713543680,
          "parentDirName": "欧美",
          "fileName": "movie.mp4",
          "filePath": "/tmp/movie.mp4",
          "fileSize": 1024,
          "fileType": "mp4",
          "isFile": "Y",
          "isExist": "Y",
          "hasChild": "N"
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(FileDto.self, from: json)

        XCTAssertEqual(file.pId, 7428297864713543680)
        XCTAssertEqual(file.parentDirName, "欧美")
        XCTAssertEqual(file.toDirectoryItem().directoryName, "欧美")
    }

    func testOnlyUploadCompletionRequestsFileListRefresh() throws {
        XCTAssertTrue(TransferTaskManager.shouldPostFileListRefresh(for: .upload))
        XCTAssertFalse(TransferTaskManager.shouldPostFileListRefresh(for: .download))
    }

}
