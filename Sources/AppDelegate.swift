import Cocoa
import SwiftUI

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    public var panel: NSPanel!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Run as accessory (menu bar item)
        NSApp.setActivationPolicy(.accessory)

        // Setup Floating Window / Panel
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.title = "Typer"
        p.titleVisibility = .visible
        p.titlebarAppearsTransparent = true
        p.appearance = NSAppearance(named: .aqua)
        p.backgroundColor = NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.986, alpha: 1.0)
        p.minSize = NSSize(width: 520, height: 560)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.contentView = NSHostingView(rootView: ContentView())
        self.panel = p

        // Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Typer")?.withSymbolConfiguration(config) {
                img.isTemplate = true
                button.image = img
            } else if let img = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Typer") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⌨️"
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Register Global Hotkey Option+T
        HotKeyManager.shared.onHotKeyPressed = {
            Task { @MainActor in
                AppState.shared.toggleTyping()
            }
        }
        HotKeyManager.shared.register()

        // Trigger system accessibility check and prompt on launch
        AppState.shared.checkPermissions(prompt: true)

        // Auto-refresh permission status when app becomes active
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.checkPermissions(prompt: false)
            }
        }

        // Show window on launch
        showPanel()
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel(sender)
        }
    }

    public func togglePanel(_ sender: Any? = nil) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    public func showPanel() {
        if let button = statusItem.button, let screen = button.window?.screen {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
            let panelSize = panel.frame.size
            let x = min(max(buttonFrame.midX - panelSize.width / 2, 20), screen.visibleFrame.maxX - panelSize.width - 20)
            let y = buttonFrame.minY - panelSize.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: max(y, 20)))
        } else {
            panel.center()
        }
        AppState.shared.checkPermissions(prompt: false)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏 Typer", action: #selector(openPanelDirectly), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出应用", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanelDirectly() {
        togglePanel(nil)
    }

    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
