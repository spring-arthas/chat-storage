//
//  MacResponsiveTextView.swift
//  chat-storage
//

import AppKit
import SwiftUI

struct MacResponsiveTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertToken: String?
    var onPasteImage: ((NSImage) -> Void)?
    var onSendTriggered: () -> Void

    init(
        text: Binding<String>,
        insertToken: Binding<String?> = .constant(nil),
        onPasteImage: ((NSImage) -> Void)? = nil,
        onSendTriggered: @escaping () -> Void
    ) {
        self._text = text
        self._insertToken = insertToken
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
        if textView.string != text {
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
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let flags = event?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) || flags.contains(.control) {
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

    override func paste(_ sender: Any?) {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }
}
