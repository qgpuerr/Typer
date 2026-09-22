import Foundation
import NaturalLanguage

public enum InputMethod: String, CaseIterable, Identifiable, Codable {
    case pinyin = "拼音 · 全拼"
    case xiaohe = "双拼 · 小鹤双拼"
    case ziranma = "双拼 · 自然码/微软"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .pinyin: return "全拼"
        case .xiaohe: return "小鹤双拼"
        case .ziranma: return "自然码双拼"
        }
    }

    public var menuTitle: String {
        switch self {
        case .pinyin: return "拼音 · 全拼"
        case .xiaohe: return "双拼 · 小鹤双拼"
        case .ziranma: return "双拼 · 自然码/微软"
        }
    }
}

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

    private let shengmuList = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]

    /// 高频中文复合词/输入法短语白名单（解决 NLTokenizer 语言学最小颗粒度切分过碎的问题）
    public static let defaultLexicon: Set<String> = [
        // 核心默认演示词与应用操作
        "精准", "裁切", "长词", "拟真", "零失误",
        "剪刀", "拖拽", "合并", "打字机", "状态栏", "菜单栏", "悬浮窗",
        // 输入法与输入习惯
        "输入法", "全拼", "双拼", "小鹤双拼", "自然码", "候选词", "翻页", "回车", "空格", "退格",
        "连击", "连打", "快捷键", "辅助功能", "深色模式", "浅色模式", "占位符",
        // 常见科技与日常复合词（易被系统切碎的高频词）
        "跨平台", "自适应", "轻量级", "沉浸式", "开箱即用", "短视频", "黑科技", "互联网",
        "高并发", "多线程", "低代码", "高性能", "端到端", "首选项",
        "微服务", "大模型", "人工智能", "机器学习", "深度学习", "自然语言",
        "与此同时", "不知不觉", "由此可见", "总而言之", "显而易见", "实事求是"
    ]

    private let commonLexicon: Set<String>

    private init(lexicon: Set<String> = PinyinEngine.defaultLexicon) {
        self.commonLexicon = lexicon
    }

    /// Converts Chinese text to Mandarin Latin Pinyin (lowercase without accents)
    public func convertToPinyin(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let result = (mutable as String).lowercased()
        let cleaned = result.components(separatedBy: CharacterSet.letters.inverted).joined()
        return cleaned.isEmpty ? result : cleaned
    }

    /// Converts Chinese text to syllable-separated pinyin with apostrophes (e.g. "ni'hao")
    public func convertToSyllables(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let raw = (mutable as String).lowercased()
        let words = raw.split(separator: " ").map {
            $0.components(separatedBy: CharacterSet.letters.inverted).joined()
        }.filter { !$0.isEmpty }
        return words.isEmpty ? convertToPinyin(text) : words.joined(separator: "'")
    }

    /// Converts Chinese text to Shuangpin (Double Pinyin) keystrokes
    public func convertToShuangpin(_ text: String, scheme: InputMethod) -> String {
        guard scheme != .pinyin else { return convertToPinyin(text) }

        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let syllables = (mutable as String).lowercased().split(separator: " ").map { String($0) }

        return syllables.map { convertSyllableToShuangpin($0, scheme: scheme) }.joined()
    }

    private func convertSyllableToShuangpin(_ syllable: String, scheme: InputMethod) -> String {
        // Clean out any non-letter characters
        let syl = syllable.components(separatedBy: CharacterSet.letters.inverted).joined()
        guard !syl.isEmpty else { return syllable }

        // Find Shengmu (initial)
        var matchedSm = ""
        for sm in shengmuList {
            if syl.hasPrefix(sm) {
                matchedSm = sm
                break
            }
        }

        let ym = String(syl.dropFirst(matchedSm.count))

        if scheme == .xiaohe {
            // Xiaohe Shengmu
            let smKey: String
            if matchedSm == "zh" { smKey = "v" }
            else if matchedSm == "ch" { smKey = "i" }
            else if matchedSm == "sh" { smKey = "u" }
            else { smKey = matchedSm }

            // Xiaohe Yunmu
            let ymMap: [String: String] = [
                "iu": "q", "ei": "w", "e": "e", "uan": "r", "van": "r", "er": "r",
                "ue": "t", "ve": "t", "un": "y", "vn": "y", "u": "u", "i": "i",
                "o": "o", "uo": "o", "ie": "p", "a": "a", "ong": "s", "iong": "s",
                "ai": "d", "en": "f", "eng": "g", "ang": "h", "an": "j",
                "ing": "k", "uai": "k", "iang": "l", "uang": "l", "ou": "z",
                "ia": "x", "ua": "x", "ao": "c", "ui": "v", "v": "v",
                "in": "b", "iao": "n", "ian": "m"
            ]

            if matchedSm.isEmpty {
                // Zero initial (零声母)
                if syl.count == 1 {
                    return syl + syl // a->aa, o->oo, e->ee
                } else if syl.count == 2 {
                    return syl // ai, an, ao, ou, en, er
                } else {
                    let first = String(syl.prefix(1))
                    let mappedYm = ymMap[syl] ?? String(syl.suffix(1))
                    return first + mappedYm
                }
            } else {
                let ymKey = ymMap[ym] ?? ym
                return smKey + ymKey
            }
        } else {
            // Ziranma / Microsoft Shengmu
            let smKey: String
            if matchedSm == "zh" { smKey = "v" }
            else if matchedSm == "ch" { smKey = "i" }
            else if matchedSm == "sh" { smKey = "u" }
            else { smKey = matchedSm }

            // Ziranma Yunmu
            let ymMap: [String: String] = [
                "iu": "q", "ia": "w", "ua": "w", "e": "e", "uan": "r", "van": "r", "er": "r",
                "ue": "t", "ve": "t", "uai": "y", "ing": "y", "u": "u", "i": "i",
                "o": "o", "uo": "o", "un": "p", "vn": "p",
                "a": "a", "ong": "s", "iong": "s", "iang": "d", "uang": "d",
                "en": "f", "eng": "g", "ang": "h", "an": "j", "ao": "k", "ai": "l",
                "ei": "z", "ie": "x", "iao": "c", "ui": "v", "v": "v",
                "ou": "b", "in": "n", "ian": "m"
            ]

            if matchedSm.isEmpty {
                // Zero initial in Ziranma begins with 'o'
                if syl.count == 1 {
                    return "o" + syl
                } else {
                    let ymKey = ymMap[syl] ?? String(syl.suffix(1))
                    return "o" + ymKey
                }
            } else {
                let ymKey = ymMap[ym] ?? ym
                return smKey + ymKey
            }
        }
    }

    /// Converts Chinese text based on selected input method
    public func convertText(_ text: String, inputMethod: InputMethod) -> String {
        switch inputMethod {
        case .pinyin:
            return convertToPinyin(text)
        case .xiaohe, .ziranma:
            return convertToShuangpin(text, scheme: inputMethod)
        }
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

    /// Automatically segments raw text into WordSegments using NaturalLanguage & selected InputMethod
    public func parse(text: String, customMap: [String: String] = [:], inputMethod: InputMethod = .pinyin) -> [WordSegment] {
        guard !text.isEmpty else { return [] }

        var result: [WordSegment] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text

        var currentIndex = text.startIndex

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            if currentIndex < tokenRange.lowerBound {
                let gapStr = String(text[currentIndex..<tokenRange.lowerBound])
                self.parseGaps(gapStr, into: &result)
            }

            let word = String(text[tokenRange])
            let type = self.detectType(word)
            let strokes: String
            let isCustom: Bool

            if let custom = customMap[word] {
                strokes = custom
                let defaultVal = (type == .chinese) ? self.convertText(word, inputMethod: inputMethod) : word
                isCustom = (custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != defaultVal.lowercased())
            } else if type == .chinese {
                strokes = self.convertText(word, inputMethod: inputMethod)
                isCustom = false
            } else {
                strokes = word
                isCustom = false
            }

            result.append(WordSegment(raw: word, pinyin: strokes, isCustomized: isCustom, type: type))
            currentIndex = tokenRange.upperBound
            return true
        }

        if currentIndex < text.endIndex {
            let trailing = String(text[currentIndex..<text.endIndex])
            self.parseGaps(trailing, into: &result)
        }

        return mergeLexiconPhrases(result, customMap: customMap, inputMethod: inputMethod)
    }

    private func mergeLexiconPhrases(_ segments: [WordSegment], customMap: [String: String], inputMethod: InputMethod) -> [WordSegment] {
        guard segments.count >= 2 else { return segments }

        var output: [WordSegment] = []
        var i = 0
        while i < segments.count {
            var matched = false
            let maxLen = min(4, segments.count - i)
            if maxLen >= 2 {
                for length in (2...maxLen).reversed() {
                    let slice = segments[i..<(i + length)]
                    guard slice.allSatisfy({ $0.type == .chinese }) else { continue }
                    let combined = slice.map(\.raw).joined()

                    if commonLexicon.contains(combined) || customMap[combined] != nil {
                        let strokes: String
                        let isCustom: Bool
                        if let custom = customMap[combined] {
                            strokes = custom
                            let defaultVal = self.convertText(combined, inputMethod: inputMethod)
                            isCustom = (custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != defaultVal.lowercased())
                        } else {
                            strokes = self.convertText(combined, inputMethod: inputMethod)
                            isCustom = false
                        }
                        output.append(WordSegment(raw: combined, pinyin: strokes, isCustomized: isCustom, type: .chinese))
                        i += length
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                output.append(segments[i])
                i += 1
            }
        }
        return output
    }

    private func parseGaps(_ gapStr: String, into result: inout [WordSegment]) {
        for char in gapStr {
            let str = String(char)
            let type = detectType(str)
            result.append(WordSegment(raw: str, pinyin: str, isCustomized: false, type: type))
        }
    }
}
