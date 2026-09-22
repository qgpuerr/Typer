import Foundation
import NaturalLanguage

public enum SegmentType: String, Codable {
    case chinese
    case english
    case number
    case punctuation
    case whitespace
    case newline
}

public struct WordSegment: Identifiable, Equatable, Codable {
    public let id: UUID
    public var raw: String
    public var pinyin: String
    public var isCustomized: Bool
    public var type: SegmentType

    public init(id: UUID = UUID(), raw: String, pinyin: String, isCustomized: Bool = false, type: SegmentType = .chinese) {
        self.id = id
        self.raw = raw
        self.pinyin = pinyin
        self.isCustomized = isCustomized
        self.type = type
    }
}

public final class PinyinEngine: Sendable {
    public static let shared = PinyinEngine()

    private init() {}

    /// Converts Chinese text to Mandarin Latin Pinyin (lowercase without accents)
    public func convertToPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let result = (mutable as String).lowercased()
        // Strip non-alphanumeric characters, keeping just clean pinyin letters
        let cleaned = result.components(separatedBy: CharacterSet.letters.inverted).joined()
        return cleaned.isEmpty ? result : cleaned
    }

    /// Determines if a character is Chinese
    public func isChineseCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value)
    }

    /// Determines segment type of a string
    public func detectType(_ text: String) -> SegmentType {
        if text == "\n" || text == "\r\n" {
            return .newline
        }
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return .whitespace
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .number
        }
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return .chinese
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            return .english
        }
        return .punctuation
    }

    /// Automatically segments raw text into WordSegments using NaturalLanguage & CFStringTransform
    public func parse(text: String, customMap: [String: String] = [:]) -> [WordSegment] {
        guard !text.isEmpty else { return [] }

        var result: [WordSegment] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text

        var currentIndex = text.startIndex

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            // Handle any gap (punctuation, spaces, newlines) before this token
            if currentIndex < tokenRange.lowerBound {
                let gapStr = String(text[currentIndex..<tokenRange.lowerBound])
                self.parseGaps(gapStr, into: &result)
            }

            let word = String(text[tokenRange])
            let type = self.detectType(word)
            let pinyin: String
            let isCustom: Bool

            if let custom = customMap[word] {
                pinyin = custom
                let defaultPy = (type == .chinese) ? self.convertToPinyin(word) : word
                isCustom = (custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != defaultPy.lowercased())
            } else if type == .chinese {
                pinyin = self.convertToPinyin(word)
                isCustom = false
            } else {
                pinyin = word
                isCustom = false
            }

            result.append(WordSegment(raw: word, pinyin: pinyin, isCustomized: isCustom, type: type))
            currentIndex = tokenRange.upperBound
            return true
        }

        // Handle trailing characters
        if currentIndex < text.endIndex {
            let trailing = String(text[currentIndex..<text.endIndex])
            self.parseGaps(trailing, into: &result)
        }

        return result
    }

    private func parseGaps(_ gapStr: String, into result: inout [WordSegment]) {
        for char in gapStr {
            let str = String(char)
            let type = detectType(str)
            result.append(WordSegment(raw: str, pinyin: str, isCustomized: false, type: type))
        }
    }
}
