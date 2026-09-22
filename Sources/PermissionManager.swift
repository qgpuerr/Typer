import Cocoa
import ApplicationServices

@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public var isAccessibilityGranted: Bool = false
    private var pollTimer: Timer?

    private init() {
        self.isAccessibilityGranted = checkAccessibility(prompt: false)
        startPollingIfNeeded()
    }

    public func startPollingIfNeeded() {
        guard !isAccessibilityGranted else { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = trusted
                    AppState.shared.hasAccessibilityPermission = trusted
                    if trusted {
                        self.stopPolling()
                    }
                }
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @discardableResult
    public func checkAccessibility(prompt: Bool = false) -> Bool {
        let trusted: Bool
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        self.isAccessibilityGranted = trusted
        if !trusted {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
        return trusted
    }

    public func openAccessibilitySettings() {
        // Directly navigate to System Settings > Privacy > Accessibility without redundant alert
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPollingIfNeeded()
    }
}
