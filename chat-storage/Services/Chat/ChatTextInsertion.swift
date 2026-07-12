//
//  ChatTextInsertion.swift
//  chat-storage
//

import Foundation

struct ChatTextInsertion {
    static func insert(_ token: String, into text: String, selectedRange: NSRange) -> (text: String, selectedRange: NSRange) {
        let source = text as NSString
        let location = max(0, min(selectedRange.location, source.length))
        let maxLength = max(0, source.length - location)
        let length = max(0, min(selectedRange.length, maxLength))
        let safeRange = NSRange(location: location, length: length)
        let updated = source.replacingCharacters(in: safeRange, with: token)
        let cursor = location + (token as NSString).length
        return (updated, NSRange(location: cursor, length: 0))
    }
}
