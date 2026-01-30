# macOS App 开发指南 (SwiftUI vs WinForm)

对于习惯了 .NET WinForm 开发的程序员来说，转向 macOS SwiftUI 开发需要理解几个核心观念的转变。本指南将帮助您快速上手。

---

## 1. 核心思维转变

| 特性 | WinForm (.NET) | SwiftUI (macOS) |
| :--- | :--- | :--- |
| **构建方式** | **命令式 (Imperative)**<br>拖控件到画布，IDE 生成代码 `InitializeComponent()` | **声明式 (Declarative)**<br>用代码描述界面结构，IDE 实时预览渲染结果 |
| **界面更新** | **手动操作**<br>`label1.Text = count.ToString();` | **自动绑定 (Binding)**<br>修改变量 `@State count`，界面自动刷新 |
| **布局系统** | 绝对坐标 (x, y) 或 Anchor/Dock | 弹性布局 (VStack, HStack, ZStack) |
| **事件处理** | `button1_Click(object sender, EventArgs e)` | 闭包 `action: { ... }` |

---

## 2. 如何进行"拖拉拽"开发 (Library)

虽然 SwiftUI 提倡手写代码，但 Xcode 依然提供了类似 Toolbox 的控件库。

### 步骤
1. 打开 Xcode 右上角的 **+** 号图标（快捷键 `Shift + Command + L`）。
2. 在弹出的 **Library** 窗口中，您可以找到各种控件（Button, Label(Text), Image 等）。
3. **直接拖拽**：将控件拖到代码编辑器中的 `body` 代码块里，或者拖到右侧的 Canvas 预览界面上。
4. **属性面板**：选中代码中的控件，右侧的 **Inspectors** 面板（快捷键 `Option + Command + 0`）会显示该控件的属性，您可以像在 Visual Studio 属性窗口中一样修改字体、颜色、对齐方式。Xcode 会自动生成对应的修饰符代码（Modifiers）。

---

## 3. 代码与界面对应关系

在 `ContentView.swift` 中：

### 容器 (类比 Panel)
- **VStack**: 垂直排列（类似 FlowLayoutPanel set to TopDown）
- **HStack**: 水平排列（类似 FlowLayoutPanel set to LeftToRight）
- **ZStack**: 层叠排列（类似 WPF 的 Grid 或直接重叠）

### 状态管理 (变量)
WinForm 中我们定义类成员变量：
```csharp
private int count = 0;
```
SwiftUI 中我们需要标记它为 State：
```swift
@State private var count = 0
```
**区别**：当 Swift 中的 `@State` 变量被修改时，使用该变量的所有 UI 控件会**立即、自动**重绘。您不需要手动调用 `Invalidate()` 或 `label.Text = ...`。

### 事件处理 (Events)
WinForm:
```csharp
private void button1_Click(object sender, EventArgs e) {
    count++;
    label1.Text = count.ToString();
}
```

SwiftUI:
```swift
Button("点击") {
    // 这里的代码就是点击事件
    count += 1
    // 不需要手动更新 Label，因为 count 变了，Text("\(count)") 会自动变
}
```

---

## 4. 调试与预览

- **Live Preview (画布)**: Xcode 右侧（或下侧）的 Canvas 相当于 Visual Studio 的设计视图。
- 如果 Canvas 暂停了，点击顶部的 "Resume" 按钮。
- 您可以在 Canvas 中直接点击按钮测试交互（需要点击 Canvas 左下角的 ▶️ "Live Preview" 按钮）。

---

## 5. 常用的标准控件对照

| WinForm | SwiftUI | 说明 |
| :--- | :--- | :--- |
| `Label` | `Text("内容")` | 显示只读文本 |
| `Button` | `Button(action: {}) { ... }` | 按钮 |
| `TextBox` | `TextField("占位符", text: $text)` | 单行输入框 |
| `PictureBox` | `Image("图片名")` | 显示图片 |
| `CheckBox` | `Toggle("标签", isOn: $isOn)` | 开关/勾选框 |
| `TrackBar` | `Slider(value: $value)` | 滑动条 |
| `Timer` | `Timer.publish(...)` | 定时器 |

---

## 6. 为什么找不到 `.xib` 或 `.storyboard`？

在旧版 iOS/macOS 开发（UIKit/AppKit）中，确实有类似 WinForm `.Designer.cs` 的界面文件（Storyboard/XIB）。
但 **SwiftUI** 取消了这些文件，界面完全由代码定义。这样做的好处是：
1. git 冲突更少（不再全是 XML）。
2. 代码复用性极高。
3. 动态布局适应性更好（自动适配不同窗口大小、分辨率）。

如果您更喜欢先看界面，请多利用 Xcode 的 **Canvas 预览功能**。
