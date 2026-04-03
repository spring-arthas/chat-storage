//
//  chat_storageTests.swift
//  chat-storageTests
//
//  Created by HLJY on 2026/1/29.
//

import XCTest
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

}
