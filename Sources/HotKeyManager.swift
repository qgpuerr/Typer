import Carbon
import Cocoa

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    public var onHotKeyPressed: (@Sendable () -> Void)?

    private init() {}

    public func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            Task { @MainActor in
                HotKeyManager.shared.onHotKeyPressed?()
            }
            return noErr
        }

        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x53545950), id: 1)
        // Option + T (kVK_ANSI_T is 17)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(optionKey), hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }
}
