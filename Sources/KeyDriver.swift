import Foundation
import Cocoa

@MainActor
public final class KeyDriver {
    public static let shared = KeyDriver()

    private var isCancelled: Bool = false

    private init() {}

    public func cancel() {
        isCancelled = true
    }

    public func executeTyping(segments: [WordSegment], speed: TypingSpeed) async {
        isCancelled = false

        for segment in segments {
            if isCancelled || Task.isCancelled { break }

            switch segment.type {
            case .chinese:
                await typeChineseSegment(pinyin: segment.pinyin, speed: speed)
            case .english:
                await typeEnglishSegment(text: segment.raw, speed: speed)
            case .number:
                await typeNumberSegment(text: segment.raw, speed: speed)
            case .punctuation:
                await typePunctuationSegment(text: segment.raw, speed: speed)
            case .whitespace:
                await typeWhitespace()
            case .newline:
                await typeNewline()
            }

            // Humanized pause between words (thinking / reviewing pause)
            let wordPause = speed.strokeDelaySeconds * 2.5 + Double.random(in: 0.02...0.06)
            try? await Task.sleep(nanoseconds: UInt64(wordPause * 1_000_000_000))
        }
    }

    private func typeChineseSegment(pinyin: String, speed: TypingSpeed) async {
        let cleanPinyin = pinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanPinyin.isEmpty else { return }

        var scriptLines = ["tell application \"System Events\""]
        for char in cleanPinyin {
            let delay = calculateDelay(speed: speed)
            scriptLines.append("    keystroke \"\(char)\"")
            scriptLines.append(String(format: "    delay %.3f", delay))
        }
        // Small pause for IME candidate box to settle, then Space (key code 49) to commit candidate #1
        scriptLines.append("    delay 0.08")
        scriptLines.append("    key code 49")
        scriptLines.append("end tell")

        await runScript(scriptLines.joined(separator: "\n"))
    }

    private func typeEnglishSegment(text: String, speed: TypingSpeed) async {
        guard !text.isEmpty else { return }

        var scriptLines = ["tell application \"System Events\""]
        for char in text {
            let delay = calculateDelay(speed: speed)
            let escaped = escapeForAppleScript(String(char))
            scriptLines.append("    keystroke \"\(escaped)\"")
            scriptLines.append(String(format: "    delay %.3f", delay))
        }
        // In Chinese IME, pressing Return (key code 36) commits English raw input directly
        scriptLines.append("    delay 0.05")
        scriptLines.append("    key code 36")
        scriptLines.append("end tell")

        await runScript(scriptLines.joined(separator: "\n"))
    }

    private func typeNumberSegment(text: String, speed: TypingSpeed) async {
        guard !text.isEmpty else { return }

        // Numbers commit immediately in macOS IME without Return or Space.
        var scriptLines = ["tell application \"System Events\""]
        for char in text {
            let delay = calculateDelay(speed: speed)
            scriptLines.append("    keystroke \"\(char)\"")
            scriptLines.append(String(format: "    delay %.3f", delay))
        }
        scriptLines.append("end tell")

        await runScript(scriptLines.joined(separator: "\n"))
    }

    private func typePunctuationSegment(text: String, speed: TypingSpeed) async {
        guard !text.isEmpty else { return }

        // Map Chinese punctuation to standard keystrokes in Apple IME
        let puncMap: [String: String] = [
            "，": ",",
            "。": ".",
            "！": "!",
            "？": "?",
            "：": ":",
            "；": ";",
            "、": "\\",
            "（": "(",
            "）": ")"
        ]

        var scriptLines = ["tell application \"System Events\""]
        for char in text {
            let s = String(char)
            let strokeChar = puncMap[s] ?? s
            let escaped = escapeForAppleScript(strokeChar)
            let delay = calculateDelay(speed: speed)
            scriptLines.append("    keystroke \"\(escaped)\"")
            scriptLines.append(String(format: "    delay %.3f", delay))
        }
        scriptLines.append("end tell")

        await runScript(scriptLines.joined(separator: "\n"))
    }

    private func typeWhitespace() async {
        let script = "tell application \"System Events\" to key code 49"
        await runScript(script)
    }

    private func typeNewline() async {
        let script = "tell application \"System Events\" to key code 36"
        await runScript(script)
    }

    private func calculateDelay(speed: TypingSpeed) -> Double {
        let base = speed.strokeDelaySeconds
        if speed.jitterRange > 0 {
            let jitter = Double.random(in: -speed.jitterRange...speed.jitterRange)
            return max(0.01, base + jitter)
        }
        return base
    }

    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runScript(_ script: String) async {
        guard !isCancelled else { return }

        await Task.detached {
            Self.executeScriptSync(script)
        }.value
    }

    private nonisolated static func executeScriptSync(_ script: String) {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                NSLog("[KeyDriver] NSAppleScript error: %@, attempting osascript fallback", err)
                _ = runViaOsaProcessSync(script)
            }
        } else {
            _ = runViaOsaProcessSync(script)
        }
    }

    private nonisolated static func runViaOsaProcessSync(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("[KeyDriver] osascript fallback failed: %@", error.localizedDescription)
            return false
        }
    }
}
