import Carbon
import Cocoa

public struct HotKeyOption: Identifiable, Equatable, Codable, Sendable {
    public var id: String { display }
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var display: String
    public var title: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String, title: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
        self.title = title
    }

    public static let defaultOption = HotKeyOption(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(optionKey),
        display: "⌥T",
        title: "⌥T (Option + T) · 默认"
    )

    public static let presets: [HotKeyOption] = [
        defaultOption,
        HotKeyOption(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey), display: "⌃T", title: "⌃T (Control + T)"),
        HotKeyOption(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey), display: "⌘⌥T", title: "⌘⌥T (Command + Option + T)"),
        HotKeyOption(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey), display: "⌥R", title: "⌥R (Option + R)"),
        HotKeyOption(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey), display: "⌥P", title: "⌥P (Option + P)"),
        HotKeyOption(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), display: "⌥Space", title: "⌥Space (Option + 空格)"),
        HotKeyOption(keyCode: UInt32(kVK_F6), modifiers: 0, display: "F6", title: "F6 (单键)"),
        HotKeyOption(keyCode: UInt32(kVK_F8), modifiers: 0, display: "F8", title: "F8 (单键)")
    ]
}

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled: Bool = false
    private var escapeGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?
    public var onHotKeyPressed: (@Sendable () -> Void)?

    private init() {}

    public func register(option: HotKeyOption = .defaultOption) {
        unregister()
        installEscapeToStopTypingIfNeeded()

        if !isHandlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
                Task { @MainActor in
                    HotKeyManager.shared.onHotKeyPressed?()
                }
                return noErr
            }
            InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, nil)
            isHandlerInstalled = true
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x53545950), id: 1)
        RegisterEventHotKey(option.keyCode, option.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Esc stops an in-progress typing session (works while focus is in another app).
    private func installEscapeToStopTypingIfNeeded() {
        guard escapeGlobalMonitor == nil else { return }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in
                if AppState.shared.isTyping {
                    AppState.shared.stopTyping()
                }
            }
        }

        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            if AppState.shared.isTyping {
                AppState.shared.stopTyping()
                return nil
            }
            return event
        }
    }
}
