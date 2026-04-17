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

    func testMainWindowLayoutBoundsAreFixed() throws {
        XCTAssertEqual(AppWindowLayout.mainWidth, 1240)
        XCTAssertEqual(AppWindowLayout.mainHeight, 760)
        XCTAssertEqual(AppWindowLayout.loginWidth, 500)
        XCTAssertEqual(AppWindowLayout.loginHeight, 550)
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

}
