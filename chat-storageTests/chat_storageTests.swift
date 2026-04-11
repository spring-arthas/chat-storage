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

    func testMainWindowLayoutBoundsAreReasonable() throws {
        XCTAssertEqual(AppWindowLayout.mainMinWidth, 1080)
        XCTAssertEqual(AppWindowLayout.mainMinHeight, 700)
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

}
