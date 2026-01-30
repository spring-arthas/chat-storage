//
//  ContentView.swift
//  chat-storage
//
//  Created by HLJY on 2026/1/29.
//

import SwiftUI
import CoreData

struct ContentView: View {
    // 类似于 WinForm 中的类成员变量，但在 SwiftUI 中我们需要用 @State 修饰
    // 当这个变量的值改变时，界面会自动刷新（UI 与数据绑定）
    @State private var counter: Int = 0
    @State private var message: String = "Hello, macOS!"

    var body: some View {
        // VStack = Vertical Stack (垂直布局容器)，类似于 WinForm 的 FlowLayoutPanel(TopDown) 或 StackPanel
        VStack(spacing: 20) {
            
            // 图片控件 (PictureBox)
            Image(systemName: "desktopcomputer")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.accentColor)
            
            // 文本控件 (Label)
            Text(message)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("点击次数: \(counter)")
                .font(.title2)
                .foregroundColor(.gray)
            
            // 按钮控件 (Button)
            // action: {} 中放置点击事件的代码
            Button(action: {
                // 在这里处理点击事件
                self.incrementCounter()
            }) {
                // 这里是按钮的外观
                Text("点击我 (Click Me)")
                    .padding()
                    .frame(minWidth: 150)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain) // 移除默认的边框样式，使用自定义样式
            
            // 另一个按钮：重置
            Button("重置") {
                self.counter = 0
                self.message = "Hello, macOS!"
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
    
    // 自定义的方法，处理业务逻辑
    private func incrementCounter() {
        counter += 1
        if counter % 5 == 0 {
            message = "你点击了 \(counter) 次！"
        } else {
            message = "继续点击..."
        }
    }
}

// 预览提供者：负责在 Xcode 右侧画布中显示预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
