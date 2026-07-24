//
//  chat_storageTests.swift
//  chat-storageTests
//
//  Created by HLJY on 2026/1/29.
//

import XCTest
import Network
import CoreData
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
        let compact = FileDetailLayoutMetrics(availableHeight: 650, availableWidth: 320)
        let regular = FileDetailLayoutMetrics(availableHeight: 900, availableWidth: 460)

        XCTAssertLessThan(compact.previewHeight, regular.previewHeight)
        XCTAssertLessThanOrEqual(compact.sectionSpacing, regular.sectionSpacing)
        XCTAssertEqual(compact.actionButtonHeight, 34)
    }

    func testAppAppearanceModesMapToExpectedColorSchemes() throws {
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }

    func testAppSettingsCategoriesStayStable() throws {
        XCTAssertEqual(AppSettingsCategory.allCases.map(\.title), ["个人资料", "外观", "文件传输", "存储与缓存", "网络连接"])
    }

    func testCacheSizeFormatterDisplaysZeroWithoutUnit() throws {
        XCTAssertEqual(CacheSizeFormatter.string(fromByteCount: 0), "0")
    }

    func testCacheCleanupServiceDoesNotManageSocketLifecycle() throws {
        let source = try sourceFileContents("chat-storage/Services/CacheCleanupService.swift")

        XCTAssertFalse(source.contains("SocketManager"))
        XCTAssertFalse(source.contains(".disconnect("))
        XCTAssertFalse(source.contains(".connect("))
        XCTAssertFalse(source.contains(".switchConnection("))
    }

    func testMacAppIconCatalogReferencesEveryRequiredRaster() throws {
        let catalogPath = "chat-storage/Assets.xcassets/AppIcon.appiconset/Contents.json"
        let catalogSource = try sourceFileContents(catalogPath)
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(catalogSource.utf8)) as? [String: Any]
        )
        let images = try XCTUnwrap(catalog["images"] as? [[String: Any]])
        let expectedFilenames = [
            "16x16-1x": "icon_16x16.png",
            "16x16-2x": "icon_16x16@2x.png",
            "32x32-1x": "icon_32x32.png",
            "32x32-2x": "icon_32x32@2x.png",
            "128x128-1x": "icon_128x128.png",
            "128x128-2x": "icon_128x128@2x.png",
            "256x256-1x": "icon_256x256.png",
            "256x256-2x": "icon_256x256@2x.png",
            "512x512-1x": "icon_512x512.png",
            "512x512-2x": "icon_512x512@2x.png"
        ]

        XCTAssertEqual(images.count, expectedFilenames.count)

        for image in images {
            let size = try XCTUnwrap(image["size"] as? String)
            let scale = try XCTUnwrap(image["scale"] as? String)
            let key = "\(size)-\(scale)"
            let expectedFilename = try XCTUnwrap(expectedFilenames[key])
            let filename = try XCTUnwrap(image["filename"] as? String)

            XCTAssertEqual(filename, expectedFilename)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: projectFileURL(
                        "chat-storage/Assets.xcassets/AppIcon.appiconset/\(filename)"
                    ).path
                ),
                "Missing AppIcon raster: \(filename)"
            )
        }
    }

    func testAppBrandingUsesDuyaoWithoutRenamingProductIdentity() throws {
        let project = try sourceFileContents("chat-storage.xcodeproj/project.pbxproj")
        let infoPlistPath = "chat-storage/Info.plist"
        let infoPlistURL = projectFileURL(infoPlistPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path))
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else { return }

        let infoPlist = try sourceFileContents(infoPlistPath)
        let debugConfiguration = try sourceSlice(
            project,
            from: "4E15EB442F2B48250093C805 /* Debug */ = {",
            to: "4E15EB452F2B48250093C805 /* Release */ = {"
        )
        let releaseConfiguration = try sourceSlice(
            project,
            from: "4E15EB452F2B48250093C805 /* Release */ = {",
            to: "4E15EB472F2B48250093C805 /* Debug */ = {"
        )

        for configuration in [debugConfiguration, releaseConfiguration] {
            XCTAssertTrue(configuration.contains("GENERATE_INFOPLIST_FILE = NO;"))
            XCTAssertTrue(configuration.contains("INFOPLIST_FILE = \"chat-storage/Info.plist\";"))
            XCTAssertFalse(configuration.contains("INFOPLIST_KEY_CFBundle"))
            XCTAssertTrue(configuration.contains("PRODUCT_BUNDLE_IDENTIFIER = \"duyao.chat-storage\";"))
            XCTAssertTrue(configuration.contains("PRODUCT_NAME = \"$(TARGET_NAME)\";"))
        }

        XCTAssertTrue(infoPlist.contains("<key>CFBundleDisplayName</key>"))
        XCTAssertTrue(infoPlist.contains("<key>CFBundleName</key>"))
        XCTAssertEqual(
            infoPlist.components(separatedBy: "<string>毒药</string>").count - 1,
            2
        )
        XCTAssertTrue(infoPlist.contains("<string>$(EXECUTABLE_NAME)</string>"))
        XCTAssertTrue(infoPlist.contains("<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>"))

        XCTAssertEqual(
            project.components(
                separatedBy: "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/chat-storage.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/chat-storage\";"
            ).count - 1,
            2
        )
    }

    func testAppStartupRefreshesDockIconFromBundledIcns() throws {
        let source = try sourceFileContents("chat-storage/chat_storageApp.swift")

        XCTAssertTrue(source.contains("Self.refreshDockIcon()"))
        XCTAssertTrue(
            source.contains(
                "Bundle.main.url(forResource: \"AppIcon\", withExtension: \"icns\")"
            )
        )
        XCTAssertTrue(source.contains("NSApplication.shared.applicationIconImage = icon"))
    }

    func testHistoryRequestEncodesOnlySelectedCursor() throws {
        let request = ChatHistoryRequestDto(friendId: 7, beforeMessageId: 99, limit: 20)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["friendId"] as? Int32, 7)
        XCTAssertEqual(json["beforeMessageId"] as? Int64, 99)
        XCTAssertNil(json["afterMessageId"])
        XCTAssertNil(json["offset"])
    }

    func testHistoryResponseDecodesCursorMetadataAndLegacyDefaults() throws {
        let newResponse = """
        {
          "list": [{"id": 100, "senderId": 7, "receiverId": 8, "content": "new", "gmtCreated": 1721640000000}],
          "hasMore": true,
          "nextBeforeMessageId": 80,
          "latestMessageId": 100
        }
        """.data(using: .utf8)!
        let newPage = try JSONDecoder().decode(ChatHistoryResponseDataDto.self, from: newResponse)

        XCTAssertTrue(newPage.hasMore)
        XCTAssertEqual(newPage.nextBeforeMessageId, 80)
        XCTAssertEqual(newPage.latestMessageId, 100)
        XCTAssertEqual(newPage.list.first?.gmtCreated, 1_721_640_000_000)
        XCTAssertNil(newPage.avatars)

        let legacyResponse = """
        {"list": [{"id": 5}, {"id": 6}]}
        """.data(using: .utf8)!
        let legacyPage = try JSONDecoder().decode(ChatHistoryResponseDataDto.self, from: legacyResponse)

        XCTAssertFalse(legacyPage.hasMore)
        XCTAssertEqual(legacyPage.nextBeforeMessageId, 5)
        XCTAssertEqual(legacyPage.latestMessageId, 6)
    }

    func testHistoryMergeDeduplicatesAndKeepsAscendingServerIds() {
        let existing = [historyMessage(id: 2), historyMessage(id: 3)]
        let incoming = [historyMessage(id: 1), historyMessage(id: 2, content: "updated")]

        let merged = ChatHistoryMergePolicy.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.compactMap(\.messageId), [1, 2, 3])
        XCTAssertEqual(merged.first(where: { $0.messageId == 2 })?.content, "updated")
    }

    func testHistoryMergeReconcilesOptimisticMessageByClientMessageId() {
        let optimistic = historyMessage(id: nil, clientMsgId: "client-1", content: "sending", status: .sending)
        let confirmed = historyMessage(id: 42, clientMsgId: "client-1", content: "sent", status: .success)

        let merged = ChatHistoryMergePolicy.merge(existing: [optimistic], incoming: [confirmed])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.messageId, 42)
        XCTAssertEqual(merged.first?.content, "sent")
        XCTAssertEqual(merged.first?.sendStatus, .success)
    }

    func testHistoryWindowLatestKeepsNewestMessagesAndReportsOlderTrim() {
        let result = ChatHistoryWindowPolicy.merge(
            existing: [historyMessage(id: 1), historyMessage(id: 2), historyMessage(id: 3)],
            incoming: [historyMessage(id: 4), historyMessage(id: 5)],
            direction: .latest,
            limit: 3
        )

        XCTAssertEqual(result.messages.compactMap(\.messageId), [3, 4, 5])
        XCTAssertTrue(result.droppedOlder)
        XCTAssertFalse(result.droppedNewer)
    }

    func testHistoryWindowOlderKeepsLoadedOlderSideAndReportsNewerTrim() {
        let result = ChatHistoryWindowPolicy.merge(
            existing: [historyMessage(id: 3), historyMessage(id: 4), historyMessage(id: 5)],
            incoming: [historyMessage(id: 1), historyMessage(id: 2)],
            direction: .older,
            limit: 3
        )

        XCTAssertEqual(result.messages.compactMap(\.messageId), [1, 2, 3])
        XCTAssertFalse(result.droppedOlder)
        XCTAssertTrue(result.droppedNewer)
    }

    func testHistoryWindowNewerKeepsLoadedNewerSideAndReportsOlderTrim() {
        let result = ChatHistoryWindowPolicy.merge(
            existing: [historyMessage(id: 1), historyMessage(id: 2), historyMessage(id: 3)],
            incoming: [historyMessage(id: 4), historyMessage(id: 5)],
            direction: .newer,
            limit: 3
        )

        XCTAssertEqual(result.messages.compactMap(\.messageId), [3, 4, 5])
        XCTAssertTrue(result.droppedOlder)
        XCTAssertFalse(result.droppedNewer)
    }

    func testEmptyHistoryCursorHasNoNewerWindow() {
        XCTAssertFalse(ChatHistoryCursorState.empty.hasNewer)
    }

    func testChatHistoryStoreUpsertsByAccountFriendAndMessageId() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)

        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 10, content: "old")]
        )
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 10, content: "new")]
        )

        let records = try await store.fetchLatest(accountId: 1, friendId: 2, limit: 20)
        XCTAssertEqual(records.map(\.content), ["new"])
        XCTAssertEqual(records.compactMap(\.messageId), [10])
    }

    func testChatHistoryStoreIsolatesAccounts() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 10, content: "account-one")]
        )

        let otherAccount = try await store.fetchLatest(accountId: 9, friendId: 2, limit: 20)
        XCTAssertTrue(otherAccount.isEmpty)
    }

    func testChatHistoryStorePreservesLongServerMessageIds() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 5_000_000_000, content: "long-id")]
        )

        let records = try await store.fetchLatest(accountId: 1, friendId: 2, limit: 20)
        XCTAssertEqual(records.compactMap(\.messageId), [5_000_000_000])
    }

    func testChatHistoryStoreFetchesOlderMessagesBeforeCursor() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [
                try historyItem(id: 1, content: "one"),
                try historyItem(id: 2, content: "two"),
                try historyItem(id: 3, content: "three")
            ]
        )

        let firstPage = try await store.fetchOlder(
            accountId: 1,
            friendId: 2,
            beforeMessageId: 4,
            limit: 2
        )
        XCTAssertEqual(firstPage.messages.compactMap(\.messageId), [2, 3])
        XCTAssertTrue(firstPage.hasMore)

        let lastPage = try await store.fetchOlder(
            accountId: 1,
            friendId: 2,
            beforeMessageId: 2,
            limit: 2
        )
        XCTAssertEqual(lastPage.messages.compactMap(\.messageId), [1])
        XCTAssertFalse(lastPage.hasMore)
    }

    func testChatHistoryStoreFetchesNewerMessagesAfterCursor() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [
                try historyItem(id: 1, content: "one"),
                try historyItem(id: 2, content: "two"),
                try historyItem(id: 3, content: "three"),
                try historyItem(id: 4, content: "four")
            ]
        )

        let firstPage = try await store.fetchNewer(
            accountId: 1,
            friendId: 2,
            afterMessageId: 1,
            limit: 2
        )
        XCTAssertEqual(firstPage.messages.compactMap(\.messageId), [2, 3])
        XCTAssertTrue(firstPage.hasMore)

        let lastPage = try await store.fetchNewer(
            accountId: 1,
            friendId: 2,
            afterMessageId: 3,
            limit: 2
        )
        XCTAssertEqual(lastPage.messages.compactMap(\.messageId), [4])
        XCTAssertFalse(lastPage.hasMore)
    }

    func testChatHistoryModelDefinesCompositeConversationCursorIndex() throws {
        let source = try sourceFileContents(
            "chat-storage/chat_storage.xcdatamodeld/chat_storage.xcdatamodel/contents"
        )
        let indexSource = try sourceSlice(
            source,
            from: "<fetchIndex name=\"byAccountFriendAndMessage\">",
            to: "</fetchIndex>"
        )

        XCTAssertTrue(indexSource.contains("property=\"accountId\""))
        XCTAssertTrue(indexSource.contains("property=\"friendId\""))
        XCTAssertTrue(indexSource.contains("property=\"messageId\""))
    }

    func testDeletingConversationOnlyDeletesSelectedAccountAndFriend() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 10, content: "delete")]
        )
        try await store.upsert(
            accountId: 1,
            friendId: 3,
            items: [try historyItem(id: 11, content: "keep-friend")]
        )
        try await store.upsert(
            accountId: 9,
            friendId: 2,
            items: [try historyItem(id: 12, content: "keep-account")]
        )

        try await store.deleteConversation(accountId: 1, friendId: 2)

        let deleted = try await store.fetchLatest(accountId: 1, friendId: 2, limit: 20)
        let keptFriend = try await store.fetchLatest(accountId: 1, friendId: 3, limit: 20)
        let keptAccount = try await store.fetchLatest(accountId: 9, friendId: 2, limit: 20)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertEqual(keptFriend.compactMap(\.messageId), [11])
        XCTAssertEqual(keptAccount.compactMap(\.messageId), [12])
    }

    func testDeletingConversationAlsoRemovesSoftDeletedRows() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ChatHistoryStore(container: persistence.container)
        try await store.upsert(
            accountId: 1,
            friendId: 2,
            items: [try historyItem(id: 10, content: "soft-deleted", deleted: true)]
        )

        try await store.deleteConversation(accountId: 1, friendId: 2)

        let context = persistence.container.viewContext
        let remaining = try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageEntity")
            request.predicate = NSPredicate(format: "accountId == 1 AND friendId == 2")
            return try context.count(for: request)
        }
        XCTAssertEqual(remaining, 0)
    }

    func testHistoryStateKeepsIndependentOlderAvailabilityPerFriend() {
        var states: [Int64: ChatHistoryCursorState] = [:]
        states[2] = ChatHistoryCursorState(
            oldestMessageId: 10,
            latestMessageId: 20,
            hasOlder: false,
            isHydrated: true
        )
        states[3] = ChatHistoryCursorState(
            oldestMessageId: 30,
            latestMessageId: 40,
            hasOlder: true,
            isHydrated: true
        )

        XCTAssertFalse(states[2]!.hasOlder)
        XCTAssertTrue(states[3]!.hasOlder)
        XCTAssertEqual(states[2]!.latestMessageId, 20)
        XCTAssertEqual(states[3]!.oldestMessageId, 30)
    }

    func testAccountSwitchClearsInMemoryChatProjection() {
        let manager = SocketManager()
        manager.currentUserId = 1
        manager.chatHistory[7] = [historyMessage(id: 10)]
        manager.chatHistoryStates[7] = ChatHistoryCursorState(
            oldestMessageId: 10,
            latestMessageId: 10,
            hasOlder: false,
            isHydrated: true
        )

        manager.currentUserId = 2

        XCTAssertTrue(manager.chatHistory.isEmpty)
        XCTAssertTrue(manager.chatHistoryStates.isEmpty)
    }

    func testAsyncHistoryPublishingRejectsStaleAccount() throws {
        let socketSource = try sourceFileContents("chat-storage/SocketManager.swift")
        let pushHandler = try sourceSlice(
            socketSource,
            from: "self.registerStreamHandler(for: [.chatPushReq])",
            to: "// 注册 0x52 消息回执监听"
        )
        XCTAssertTrue(pushHandler.contains("guard self.currentUserId == currentUserId else { return }"))

        let chatSource = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let clearMethod = try sourceSlice(
            chatSource,
            from: "private func clearLocalHistory() async",
            to: "private func loadInitialHistory() async"
        )
        let initialMethod = try sourceSlice(
            chatSource,
            from: "private func loadInitialHistory() async",
            to: "private func loadMoreHistory() async"
        )
        let mergeMethod = try sourceSlice(
            chatSource,
            from: "private func mergeHistoryMessages(",
            to: "private func historyMessages("
        )

        XCTAssertTrue(clearMethod.contains("guard socketManager.currentUserId == accountId else { return }"))
        XCTAssertTrue(initialMethod.contains("guard socketManager.currentUserId == accountId else { return }"))
        XCTAssertTrue(mergeMethod.contains("guard socketManager.currentUserId == accountId else { return nil }"))
    }

    func testRealtimeAndActionDtosDecodeLongMessageIds() throws {
        let push = try JSONDecoder().decode(ChatPushDto.self, from: """
        {
          "messageId": 5000000000,
          "senderId": 7,
          "content": "push",
          "msgType": "TEXT",
          "gmtCreated": 1721640000000
        }
        """.data(using: .utf8)!)
        let receipt = try JSONDecoder().decode(ChatReceiptDto.self, from: """
        {"messageId": 5000000000, "status": "SUCCESS"}
        """.data(using: .utf8)!)
        let action = try JSONDecoder().decode(ChatMessageActionPushDto.self, from: """
        {"action": "retract", "messageId": 5000000000, "friendId": 7}
        """.data(using: .utf8)!)

        XCTAssertEqual(push.messageId, 5_000_000_000)
        XCTAssertEqual(receipt.messageId, 5_000_000_000)
        XCTAssertEqual(action.messageId, 5_000_000_000)
    }

    func testInitialHistorySourceDoesNotClearExistingConversation() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let method = try sourceSlice(
            source,
            from: "private func loadInitialHistory() async",
            to: "private func loadMoreHistory() async"
        )

        XCTAssertFalse(method.contains("history[friend.id] = []"))
        XCTAssertTrue(method.contains("ChatHistoryStore.shared.fetchLatest"))
        XCTAssertTrue(method.contains("afterMessageId"))
    }

    func testHistoryPageMergeRunsOutsideMainActor() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let method = try sourceSlice(
            source,
            from: "private func persistAndMerge(",
            to: "private func historyMessages("
        )

        XCTAssertTrue(method.contains("let merged = await Task.detached"))
        XCTAssertTrue(method.contains("ChatHistoryWindowPolicy.merge"))
        XCTAssertTrue(method.contains("SocketManager.chatHistoryWindowLimit"))
        XCTAssertTrue(method.contains("nonisolated private static func makeHistoryMessages"))
    }

    func testHistoryProjectionDeclaresBoundedWindowAndIndependentLatestMessage() throws {
        let source = try sourceFileContents("chat-storage/SocketManager.swift")

        XCTAssertTrue(source.contains("static let chatHistoryWindowLimit = 160"))
        XCTAssertTrue(source.contains("@Published var latestChatMessages: [Int64: ChatMessage] = [:]"))
    }

    func testIncrementalHistoryPersistsPagesBeforeSingleWindowPublication() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let method = try sourceSlice(
            source,
            from: "private func synchronizeIncrementalHistory(",
            to: "private func loadMoreHistory() async"
        )

        let persistRange = try XCTUnwrap(method.range(of: "ChatHistoryStore.shared.upsert"))
        let publishRange = try XCTUnwrap(method.range(of: "await mergeHistoryMessages("))
        XCTAssertLessThan(persistRange.lowerBound, publishRange.lowerBound)
        XCTAssertEqual(method.components(separatedBy: "await mergeHistoryMessages(").count - 1, 1)
        XCTAssertTrue(method.contains("Task.detached"))
    }

    func testHistoryLoadTriggerCoalescesDelayedRequests() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let detail = try sourceSlice(
            source,
            from: "private struct ChatDetailView: View {",
            to: "// 3. Friend Sidebar View"
        )

        XCTAssertTrue(detail.contains("@State private var historyLoadTask: Task<Void, Never>?"))
        XCTAssertTrue(detail.contains("scheduleLoadMoreHistory()"))
        XCTAssertTrue(detail.contains("historyLoadTask?.cancel()"))
    }

    func testHistoryLoadUsesLocalOlderPageBeforeNetworkFallback() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let method = try sourceSlice(
            source,
            from: "private func loadMoreHistory() async",
            to: "private func scheduleLoadMoreHistory()"
        )

        XCTAssertTrue(method.contains("ChatHistoryStore.shared.fetchOlder"))
        XCTAssertTrue(method.contains("mergeLocalHistory"))

        let localFetch = try XCTUnwrap(method.range(of: "ChatHistoryStore.shared.fetchOlder"))
        let networkFetch = try XCTUnwrap(method.range(of: "socketManager.getChatHistory"))
        XCTAssertLessThan(localFetch.lowerBound, networkFetch.lowerBound)
    }

    func testHistoryWindowSupportsLocalNewerPagingAndRevisionBasedScrollRestore() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let detail = try sourceSlice(
            source,
            from: "private struct ChatDetailView: View {",
            to: "// 3. Friend Sidebar View"
        )
        let newerMethod = try sourceSlice(
            source,
            from: "private func loadNewerHistory() async",
            to: "private func scheduleLoadMoreHistory()"
        )

        XCTAssertTrue(detail.contains(".onChange(of: historyWindowRevision)"))
        XCTAssertFalse(detail.contains(".onChange(of: messages.count)"))
        XCTAssertTrue(detail.contains("scheduleLoadNewerHistory()"))
        XCTAssertTrue(newerMethod.contains("ChatHistoryStore.shared.fetchNewer"))
        XCTAssertTrue(newerMethod.contains("direction: .newer"))
    }

    func testFriendSummaryUsesLatestMessageProjectionInsteadOfWindowTail() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let friendRow = try sourceSlice(
            source,
            from: "private struct FriendRow: View {",
            to: "// 4. Friend Chat Split View"
        )

        XCTAssertTrue(friendRow.contains("socketManager.latestChatMessages[friend.id]"))
        XCTAssertFalse(friendRow.contains("socketManager.chatHistory[friend.id]?.last"))
    }

    func testChatHistoryUsesFlatTimelineEntriesForLazyRendering() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let detail = try sourceSlice(
            source,
            from: "private struct ChatDetailView: View {",
            to: "// 3. Friend Sidebar View"
        )

        XCTAssertTrue(detail.contains("private enum ChatTimelineEntry"))
        XCTAssertTrue(detail.contains("ForEach(timelineEntries)"))
        XCTAssertFalse(detail.contains("ForEach(groupedMessages"))
    }

    func testHistoryRawPayloadLoggingIsRemoved() throws {
        let source = try sourceFileContents("chat-storage/SocketManager.swift")
        XCTAssertFalse(source.contains("[getChatHistory] Raw JSON"))
    }

    func testConversationClearDoesNotUseSocketLifecycle() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let method = try sourceSlice(
            source,
            from: "private func clearLocalHistory() async",
            to: "private func loadInitialHistory() async"
        )

        XCTAssertTrue(method.contains("deleteConversation"))
        XCTAssertFalse(method.contains("CacheCleanupService"))
        XCTAssertFalse(method.contains("disconnect"))
        XCTAssertFalse(method.contains("receiveBuffer"))
        XCTAssertFalse(method.contains("clearHandlers"))
    }

    func testServerConnectionTestUsesIndependentProbe() throws {
        let source = try sourceFileContents("chat-storage/ConfigServerView.swift")
        let testHandler = try XCTUnwrap(
            source.range(
                of: "private func handleTestConnection()",
                range: source.startIndex..<source.endIndex
            )
        )
        let confirmHandler = try XCTUnwrap(
            source.range(
                of: "private func handleConfirm()",
                range: testHandler.upperBound..<source.endIndex
            )
        )
        let handlerSource = String(source[testHandler.lowerBound..<confirmHandler.lowerBound])

        XCTAssertTrue(handlerSource.contains("ServerConnectionProbe.test"))
        XCTAssertFalse(handlerSource.contains("socketManager.disconnect("))
        XCTAssertFalse(handlerSource.contains("socketManager.switchConnection("))
    }

    func testDirectoryParserRequiresExplicitSuccessBeforeEmptyData() throws {
        let source = try sourceFileContents("chat-storage/Services/DirectoryService.swift")

        XCTAssertTrue(source.contains("guard hasExplicitSuccess else"))
        XCTAssertTrue(source.contains("errorCode"))
        XCTAssertFalse(source.contains("响应中没有 data 字段，视为操作成功但无返回数据"))
    }

    func testDirectoryParserRejectsNotLoggedInResponseInsteadOfReturningEmptyData() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "errorCode": "NOT_LOGGED_IN",
            "message": "请先登录"
        ])
        let frame = Frame(type: .dirResponse, data: data)

        XCTAssertThrowsError(try DirectoryService.debugParseDirectoryResponse(frame)) { error in
            guard case DirectoryError.serverError(let code, let message) = error else {
                return XCTFail("Expected DirectoryError.serverError, got \(error)")
            }
            XCTAssertEqual(code, 401)
            XCTAssertEqual(message, "请先登录")
        }
    }

    func testCurrentUserAvatarFallbackUsesAtMostTwoCharacters() throws {
        XCTAssertEqual(CurrentUserAvatarDisplay.initials(for: "18806504525"), "18")
        XCTAssertEqual(CurrentUserAvatarDisplay.initials(for: "张三丰"), "张三")
        XCTAssertEqual(CurrentUserAvatarDisplay.initials(for: "  "), "用")
    }

    func testStoredSelfMessagesFallBackToCurrentUserAvatar() throws {
        let rowSource = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")
        let mainSource = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(rowSource.contains("let currentUserAvatarBase64: String?"))
        XCTAssertTrue(rowSource.contains("base64String: message.avatar ?? currentUserAvatarBase64"))
        XCTAssertTrue(mainSource.contains("ChatDetailView(friend: friend, currentUserAvatarBase64: currentUserAvatar)"))
        XCTAssertTrue(mainSource.contains("currentUserAvatarBase64: currentUserAvatarBase64"))
    }

    func testFriendDtoDecodesUnreadCountFromFlexibleServerFields() throws {
        let json = """
        {
          "id": 1,
          "userId": 7,
          "friendId": 5,
          "alias": "好友",
          "userName": "15868139672",
          "nickName": "好友昵称",
          "unread_count": "6",
          "latestUnreadMsg": "未读消息"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(FriendDto.self, from: json)

        XCTAssertEqual(dto.unreadCount, 6)
        XCTAssertEqual(dto.latestUnreadMsg, "未读消息")
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

    func testTransferCenterDoesNotRenderTaskSearchField() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertFalse(source.contains("TextField(\"搜索任务\""))
        XCTAssertFalse(source.contains("transferSearchField"))
        XCTAssertFalse(source.contains("transferSearchText"))
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

    func testChatImageBubbleSourcePrefersThumbnailThenPreviewAndNeverOriginal() throws {
        let fullyDerived = ChatImageAttachment(
            fileId: 90007,
            fileName: "source.png",
            fileSize: 8_000_000,
            mimeType: "image/png",
            thumbnailFileId: 91007,
            thumbnailFileSize: 70_000,
            previewFileId: 92007,
            previewFileSize: 900_000
        )
        let previewOnly = ChatImageAttachment(
            fileId: 90008,
            fileName: "preview-only.png",
            fileSize: 8_000_000,
            mimeType: "image/png",
            previewFileId: 92008,
            previewFileSize: 900_000
        )
        let originalOnly = ChatImageAttachment(
            fileId: 90009,
            fileName: "original-only.png",
            fileSize: 8_000_000,
            mimeType: "image/png"
        )

        XCTAssertEqual(fullyDerived.bubbleThumbnailDirectoryItem()?.id, 91007)
        XCTAssertEqual(previewOnly.bubbleThumbnailDirectoryItem()?.id, 92008)
        XCTAssertNil(originalOnly.bubbleThumbnailDirectoryItem())
    }

    func testChatImageDerivedPreviewKeepsModernImageFormatsLoadable() throws {
        let attachment = ChatImageAttachment(
            fileId: 90004,
            fileName: "large.heic",
            fileSize: 20_000_000,
            mimeType: "image/heic",
            thumbnailFileId: 91004,
            thumbnailFileSize: 80_000,
            previewFileId: 92004,
            previewFileSize: 1_200_000
        )

        XCTAssertTrue(attachment.thumbnailDirectoryItem().isImageFile)
        XCTAssertTrue(attachment.previewDirectoryItem().isImageFile)
    }

    func testChatImagePreviewCandidatesPreferOriginalAndFallbackToDerivedPreview() throws {
        let attachment = ChatImageAttachment(
            fileId: 90005,
            fileName: "large.webp",
            fileSize: 20_000_000,
            mimeType: "image/webp",
            thumbnailFileId: 91005,
            thumbnailFileSize: 80_000,
            previewFileId: 92005,
            previewFileSize: 1_200_000
        )

        let candidates = attachment.previewCandidateDirectoryItems()

        XCTAssertEqual(candidates.map(\.id), [90005, 92005])
        XCTAssertEqual(candidates.map(\.fileSize), [20_000_000, 1_200_000])
        XCTAssertTrue(candidates.allSatisfy(\.isImageFile))
    }

    func testTallChatImagePreviewPrefersOriginalBeforeDerivedPreview() throws {
        let attachment = ChatImageAttachment(
            fileId: 90006,
            fileName: "long-receipt.jpg",
            fileSize: 3_148_898,
            mimeType: "image/jpeg",
            width: 1216,
            height: 21_256,
            thumbnailFileId: 91006,
            thumbnailFileSize: 19_270,
            previewFileId: 92006,
            previewFileSize: 212_489
        )

        let candidates = attachment.previewCandidateDirectoryItems()
        let bubbleSize = attachment.bubblePreviewSize()

        XCTAssertEqual(candidates.map(\.id), [90006, 92006])
        XCTAssertEqual(bubbleSize.width, 320)
        XCTAssertEqual(bubbleSize.height, 360)
    }

    func testChatImagePreviewOverlayUsesAttachmentFallbackLoader() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")

        XCTAssertTrue(source.contains("previewImage(for: selectedAttachment"))
        XCTAssertFalse(source.contains("previewImage(\n            for: selectedAttachment.previewDirectoryItem()"))
    }

    func testChatSingleImageBubbleUsesThumbnailAndDynamicSize() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")
        let bubbleSource = try sourceSlice(
            source,
            from: "private struct ChatImageGridView: View {",
            to: "struct ChatImagePreviewOverlay: View {"
        )

        XCTAssertTrue(bubbleSource.contains("attachment.bubblePreviewSize()"))
        XCTAssertTrue(bubbleSource.contains("attachment.bubbleThumbnailDirectoryItem()"))
        XCTAssertTrue(bubbleSource.contains("thumbnail(for: bubbleSource)"))
        XCTAssertTrue(bubbleSource.contains("暂无缩略图"))
        XCTAssertFalse(bubbleSource.contains("attachment.thumbnailDirectoryItem()"))
        XCTAssertFalse(bubbleSource.contains("thumbnail(for: attachment.directoryItem())"))
        XCTAssertFalse(bubbleSource.contains("preferReadablePreview"))
        XCTAssertFalse(bubbleSource.contains("previewImage(for: attachment"))
    }

    func testFileThumbnailServiceDecodesCachedBytesThroughImageIOOffMainActor() throws {
        let source = try sourceFileContents("chat-storage/Services/FileThumbnailService.swift")
        let thumbnailSource = try sourceSlice(
            source,
            from: "func thumbnail(for item: DirectoryItem)",
            to: "func previewImage(for item: DirectoryItem"
        )

        XCTAssertTrue(source.contains("actor FileThumbnailService"))
        XCTAssertTrue(source.contains("kCGImageSourceShouldCacheImmediately"))
        XCTAssertTrue(thumbnailSource.contains("Data(contentsOf: path)"))
        XCTAssertTrue(thumbnailSource.contains("Self.decodeImageData"))
        XCTAssertFalse(thumbnailSource.contains("NSImage(contentsOf: path)"))
    }

    func testChatImagePreviewOverlaySupportsScrollableZoomableLongImages() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")

        XCTAssertTrue(source.contains("ZoomablePreviewImageView"))
        XCTAssertTrue(source.contains("ScrollView([.horizontal, .vertical])"))
        XCTAssertTrue(source.contains("initialZoomScale"))
    }

    func testChatImagePreviewDoesNotDownsampleOriginalRasterAndInvalidatesOldCache() throws {
        let source = try sourceFileContents("chat-storage/Services/FileThumbnailService.swift")

        XCTAssertFalse(source.contains("let scaledImage = scaled(image, maxDimension: 2048)"))
        XCTAssertTrue(source.contains("image-previews-v2"))
        XCTAssertTrue(source.contains("return image"))
    }

    func testChatImagePreviewAlwaysPrefersOriginalForReadableQuality() throws {
        let source = try sourceFileContents("chat-storage/Services/Chat/ChatAttachmentModels.swift")

        XCTAssertTrue(source.contains("return [original, preferred]"))
    }

    func testChatImageUploadSkipsLowResolutionDerivedPreviewForVeryTallImages() throws {
        let source = try sourceFileContents("chat-storage/Services/Chat/ChatAttachmentUploadService.swift")

        XCTAssertTrue(source.contains("shouldGenerateDerivedPreview"))
        XCTAssertTrue(source.contains("image.size.height / width < 3"))
    }

    func testDirectoryItemImageDetectionReusesChatImageFormatSupport() throws {
        let source = try sourceFileContents("chat-storage/Models/do/FileDto.swift")

        XCTAssertTrue(source.contains("ChatImageFormat.isSupported(fileName: fileName)"))
    }

    func testDirectoryItemPlayableVideoFallsBackToServerFileType() throws {
        let dto = FileDto(
            id: 9,
            pId: 3,
            fileName: "重命名后没有扩展名",
            filePath: "/Users/demo/storages/account/video/task_9_demo.mp4",
            fileSize: 2048,
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

        let item = dto.toDirectoryItem()

        XCTAssertTrue(item.isVideoFile)
        XCTAssertTrue(item.isPlayableVideoFile)
        XCTAssertEqual(item.iconName, "film")
    }

    func testFileRenamePolicyPreservesOriginalExtensionWhenEditedNameOmitsIt() throws {
        XCTAssertEqual(
            FileNameRules.editableStem(for: "哈地方都舒服.mp4"),
            "哈地方都舒服"
        )
        XCTAssertEqual(
            FileNameRules.applyingPreservedExtension(
                to: "又是一款性感肉丝美腿",
                originalFileName: "哈地方都舒服.mp4"
            ),
            "又是一款性感肉丝美腿.mp4"
        )
        XCTAssertEqual(
            FileNameRules.applyingPreservedExtension(
                to: "又是一款性感肉丝美腿.mov",
                originalFileName: "哈地方都舒服.mp4"
            ),
            "又是一款性感肉丝美腿.mov"
        )
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

    func testChatInputBarUsesUnifiedSendForTextAndMixedAttachments() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatInputBar.swift")

        XCTAssertTrue(source.contains("@Binding var pendingAttachments: [PendingChatAttachment]"))
        XCTAssertTrue(source.contains("let onPickAttachments: () -> Void"))
        XCTAssertTrue(source.contains("let onRemovePendingAttachment: (UUID) -> Void"))
        XCTAssertTrue(source.contains("PendingChatAttachmentCard"))
        XCTAssertTrue(source.contains("Button(action: onSendMessage)"))
        XCTAssertFalse(source.contains("let onSendImage: () -> Void"))
        XCTAssertFalse(source.contains("pendingImages"))
    }

    func testChatInputBarUsesFloatingToggleableEmojiPanelAndRemovesUnusedTools() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatInputBar.swift")

        XCTAssertTrue(source.contains(".overlay(alignment: .topLeading)"))
        XCTAssertTrue(source.contains("showEmojiPicker.toggle()"))
        XCTAssertFalse(source.contains("systemName: \"scissors\""))
        XCTAssertFalse(source.contains("systemName: \"mic\""))
        XCTAssertFalse(source.contains("systemName: \"hand.tap\""))
        XCTAssertFalse(source.contains("systemName: \"phone\""))
        XCTAssertFalse(source.contains("systemName: \"video\""))
    }

    func testChatTextViewReadsScreenshotPasteboardFormatsBeforeTextPaste() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/MacResponsiveTextView.swift")

        XCTAssertTrue(source.contains("NSPasteboard.PasteboardType.png"))
        XCTAssertTrue(source.contains("NSPasteboard.PasteboardType.tiff"))
        XCTAssertTrue(source.contains("NSImage(pasteboard:"))
        XCTAssertTrue(source.contains("super.paste(sender)"))
    }

    func testLocalChatMessageDerivesServerCompatibleTimeGrouping() throws {
        let date = Date(timeIntervalSince1970: 1_721_640_000)
        let message = ChatMessage(
            messageId: nil,
            clientMsgId: "local-time",
            content: "hello",
            isMe: true,
            timestamp: date,
            type: "TEXT",
            sendStatus: .sending
        )

        XCTAssertEqual(message.groupTime, ChatMessageTimeGrouping.groupTime(for: date))
        XCTAssertEqual(message.msgTimeStr, ChatMessageTimeGrouping.messageTime(for: date))
    }

    func testChatTimelineDoesNotUseUnknownTimeForValidMessageTimestamp() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(source.contains("ChatMessageTimeGrouping.groupTime(for: message.timestamp)"))
        XCTAssertFalse(source.contains("message.groupTime ?? \"未知时间\""))
    }

    func testChatTextViewRecognizesClipboardStringFilePathAsImage() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/MacResponsiveTextView.swift")

        XCTAssertTrue(source.contains("string(forType: .fileURL)"))
        XCTAssertTrue(source.contains("URL(fileURLWithPath:"))
        XCTAssertTrue(source.contains("ChatImageFormat.isSupported(fileName:"))
    }

    func testChatInputHidesPlaceholderWhileInputMethodHasMarkedText() throws {
        let textViewSource = try sourceFileContents("chat-storage/Views/Chat/MacResponsiveTextView.swift")

        XCTAssertTrue(ChatInputPlaceholderPolicy.shouldShow(
            messageText: "",
            isComposing: false,
            hasAttachments: false,
            hasQuote: false
        ))
        XCTAssertFalse(ChatInputPlaceholderPolicy.shouldShow(
            messageText: "",
            isComposing: true,
            hasAttachments: false,
            hasQuote: false
        ))
        XCTAssertTrue(textViewSource.contains("onMarkedTextChanged"))
        XCTAssertTrue(textViewSource.contains("setMarkedText"))
        XCTAssertTrue(textViewSource.contains("if !textView.hasMarkedText(), textView.string != text"))
    }

    func testChatMixedImageSendUsesOptimisticBubbleBeforeUpload() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let socketSource = try sourceFileContents("chat-storage/SocketManager.swift")

        XCTAssertTrue(source.contains("appendLocalChatMessage"))
        XCTAssertTrue(source.contains("updateLocalChatMessage"))
        XCTAssertTrue(source.contains("appendLocalMessage: false"))
        XCTAssertTrue(source.contains("attachmentTransferStore.createBatch("))
        XCTAssertTrue(source.contains("sendStatus: .uploadingMedia"))
        XCTAssertTrue(source.contains("attachmentTransferCoordinator.enqueue("))
        XCTAssertFalse(source.contains("isUploadingAttachment"))
        XCTAssertTrue(socketSource.contains("appendLocalMessage: Bool = true"))
    }

    func testChatAttachmentPickerSupportsMultipleArbitraryFilesAndRetryKeepsFullList() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(source.contains("panel.allowsMultipleSelection = true"))
        XCTAssertTrue(source.contains("panel.canChooseFiles = true"))
        XCTAssertTrue(source.contains("PendingChatAttachment.file(url: url)"))
        XCTAssertTrue(source.contains("attachmentTransferStore.createBatch("))
        XCTAssertTrue(source.contains("attachments: attachmentsToSend"))
        XCTAssertTrue(source.contains("attachmentsToSend: attachmentTransferStore.pendingAttachments(clientMsgId: clientMsgId)"))
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
        XCTAssertTrue(source.contains("ChatFileAttachmentCard"))
        XCTAssertTrue(source.contains("onDownloadAttachment"))
        XCTAssertTrue(detailSource.contains("downloadChatAttachment"))
        XCTAssertTrue(detailSource.contains("onDownloadAttachment: downloadChatAttachment"))
        XCTAssertFalse(source.contains("message.type == \"IMAGE\" ? \"[图片]\" : message.content"))
        XCTAssertFalse(source.contains("@State private var previewContext: ChatImagePreviewContext?"))
        XCTAssertFalse(source.contains(".sheet(item: $previewContext)"))
        XCTAssertTrue(source.contains("onPreviewImage"))
        XCTAssertTrue(source.contains(".onTapGesture(count: 1)"))
        XCTAssertTrue(source.contains("previewImage(for: selectedAttachment"))
        XCTAssertFalse(source.contains("selectedAttachment.previewDirectoryItem()"))
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

    func testSocketManagerDrainsLargeFrameInSingleInputEvent() throws {
        let payload = Data(repeating: 0x41, count: 32 * 1024)
        let frameBytes = Frame(type: .userResponse, data: payload).toBytes()
        let inputStream = InputStream(data: frameBytes)
        let socketManager = SocketManager()

        inputStream.open()
        defer { inputStream.close() }
        socketManager.inputStream = inputStream
        socketManager.isReceiving = true

        socketManager.receiveAndProcessFrames()

        XCTAssertTrue(socketManager.receiveBuffer.isEmpty)
        XCTAssertFalse(inputStream.hasBytesAvailable)
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

    func testUploadFinalAckRequiresMatchingTaskAndPositiveFileId() throws {
        let valid = StandardAckResponse(
            status: "success",
            taskId: "task-123",
            message: nil,
            fileId: 7478051867767984128,
            uploadedSize: nil,
            serverState: nil,
            recommendedChunkSize: nil,
            recommendedAckWindow: nil,
            serverWriteMillis: nil,
            retryAfterMs: nil
        )

        XCTAssertEqual(
            try FileTransferService.debugValidateFinalUploadAck(valid, expectedTaskId: "task-123"),
            7478051867767984128
        )

        let wrongTask = StandardAckResponse(
            status: "success",
            taskId: "task-456",
            message: nil,
            fileId: 7478051867767984128,
            uploadedSize: nil,
            serverState: nil,
            recommendedChunkSize: nil,
            recommendedAckWindow: nil,
            serverWriteMillis: nil,
            retryAfterMs: nil
        )
        XCTAssertThrowsError(
            try FileTransferService.debugValidateFinalUploadAck(wrongTask, expectedTaskId: "task-123")
        )

        let missingFile = StandardAckResponse(
            status: "success",
            taskId: "task-123",
            message: nil,
            fileId: nil,
            uploadedSize: nil,
            serverState: nil,
            recommendedChunkSize: nil,
            recommendedAckWindow: nil,
            serverWriteMillis: nil,
            retryAfterMs: nil
        )
        XCTAssertThrowsError(
            try FileTransferService.debugValidateFinalUploadAck(missingFile, expectedTaskId: "task-123")
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

    func testChatMixedMessageContentRoundTripsImagesAndFiles() throws {
        let attachments = [
            ChatAttachment(
                kind: "image",
                fileId: 81001,
                fileName: "photo.png",
                fileSize: 1024,
                mimeType: "image/png",
                width: 100,
                height: 80
            ),
            ChatAttachment(
                kind: "file",
                fileId: 81002,
                fileName: "资料.pdf",
                fileSize: 2048,
                mimeType: "application/pdf"
            )
        ]

        let payload = try ChatMixedMessageContent(text: "请查收", attachments: attachments)
        let parsed = try XCTUnwrap(ChatMixedMessageContent.parse(payload.contentString()))

        XCTAssertEqual(parsed.attachments, attachments)
        XCTAssertEqual(parsed.attachments.filter(\.isImage).count, 1)
        XCTAssertEqual(parsed.attachments.filter { !$0.isImage }.count, 1)
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

    func testChatMessagePreparedPayloadUpdatesWithControlledContentReplacement() throws {
        var message = historyMessage(id: 1, content: "before")
        let attachment = ChatImageAttachment(
            fileId: 101,
            fileName: "after.png",
            fileSize: 2048,
            mimeType: "image/png"
        )
        let mixed = try ChatMixedMessageContent(text: "after", attachments: [attachment])
        let content = try mixed.contentString()

        message.updateContent(
            content,
            type: "MIXED",
            preparedPayload: .mixed(mixed)
        )

        XCTAssertEqual(message.content, content)
        XCTAssertEqual(message.type, "MIXED")
        XCTAssertEqual(message.preparedPayload, .mixed(mixed))
        XCTAssertEqual(message.displayText, "[图片] after")
    }

    func testChatMessageRowUsesPreparedPayloadWithoutTextSelectionOrParsing() throws {
        let source = try sourceFileContents("chat-storage/Views/Chat/ChatMessageRow.swift")

        XCTAssertTrue(source.contains("let payload = message.preparedPayload"))
        XCTAssertFalse(source.contains("ChatMessagePayload.parse"))
        XCTAssertFalse(source.contains(".textSelection(.enabled)"))

        let socketSource = try sourceFileContents("chat-storage/SocketManager.swift")
        let updateMethod = try sourceSlice(
            socketSource,
            from: "func updateLocalChatMessage(",
            to: "func sendChatMessage("
        )
        XCTAssertTrue(updateMethod.contains("preparedPayload: ChatMessagePayload?"))
        XCTAssertTrue(updateMethod.contains("history[index].updateContent("))
    }

    func testFriendRowsUsePreparedServerPreviewWithoutBodyParsing() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")
        let friendRowSource = try sourceSlice(
            source,
            from: "private struct FriendRow: View {",
            to: "// 4. Friend Chat Split View"
        )
        let recentRowSource = try sourceSlice(
            source,
            from: "private struct ChatWorkspaceRecentRow: View {",
            to: "private struct ChatWorkspaceAvatar: View {"
        )

        XCTAssertTrue(source.contains("makeServerLatestPreviews"))
        XCTAssertTrue(source.contains("Task.detached(priority: .utility)"))
        XCTAssertTrue(friendRowSource.contains("friend.serverLatestDisplayText"))
        XCTAssertTrue(recentRowSource.contains("friend.serverLatestDisplayText"))
        XCTAssertFalse(friendRowSource.contains("ChatMessagePayload.parse"))
        XCTAssertFalse(recentRowSource.contains("ChatMessagePayload.parse"))
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
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "wide.avif"), "image/avif")
        XCTAssertEqual(ChatImageFormat.mimeType(forFileName: "legacy.jfif"), "image/jpeg")
        XCTAssertTrue(ChatImageFormat.isSupported(fileName: "paste.png"))
        XCTAssertTrue(ChatImageFormat.isSupported(fileName: "poster.jp2"))
        XCTAssertFalse(ChatImageFormat.isSupported(fileName: "archive.zip"))
    }

    private func sourceFileContents(_ relativePath: String) throws -> String {
        try String(contentsOf: projectFileURL(relativePath), encoding: .utf8)
    }

    private func projectFileURL(_ relativePath: String) -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return projectRoot.appendingPathComponent(relativePath)
    }

    private func sourceSlice(_ source: String, from start: String, to end: String) throws -> String {
        let startRange = try XCTUnwrap(source.range(of: start))
        let endRange = try XCTUnwrap(source.range(of: end, range: startRange.upperBound..<source.endIndex))
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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

    private func historyMessage(
        id: Int64?,
        clientMsgId: String? = nil,
        content: String = "message",
        status: ChatMessage.SendStatus = .success
    ) -> ChatMessage {
        ChatMessage(
            messageId: id,
            clientMsgId: clientMsgId,
            content: content,
            isMe: false,
            timestamp: Date(),
            type: "TEXT",
            sendStatus: status
        )
    }

    private func historyItem(
        id: Int64,
        senderId: Int32 = 1,
        receiverId: Int32 = 2,
        content: String,
        clientMsgId: String? = nil,
        deleted: Bool = false
    ) throws -> ChatHistoryItemDto {
        var json: [String: Any] = [
            "id": id,
            "senderId": senderId,
            "receiverId": receiverId,
            "content": content,
            "msgType": "TEXT",
            "status": 1,
            "gmtCreated": 1_721_640_000_000 + id,
            "deleted": deleted
        ]
        if let clientMsgId {
            json["clientMsgId"] = clientMsgId
        }
        return try JSONDecoder().decode(
            ChatHistoryItemDto.self,
            from: JSONSerialization.data(withJSONObject: json)
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

    func testCloudUploadTargetRejectsMissingInvalidAndRootSelections() throws {
        let root = DirectoryItem(id: 100, pId: -1, fileName: "user", childFileList: nil)
        let child = DirectoryItem(id: 200, pId: 100, fileName: "docs", childFileList: nil)
        let rejectedSelections: [Int64?] = [nil, 0, -1, root.id]

        for selection in rejectedSelections {
            let resolved = selection == child.id ? child : (selection == root.id ? root : nil)
            let result = CloudUploadTargetValidator.validate(
                selectedDirectoryId: selection,
                rootDirectoryId: root.id,
                resolvedDirectory: resolved
            )

            guard case .failure(let error) = result else {
                return XCTFail("Expected upload target rejection for selection: \(String(describing: selection))")
            }
            XCTAssertEqual(error, .invalidTarget)
            XCTAssertEqual(error.errorDescription, "根目录不允许上传，请先选择一个子目录")
        }
    }

    func testCloudUploadTargetRejectsUnknownPositiveDirectory() throws {
        let result = CloudUploadTargetValidator.validate(
            selectedDirectoryId: 200,
            rootDirectoryId: 100,
            resolvedDirectory: nil
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected unknown directory rejection")
        }
        XCTAssertEqual(error, .invalidTarget)
    }

    func testCloudUploadTargetAllowsResolvedPositiveChildDirectory() throws {
        let child = DirectoryItem(id: 200, pId: 100, fileName: "docs", childFileList: nil)
        let result = CloudUploadTargetValidator.validate(
            selectedDirectoryId: child.id,
            rootDirectoryId: 100,
            resolvedDirectory: child
        )

        guard case .success(let target) = result else {
            return XCTFail("Expected child directory to be uploadable")
        }
        XCTAssertEqual(target.id, child.id)
    }

    func testCloudUploadEntryRequiresValidatedNonOptionalDirectory() throws {
        let source = try sourceFileContents("chat-storage/MainChatStorage.swift")

        XCTAssertTrue(source.contains("private func handleCloudUpload(targetDirectory: DirectoryItem? = nil)"))
        XCTAssertTrue(source.contains("CloudUploadTargetValidator.validate("))
        XCTAssertTrue(source.contains("handleCloudUpload(targetDirectory: item)"))
        XCTAssertTrue(source.contains("private func handleSelectFiles(targetDirectory: DirectoryItem)"))
        let directCalls = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("handleSelectFiles(targetDirectory:") }
        XCTAssertEqual(directCalls, ["handleSelectFiles(targetDirectory: targetDirectory)"])
        XCTAssertFalse(source.contains("targetDirectory?.id ?? 0"))
        XCTAssertFalse(source.contains("targetDirectory?.fileName ?? \"根目录\""))
    }

}
