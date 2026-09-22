import Foundation
import Cocoa
import Carbon

@MainActor
public final class KeyDriver {
    public static let shared = KeyDriver()

    private var isCancelled: Bool = false

    private init() {}

    public func cancel() {
        isCancelled = true
        FakeIMEOverlay.shared.hide()
    }

    public func executeTyping(segments: [WordSegment], speed: TypingSpeed) async {
        isCancelled = false

        // Initialize caret position once at start of session; never tracks mouse movement during typing!
        FakeIMEOverlay.shared.prepareSession()

        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)

        defer {
            FakeIMEOverlay.shared.hide()
            // Allow the last Cmd+V operation to complete before restoring original clipboard
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                if let original = originalClipboard {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }
        }

        for segment in segments {
            if isCancelled || Task.isCancelled { break }

            switch segment.type {
            case .chinese:
                await typeChineseWithFakeIME(text: segment.raw, speed: speed)
            case .english, .number, .punctuation:
                await injectTextDirectly(segment.raw, speed: speed)
            case .whitespace:
                await injectTextDirectly(" ", speed: speed)
            case .newline:
                await typeNewline()
            }

            // Humanized pause between words (thinking / reviewing pause)
            let wordPause = speed.strokeDelaySeconds * 2.2 + Double.random(in: 0.02...0.05)
            try? await Task.sleep(nanoseconds: UInt64(wordPause * 1_000_000_000))
        }
    }

    /// Types Chinese characters with pinyin typed directly into the input box and floating candidate bar
    private func typeChineseWithFakeIME(text: String, speed: TypingSpeed) async {
        guard !text.isEmpty, !isCancelled else { return }

        // Get continuous pinyin string typed into the input field (e.g. nihao)
        let pinyin = PinyinEngine.shared.convertToPinyin(text)

        // Prepare progressive candidates; panel appears after first pinyin letter
        FakeIMEOverlay.shared.beginPinyinState(candidate: text)

        var typed = ""
        for char in pinyin {
            if isCancelled || Task.isCancelled {
                FakeIMEOverlay.shared.hide()
                return
            }
            typed.append(char)
            FakeIMEOverlay.shared.updateTypedPinyin(typed)
            typeSingleCharUnicode(char)

            let delay = calculateDelay(speed: speed)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Slight human pause before confirming candidate 1 (simulating user hitting Space)
        let confirmDelay = max(0.06, speed.strokeDelaySeconds * 1.5)
        try? await Task.sleep(nanoseconds: UInt64(confirmDelay * 1_000_000_000))

        // Hide candidate bar
        FakeIMEOverlay.shared.hide()

        // Atomically replace the typed pinyin with the target Chinese word
        replaceInlinePinyin(pinyinLength: pinyin.count, target: text)

        // Advance anchor for the next segment
        FakeIMEOverlay.shared.advanceCaret(forText: text)
    }

    /// Types a single Unicode character directly into the active field without modifiers
    private func typeSingleCharUnicode(_ char: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(String(char).utf16)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            keyDown.flags = [] // Strictly clear any modifier flags so it never triggers Cmd+A
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            keyUp.flags = []
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Atomically replaces the typed inline pinyin with target Chinese characters
    private func replaceInlinePinyin(pinyinLength: Int, target: String) {
        guard pinyinLength > 0 else { return }

        // 1. Pre-populate clipboard in advance so there is zero delay
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(target, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let deleteKey: CGKeyCode = 51 // kVK_Delete

        // 2. Option + Delete: removes the entire Latin pinyin word in ONE single frame (NO blue selection highlight!)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true) {
            down.flags = .maskAlternate
            down.post(tap: .cghidEventTap)
        }
        usleep(3000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false) {
            up.flags = []
            up.post(tap: .cghidEventTap)
        }

        usleep(3000)

        // 3. Instant paste Chinese characters within the same visual refresh frame
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        usleep(4000)
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = [] // Ensure Command flag is released
            keyUp.post(tap: .cghidEventTap)
        }
        usleep(8000)
    }

    /// Directly injects non-Chinese text into target window
    private func injectTextDirectly(_ text: String, speed: TypingSpeed) async {
        guard !text.isEmpty, !isCancelled else { return }

        // For small tokens or single chars, simulate stroke delay
        let delay = calculateDelay(speed: speed) * Double(text.count)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        injectTextInstantly(text)

        // Advance anchor for the next segment
        FakeIMEOverlay.shared.advanceCaret(forText: text)
    }

    private func typeNewline() async {
        guard !isCancelled else { return }
        let script = "tell application \"System Events\" to key code 36"
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        FakeIMEOverlay.shared.newlineCaret()
    }

    /// Injects text using clipboard swap & Cmd+V for 100% accuracy in all macOS apps
    private func injectTextInstantly(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Trigger Cmd + V via CGEvent for maximum reliability and speed
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V is 9

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        usleep(6000)
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = []
            keyUp.post(tap: .cghidEventTap)
        }
        usleep(10000)
    }

    private func calculateDelay(speed: TypingSpeed) -> Double {
        let base = speed.strokeDelaySeconds
        if speed.jitterRange > 0 {
            let jitter = Double.random(in: -speed.jitterRange...speed.jitterRange)
            return max(0.012, base + jitter)
        }
        return base
    }
}
