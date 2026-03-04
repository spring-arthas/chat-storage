# 桌面端聊天体验优化设计方案 V3.0 (终极详细设计版)

这份文档针对 macOS 桌面端聊天的 5 个核心优化点，提供了**从业务场景到前后端数据结构协议、服务端兼容逻辑、最后到客户端组件具体实现代码**的保姆级深度设计。此文档可直接作为开发和前后端联调的参考手册。

由于您的要求，所有新增且非现存修改的 Socket 帧类型均从 **0x57** 开始步进分配。

---

## 1. 聊天气泡右键菜单 (Message Context Menu)

赋予普通的聊天消息高级交互能力，提升信息处理效率。

### 1.1 复制文本与图片 (Copy Text/Image)
- **客户端处理逻辑**：
  - 在 `ChatDetailView` 中的 `MessageRow` 视图上附加 `.contextMenu` 修饰符。
  - 对于文本消息 (`msgType == "TEXT"`)，直接从消息对象获取文本，向 `NSPasteboard.general` 写入 `content`。
  - 对于图片消息 (`msgType == "IMAGE"` 或 `FILE`)，客户端需要判断 `content` 是本地路径、Base64 还是下载后的 NSImage 数据缓存，然后利用 `NSPasteboard.general.writeObjects([nsImage])` 实现图片的静默复制。
- **服务端处理逻辑**：纯客户端本地操作系统 API 交互，无服务端改动。

### 1.2 单条消息删除与双向撤回 (Delete / Retract Message)
**【前后端协议定义】**
新增帧类型：**单条消息删除请求 (0x57)**
```json
// Request DTO (对应新类 ChatDeleteMessageReqDto)
{
  "messageId": 123456, // 要删除的消息主键ID
  "friendId": 7890,    // 对应的聊天对象ID
  "deleteType": 0      // 0:单向删除(仅我方不可见), 1:双向删除(全网撤回)
}
```
新增帧类型：**消息撤回/删除推送指令 (0x58)**
```json
// Push DTO (对应新类 ChatMessageDeletePushDto)
{
  "messageId": 123456,
  "friendId": 8888,    // 触发撤回操作的用户ID
  "notifyText": "发件人撤回了一条消息" // 辅助老客户端或系统消息的文案
}
```

**【客户端处理详细步骤】**
1. **交互层**：用户在某条消息上右键点击“删除”或“撤回”。
2. **乐观更新 UI**：不等待服务端确认，针对当前 `socketManager.chatHistory[friendId]` 数组执行 `removeAll(where: { $0.id == targetMessageId })`，或者将整条消息替换为一个“系统提示”的占位符模型。内存更新完毕后 UI 会自动刷新丢弃该气泡。
3. **网络流**：根据用户选择组装并发射 `0x57` 帧指令到 Socket 服务端。
4. **被下发方的协同**：如果我的朋友发出了撤回动作，我的客户端会在 `SocketManager` 处接收到来自服务端的 `0x58` 推送，此时执行如下内存清理：`self.chatHistory[pushDto.friendId]?.removeAll { $0.id == pushDto.messageId }`，如果当前正好在这个聊天页，气泡会无声无息消失。

**【服务端处理逻辑与历史功能兼容】**
1. 控制器接收并识别 `0x57` 命令，提取 `messageId`。需校验操纵者(Token owner)和消息的发送方关系、时间窗口（如撤回需距离发送不超过 2 分钟，仅删除自己记录则通常无时间限制）。
2. **处理 `deleteType = 0` (单向逻辑删除)**：
   - *逻辑更新*：坚决不在数据库级别物理删除原始记录 `mds_chat_record`，而是拓展一个新列 `deleted_by_uids` (类型 VARCHAR，存 JSON 数组格式的 userId) 或者建立一张关联表 `mds_chat_del_record` 记录 `msg_id` - `user_id` 的不可见关系。
   - *向后兼容策略*：当历史的老版本客户端发出 `0x53` (ChatHistoryReq) 获取聊天历史时，服务端的查询 SQL 必须带上过滤条件 `NOT IN deleted_by_uids` (或使用左连接关联表过滤)。旧版本客户端无需任何更新代码就能完美适配，它们将根本无法加载到这条消息；发出该帧的新版本客户端一样。
3. **处理 `deleteType = 1` (双向撤回)**：
   - *逻辑更新*：可以复用原本存盘数据结构的 `status` 字段。将数据库该主键记录的 `status` 变更为特定值（如 -1），表示撤回作废。
   - *向后兼容功能*：如果考虑让极老的强缓存版本客户端不致出错，除了将状态置 -1，还可以修改它的 `content` 内容强制刷成 "[该消息已被撤回]"，并将 `msgType` 变更为 `SYSTEM` 类型。这样老客户端刷历史时能渲染出文案。
   - *流转*：实时寻找目标 `friendId` 的 TCP session 在线连接管道，组装并向其下发新注册的 `0x58` 帧即可。

### 1.3 引用回复 (Quote Reply)
**【前后端协议变更 (扩展现存)】**
由于属于聊天的一部分，不需要创建全新的主类型指令，应当拓展当前基础发信指令 `0x50` 和推流指令 `0x51`, `0x54` 以保持整洁。
**变更现存帧请求体** (修改 `ChatSendRequestDto`, `ChatPushDto`, `ChatHistoryItemDto`)
```json
// 在原有结构体 JSON 最外层中追加额外的冗余打包字段
{
   ... // 其他正常字段 content, msgType 等
  "quoteMsgId": 123456,            // 新增可选：引用的原消息ID
  "quoteMsgContent": "明天开会",   // 新增可选：防止客户端做二级查询的预先冗余摘要
  "quoteMsgSenderName": "李华"     // 新增可选：防止查询用户字典的冗余名称
}
```

**【客户端处理详细步骤】**
1. **交互暂存**：用户右键引用的瞬间，把获取到的 `ChatHistoryItemDto` 对象缓存到一个全局 `@State var currentQuoteMsg: ChatHistoryItemDto? = nil`。
2. **组装UI面板设计**：由于是原生应用，输入区可以放在包裹底部的 VStack，当 `currentQuoteMsg != nil` 就在内部输入框的顶端插入一条浅灰色的引用内容面板块（限制 `lineLimit(1)`并带一个删除 X 按钮，按 X 则把 `currentQuoteMsg` 归 nil 关闭该区域）。
3. **发送组装**：用户敲击回车，检查如果 `currentQuote` 有值，则在发送给底层的 `socketManager.sendMessage(0x50...)` 调用中拼上对应的三个新加字段。发送完后清除状态 `currentQuoteMsg = nil`。
4. **渲染展示**：对于所有的发信列表和历史获取列表，渲染时先判断模型的这三个附加字段是否非空？如果非空，在此气泡顶部堆叠展示出极小字体的浅色块展示这部分字。

**【服务端处理逻辑与历史功能兼容】**
1. 服务端收到 `0x50` 发送聊天。解析过程中捕获这三个 `quote` 相关的附加字段。
2. **逻辑写入**：若此时表结构没有对应的新增单独列，而又不想产生大面积表更动，最佳解法是在表字段中定义一栏扩展 JSON 字段 (如 `ext_info` Text类型) 或将其序列化在 `content` 核心字段（通过某种带 Header 标记的前置协议如 `[QUOTE|id|name|content]正文主体`）中存储。如果为了规范能建表添列则建 `quote_id`, `quote_content` 等列。
3. **向后兼容性**：不论是在入库时如何组合，当使用网络向对方下发推流数据 (`0x51`) 和历史 (`0x54`) 时，直接透传这三个字段。旧的老客户端内部反序列化的 `Codable`/`Jackson` 类因为没有声明接受这些附加字段名，在反解 JSON 时只会取认得核心字段，完美跳过和兼容不可见；而新客户端则读取利用。

---

## 2. 好友列表右键操作及管理 (Friend List Extensibility)

增强侧边栏 `OptimizedFriendSidebarView` 列表联系人管理。

### 2.1 修改好友别名/备注 (Update Alias)
**【前后端协议定义】**
新增帧类型：**修改好友备注请求 (0x59)**
```json
// Request DTO (FriendUpdateAliasReqDto)
{
  "friendId": 7890,
  "alias": "开发对接群-小张" // 新设置的本地备注
}
```

**【客户端处理详细步骤】**
1. 为左侧的 `FriendRow` 附加 `.contextMenu` -> “修改备注”。
2. 点击事件触发 `sheet/alert` 输入框获取最新录入的 `String`。发包 `0x59` 到后端。
3. 发包之后即可直接针对本单例维护的心脏列表 `socketManager.friendList` 中的对象做元素值修改（`idx = .firstIndex...; array[idx].alias = newValue`），UI 将立刻双向绑定更新列表上的文字呈现，甚至会自动跑入您的排序策略中被重排。

**【服务端处理逻辑与历史功能兼容】**
1. 拦截解析指令，寻找 `mds_user_friend`（或者管理相互关系的关联表）中当前客户端与 `friendId` 的实体行，更新或覆盖其 `alias` 列。
2. **向后兼容性**：之前由于客户端请求老版本的 `0x35` 后端就是下发全集带 `alias` 数据的清单对象了；修改后，无论多古老的客户端触发了重新查询请求(`0x35`)时，后端只是按表如实吐出了新保存的数据。旧版本的旧界面立刻正常展示最新的被我改动过的名称。

### 2.2 双向移除 / 删除联系人 (Delete Friend)
**【前后端协议定义】**
新增帧类型：**解除好友关系请求 (0x5A)**
```json
// Request DTO (FriendDeleteReqDto)
{ "friendId": 7890 }
```
新增帧类型：**己方被删好友关系断裂广播 (0x5B)**
```json
// Push DTO (FriendDeletedNotifyPushDto)
{ "friendId": 1234 }  // 这是发出删人者的ID
```

**【客户端处理详细步骤】**
1. 界面弹窗红色醒目字要求确认是否需要删除好友并清理记录。
2. 发出 `0x5A` 指令。将此人从内存 `socketManager.friendList` 全生命周期内拔除。
3. 从 `socketManager.chatHistory` 该键对应的字典和对象彻底释放，若此时主右面板正好处于跟此人聊天的阶段，使用 `if` 或者重新定一个空的 fallback 页覆盖退出聊天态。
4. 被删除者的电脑接到 `0x5B` 指令推送，执行全套跟步骤 2,3 一模一样的拔除代码，让这个人立刻从界面凭空飞遁。

**【服务端处理逻辑与历史功能兼容】**
1. 收到 `0x5A` 指令，执行对应数据库关系破裂流转：如将彼此在关系映射表的关联行删除或标记 `status=deleted` 状态。
2. **主动性推送协调**：后端需要利用 `0x5A` 中指出的目标 `friendId` 用户，看其当下有没有跟某 Netty Node 存在存续 TCP Session，如果有，定向对他的渠道广播刚刚定义好的 `0x5B` 断裂协议（不用管他是否真的连线，因为只是一个状态更新，连线就推，不在线就跳过）。
3. 如果老客户端收到 `0x5B` 由于没有对应的 `handler`，可能会丢弃它——这并不可怕。只要关系破裂已持久化在数据库，老客户端刷新好友列表（`0x35`）就肯定看不见这人了。若是老客户端仍然向对方强行发老版的 `0x50` 通信帧，服务端必须先去校验好友表，然后阻截返回：不是好友或者发信失败指令。向后完美兼容！

---

## 3. 深蓝级强化：拖拽与剪贴板图传增强 (Drag & Paste Boost)

这并非协议添加，而是**重度的 MacOS AppKit 客户端原生渲染接口挂载整合**！这块最能拉升原生体验。
服务端保持原有的 `FileUploadClient` 和 `0x50(msgType=IMAGE/FILE)` 的原流程。

### 3.1 拦截系统剪贴板（ Cmd+V 图文透贴发图）
**【客户端核心底层代码整合设计】**
普通的 SwiftUI `TextEditor` 组件只提供系统默认的剪切板实现，不可能捕获出图片序列。我们建立封装隔离器（只在 OSX 环境下编译使用）：
```swift
// 创建一个 Representable
struct MacResponsiveTextView: NSViewRepresentable {
    @Binding var text: String
    var onPasteImage: (NSImage) -> Void   // 将捕获传出的图像数据钩子抛出

    func makeNSView(context: Context) -> CustomNSTextView {
        let view = CustomNSTextView()
        view.delegate = context.coordinator
        view.onPasteImage = onPasteImage
        return view
    }
    
    // ...更新方法 updateNSView ...
}

// 在其中复写具体的类：利用 AppKit 事件回溯控制
class CustomNSTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?

    override func paste(_ sender: Any?) {
        let pB = NSPasteboard.general
        // 探查有没有基于图片的二进制载体拷贝
        if let images = pB.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], 
           let firstImage = images.first {
            
            // 重要：中断系统的默认纯文本粘贴链，把活儿包下来
            self.onPasteImage?(firstImage)
            return
        }
        
        // 当判断是干干净净的文字或者啥都没有，抛给上家原生函数处理。天衣无缝。
        super.paste(sender)
    }
}
```
上层利用 `@State var showImagePreviewBoard: Bool` 控制并在捕获后进入你们早已写好的上传流逻辑代码即可。

### 3.2 接收 Finder 的拖拽文件 (Drag & Drop)
**【客户端处理详细步骤】**
在包裹大量信息或者外层页的修饰符直接串联 SwiftUI 特有的高阶拖拽接口：
```swift
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    for item in providers {
        if item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                guard let data = urlData as? Data,
                      let targetURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                DispatchQueue.main.async { 
                    prepareUploadSendFlow(with: targetURL) 
                }
            }
        }
    }
    return true
}
```

---

## 4. 键盘互动及输入区高度自适应扩展

体验升级的基础（与服务端无关，前端逻辑进阶）。

### 4.1 回车直发（Enter send) 与 (Shift/Option + Enter换行)
原生应用必须要实现 Enter 发送的畅快感！利用你在【3.1】编写过的 `CustomNSTextView` 类，配合 Coordinator 去实现代理：
```swift
class Coordinator: NSObject, NSTextViewDelegate {
    // 监听打字的输入插入命令钩子
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // 如果我们捕获到了用户插入新建行的那个专属系统调用
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // 获取键盘压按那刹那间有没有携带 Shift 或者 Option 键修饰符号
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                // 有修饰符：正常行为，给他放上一条回车符，中断方法接管
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            } else {
                // 完全没修饰符的生敲回车：调用外界我们绑定好的 send 逻辑
                self.parent.onSubmitMethodTiedFromUpperLevel()
                return true // 阻止框架自己去产生换行符行为
            }
        }
        return false // 不是这个指令我就不管
    }
}
```

### 4.2 文字胀破边界的高度自适应框
这在桌面开发被叫做 "Auto-growing TextView"。
依旧在你的内部对象代理中，重写内容变动的观察者回调：
1. 监听 `func textDidChange(_ notification: Notification)`
2. 根据内部 `NSTextContainer` 与字符画板系统算一下需要的实际物理包围盒宽高。
3. 如果这高度 > (设定你框子最原始的限制譬如 38px)，使用 SwiftUI 中的 `withAnimation` 向父级 `@Binding var height: CGFloat` 更新这个像素值。
4. 一旦超过（比如 250px 高再长大就影响视觉比例了），就锁死汇报，直接更改 NSTextview 的内部 `allowsDocumentBackgroundColorChange=false/isVerticallyResizable=true` 打开系统自带滚动条解决。

---

## 5. UI 美术优化及高阶消息状态体系

打造媲美头部产品的交互效果。

### 5.1 【纯前端绘制】气泡尾钩小箭头造型
放弃传统的圆角圆滑 `clipShape(RoundedRectangle(cornerRadius: 16))`。
我们要自己手画图形 `Shape` 构建聊天方向感气泡边界。
```swift
struct TailChatBubbleShape: Shape {
    var isMe: Bool  // 通过是否是我发的决定尾巴画哪边
    let cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // 此处利用 path.addArc 与 path.addLine(to:) 构建，
        // 核心思路：其他三个内角正常画出 12 像素曲边的内弧，
        // MyMsg 时将【右下角】画成不规则三角形；
        // OpponentMsg 将【左上角】或者【左下角】做延伸拖尾绘制。
        // 最后用做 `.clipShape(TailChatBubbleShape(isMe: ...))` 完美契合任意图片拉伸
        return path
    }
}
```

### 5.2 状态提示及定向单链消息“已读反馈”上推功能
**【前后端协议定义】**
不再是简单统推 `0x55` 来销账，要告知细致的数据流。
新增帧：**收看方已读精确汇报推送 (0x5C)**
```json
// Push DTO (ChatPreciseReadAckPushDto)
{
  "friendId": 7890,      // 是谁在看屏幕
  "messageIds": [123456, 123457], // 他切实体认真看过的并且刚入屏幕呈现的id列
}
```

**【客户端处理详细流转步骤】**
1. 发送方（A）界面在信息底部附上 `<Text(status == "Sent" ? "已送达" : "已读")>` 的极细副标题（如微信电脑版小绿字）。
2. 在接收方（B）的 `ChatDetailView` 中：针对每生成的一行信息元素，若为对方的信息挂戴 `.onAppear`。利用该回调拦截当前显示的 message 且把其 `messageId` 攒入一个每几秒放行打包一次 `[Int64]` 数组的后台池。
3. B 倒出这个池数据，发送特定的确认网络请求包给后端登记已读。
4. **回包推送与解析**：在线的 A 先生收到了服务器针对他之前发的这批文章推送回来的 `0x5C`；A 先生立刻使用大循环找内存列表里的数据 `idx = self.chatHistory.firstIndex...` 把内部 `status` 变轨为新的只读常驻状态(`status = "Read"`)。由于是使用 `ObservableObject` UI 会自动将发送信息小黑标变成大绿标。
**【服务端处理逻辑与历史功能兼容】**
1. 服务端拿到汇报清单，走常规的 DB 批量 `Update where IN (messageIds)` 更新库状态落盘。
2. 转手生成 `0x5C` 构建推送，如果有在线 Session 则立刻推向目标发信人管道。
3. **完美跨周期兼容性**：在旧版客户端，旧版发送者即使发了文章他也绝收不了 `0x5C` 动态推送包，这毫不影响他聊天。然而等他重新刷新客户端拉历史或切屏，服务端将最新的 status 送下去，还是展示了新的信息表现状态，老客户端一样能在刷数据中悄然得益！而旧的读信方只是失去了汇报新状态请求的小组件但并不会发生功能雪崩。这是最理想的接口过渡模式！
