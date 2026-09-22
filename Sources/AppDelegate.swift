import Cocoa
import SwiftUI

public class TyperPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Support Control+C, Control+V, Control+A, Control+X, Control+Z for users with Control shortcut habits
        if event.modifierFlags.contains(.control) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "c" {
                return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            } else if key == "v" {
                return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            } else if key == "a" {
                return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            } else if key == "x" {
                return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            } else if key == "z" {
                return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    public var panel: TyperPanel!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Setup Main Menu (Required by macOS for Command+C/V/A/X/Z shortcuts to work in TextEditor/NSTextView)
        setupMainMenu()

        // Run as accessory (menu bar item)
        NSApp.setActivationPolicy(.accessory)

        // Setup Floating Window / Panel
        let p = TyperPanel(
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
        HotKeyManager.shared.register(option: AppState.shared.hotKeyOption)

        // Silently check accessibility permission on launch without throwing intrusive modals
        AppState.shared.checkPermissions(prompt: false)

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

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Typer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 Typer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 Typer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit Menu (Essential for Cut, Copy, Paste, Select All, Undo shortcuts to work in macOS)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
