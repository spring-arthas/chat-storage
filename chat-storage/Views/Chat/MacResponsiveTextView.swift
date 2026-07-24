//
//  MacResponsiveTextView.swift
//  chat-storage
//

import AppKit
import SwiftUI

struct MacResponsiveTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertToken: String?
    @Binding var isComposing: Bool
    var onPasteImage: ((NSImage) -> Void)?
    var onSendTriggered: () -> Void

    init(
        text: Binding<String>,
        insertToken: Binding<String?> = .constant(nil),
        isComposing: Binding<Bool> = .constant(false),
        onPasteImage: ((NSImage) -> Void)? = nil,
        onSendTriggered: @escaping () -> Void
    ) {
        self._text = text
        self._insertToken = insertToken
        self._isComposing = isComposing
        self.onPasteImage = onPasteImage
        self.onSendTriggered = onSendTriggered
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let customTextView = CustomNSTextView()
        customTextView.delegate = context.coordinator
        customTextView.onPasteImage = onPasteImage
        customTextView.onMarkedTextChanged = { isComposing in
            self.isComposing = isComposing
        }
        customTextView.drawsBackground = false
        customTextView.isRichText = false
        customTextView.font = NSFont.systemFont(ofSize: 14)
        customTextView.autoresizingMask = [.width]
        customTextView.isHorizontallyResizable = false
        customTextView.isVerticallyResizable = true
        customTextView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = customTextView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }
        textView.onPasteImage = onPasteImage
        textView.onMarkedTextChanged = { isComposing in
            self.isComposing = isComposing
        }
        if let token = insertToken, !token.isEmpty {
            let result = ChatTextInsertion.insert(token, into: textView.string, selectedRange: textView.selectedRange())
            textView.string = result.text
            textView.setSelectedRange(result.selectedRange)
            DispatchQueue.main.async {
                self.text = result.text
                self.insertToken = nil
            }
            return
        }
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacResponsiveTextView

        init(_ parent: MacResponsiveTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            self.parent.isComposing = textView.hasMarkedText()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // 中文输入法存在未确认的标记文本时，Enter 应先交给输入法确认候选词。
                guard !textView.hasMarkedText() else {
                    return false
                }
                let event = NSApp.currentEvent
                let flags = event?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    self.parent.onSendTriggered()
                    return true
                }
            }
            return false
        }
    }
}

class CustomNSTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    var onMarkedTextChanged: ((Bool) -> Void)?

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChanged?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChanged?(false)
    }

    override func paste(_ sender: Any?) {
        if let image = Self.image(from: NSPasteboard.general) {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }

    private static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType.tiff
        ]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }

        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])?.first as? URL,
           ChatImageFormat.isSupported(fileName: fileURL.lastPathComponent) {
            return NSImage(contentsOf: fileURL)
        }

        for value in [pasteboard.string(forType: .fileURL), pasteboard.string(forType: .string)].compactMap({ $0 }) {
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileURL: URL?
            if candidate.hasPrefix("file://") {
                fileURL = URL(string: candidate)
            } else if candidate.hasPrefix("/") {
                fileURL = URL(fileURLWithPath: candidate)
            } else {
                fileURL = nil
            }
            guard let fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  ChatImageFormat.isSupported(fileName: fileURL.lastPathComponent) else {
                continue
            }
            if let image = NSImage(contentsOf: fileURL) {
                return image
            }
        }
        return nil
    }
}
