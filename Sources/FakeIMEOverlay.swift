import SwiftUI
import Cocoa
import ApplicationServices

public struct CaretLocation: Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var height: CGFloat

    public init(x: CGFloat, y: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.height = height
    }
}

@MainActor
public final class FakeIMEOverlay: ObservableObject {
    public static let shared = FakeIMEOverlay()

    @Published public var mainCandidate: String = ""
    @Published public var secondaryCandidates: [String] = []

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FakeIMEView>?

    // Caret anchoring state for the current typing session
    private var sessionCaret: CaretLocation = CaretLocation(x: 200, y: 500, height: 18)
    private var currentCaret: CaretLocation = CaretLocation(x: 200, y: 500, height: 18)
    private var isDynamicCaretAvailable: Bool = false

    // Progressive candidate state (edge-type-edge-refine like a real IME)
    private var sessionTarget: String = ""
    private var sessionSyllables: [String] = []
    private var sessionFullPinyin: String = ""

    private init() {}

    private func ensurePanel() {
        if panel != nil { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))

        let host = NSHostingView(rootView: FakeIMEView(overlay: self))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = host
        self.hostingView = host
        self.panel = p
    }

    /// Initializes anchor position ONCE before starting typing.
    public func prepareSession() {
        // 1. Try precise AX caret (native apps: TextEdit, Notes, Pages, etc.)
        if let caret = queryPreciseCaretLocation() {
            self.sessionCaret = caret
            self.currentCaret = caret
            self.isDynamicCaretAvailable = true
            return
        }
        // Target app may not be fully focused yet — retry after a brief delay
        usleep(150_000)
        if let caret = queryPreciseCaretLocation() {
            self.sessionCaret = caret
            self.currentCaret = caret
            self.isDynamicCaretAvailable = true
            return
        }
        // 2. Browser/Electron apps: the user clicked the input field to place cursor there,
        //    so mouse position ≈ text cursor position. Snapshot ONCE, never re-tracked.
        let mouse = NSEvent.mouseLocation
        let fallback = CaretLocation(x: mouse.x, y: mouse.y, height: 18)
        self.sessionCaret = fallback
        self.currentCaret = fallback
        self.isDynamicCaretAvailable = false
    }

    /// Prepares progressive IME state for a Chinese segment. Panel stays hidden until first letter.
    public func beginPinyinState(candidate: String) {
        ensurePanel()
        sessionTarget = candidate
        sessionSyllables = PinyinEngine.shared.convertToSyllables(candidate)
            .split(separator: "'")
            .map(String.init)
            .filter { !$0.isEmpty }
        if sessionSyllables.isEmpty {
            sessionSyllables = [PinyinEngine.shared.convertToPinyin(candidate)].filter { !$0.isEmpty }
        }
        sessionFullPinyin = sessionSyllables.joined()
        mainCandidate = ""
        secondaryCandidates = []

        // Only override position when we have a REAL pixel-accurate caret from AX (native apps).
        // For browser/Electron apps, trust advanceCaret tracking so the popup moves with text.
        if let live = queryPreciseCaretLocation() {
            self.currentCaret = live
        }
    }

    /// Refresh candidates after each typed pinyin letter — grows/refines like a real IME.
    public func updateTypedPinyin(_ typed: String) {
        guard !sessionTarget.isEmpty, !typed.isEmpty else { return }

        let revealed = revealedCharacterCount(typedLength: typed.count)
        let main = String(sessionTarget.prefix(max(1, revealed)))
        mainCandidate = main
        secondaryCandidates = generateProgressiveSecondaries(
            target: sessionTarget,
            revealedMain: main,
            typedLength: typed.count,
            fullLength: max(sessionFullPinyin.count, 1)
        )
        presentPanel()
    }

    /// How many target characters to show given typed pinyin length (syllable-aware).
    private func revealedCharacterCount(typedLength: Int) -> Int {
        guard !sessionSyllables.isEmpty else {
            let ratio = Double(typedLength) / Double(max(sessionFullPinyin.count, 1))
            return max(1, min(sessionTarget.count, Int(ceil(ratio * Double(sessionTarget.count)))))
        }

        var covered = 0
        var revealed = 0
        for syl in sessionSyllables {
            if typedLength >= covered + syl.count {
                covered += syl.count
                revealed += 1
            } else if typedLength > covered {
                // Mid-syllable: IME already predicts this character
                revealed += 1
                break
            } else {
                break
            }
        }
        return max(1, min(sessionTarget.count, revealed))
    }

    private func presentPanel() {
        ensurePanel()
        guard let panel = panel, let host = hostingView else { return }

        host.rootView = FakeIMEView(overlay: self)
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let panelW = max(fitting.width, 180)
        let panelH = max(fitting.height, 40)

        let caretPoint = NSPoint(x: currentCaret.x, y: currentCaret.y)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -80, dy: -80).contains(caretPoint) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var originX = currentCaret.x - 4.0
        var originY = currentCaret.y - panelH - 6.0

        if originY < visible.minY + 4.0 {
            originY = currentCaret.y + currentCaret.height + 6.0
        }

        originX = min(max(originX, visible.minX + 8), max(visible.minX + 8, visible.maxX - panelW - 8))
        originY = min(max(originY, visible.minY + 4), max(visible.minY + 4, visible.maxY - panelH - 4))

        panel.alphaValue = 1
        panel.setFrame(NSRect(x: originX, y: originY, width: panelW, height: panelH), display: true)
        panel.orderFrontRegardless()
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
    }

    public func advanceCaret(forText text: String) {
        var width: CGFloat = 0
        for ch in text {
            width += ch.isASCII ? 8.5 : 15.0 // Realistic average character width (14-16pt font)
        }
        self.currentCaret.x += width
    }

    public func newlineCaret() {
        self.currentCaret.x = sessionCaret.x
        self.currentCaret.y -= 22.0
    }

    public func hide() {
        sessionTarget = ""
        sessionSyllables = []
        sessionFullPinyin = ""
        mainCandidate = ""
        secondaryCandidates = []
        panel?.orderOut(nil)
    }

    // MARK: - Caret coordinate resolution via macOS Accessibility API

    /// Returns the precise pixel caret location (only when AX returns real cursor bounds)
    public func queryPreciseCaretLocation() -> CaretLocation? {
        let primaryScreenH = NSScreen.screens.first?.frame.height ?? 900
        guard let appElem = resolveTargetAppElement() else { return nil }

        func extractCaret(from elem: AXUIElement) -> CaretLocation? {
            var rangeVal: AnyObject?
            if AXUIElementCopyAttributeValue(elem, kAXSelectedTextRangeAttribute as CFString, &rangeVal) == .success,
               let rv = rangeVal {
                var boundsVal: AnyObject?
                if AXUIElementCopyParameterizedAttributeValue(elem, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &boundsVal) == .success,
                   let bv = boundsVal {
                    var rect = CGRect.zero
                    if AXValueGetValue(bv as! AXValue, .cgRect, &rect),
                       rect.origin.x > 1.0,
                       rect.origin.y > 1.0,
                       rect.origin.y < (primaryScreenH - 10.0),
                       rect.size.height >= 8.0,
                       rect.size.height <= 80.0 {
                        return convertAXRectToCaret(rect, primaryScreenH: primaryScreenH)
                    }
                }
            }
            return nil
        }

        var focusedUI: AnyObject?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &focusedUI) == .success,
           let el = focusedUI as! AXUIElement? {
            if let caret = extractCaret(from: el) {
                return caret
            }
            var childFocus: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &childFocus) == .success,
               let childEl = childFocus as! AXUIElement?,
               let caret = extractCaret(from: childEl) {
                return caret
            }
        }
        return nil
    }

    /// Returns the focused input field's frame origin as a rough anchor (for apps that don't report caret bounds)
    public func queryFrameAnchor() -> CaretLocation? {
        let primaryScreenH = NSScreen.screens.first?.frame.height ?? 900
        guard let appElem = resolveTargetAppElement() else { return nil }

        var focusedUI: AnyObject?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &focusedUI) == .success,
           let el = focusedUI as! AXUIElement? {
            var posVal: AnyObject?, sizeVal: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posVal) == .success,
               AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let pv = posVal, let sv = sizeVal {
                var pt = CGPoint.zero
                var sz = CGSize.zero
                if AXValueGetValue(pv as! AXValue, .cgPoint, &pt),
                   AXValueGetValue(sv as! AXValue, .cgSize, &sz),
                   sz.width > 20, sz.height >= 12 {
                    let lineH: CGFloat = min(sz.height, 20.0)
                    return convertAXRectToCaret(CGRect(x: pt.x + 8.0, y: pt.y, width: 1, height: lineH), primaryScreenH: primaryScreenH)
                }
            }
        }
        return nil
    }

    /// Combined query: precise caret first, then frame anchor fallback (used only for initial session setup)
    public func queryActiveCaretLocation() -> CaretLocation? {
        return queryPreciseCaretLocation() ?? queryFrameAnchor()
    }

    /// Resolves the target app's AXUIElement
    private func resolveTargetAppElement() -> AXUIElement? {
        let targetApp: NSRunningApplication?
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        } else {
            targetApp = AppState.shared.lastActiveApp
        }
        guard let target = targetApp else { return nil }
        return AXUIElementCreateApplication(target.processIdentifier)
    }

    /// AX/Quartz rects are top-left on the primary display; Cocoa windows are bottom-left.
    private func convertAXRectToCaret(_ rect: CGRect, primaryScreenH: CGFloat) -> CaretLocation {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        let top = primary?.frame.maxY ?? primaryScreenH
        return CaretLocation(
            x: rect.origin.x,
            y: top - rect.origin.y - rect.size.height,
            height: rect.size.height
        )
    }

    // MARK: - Progressive Mock Candidates

    private static let fullWordAlts: [String: [String]] = [
        "你好": ["拟好", "你号", "泥嚎", "拟稿"],
        "功能演示": ["功能演示", "工能演示", "功用演示", "功能演试"],
        "功能": ["工能", "供能", "攻能", "公能"],
        "演示": ["严实", "岩石", "掩饰", "研制"],
        "屏幕": ["凭募", "屏暮", "评议", "平幕"],
        "输入": ["叔入", "术入", "熟人", "数入"],
        "测试": ["侧视", "策士", "撤市", "测式"],
        "代码": ["带码", "带吗", "贷码", "待码"],
        "开发": ["开法", "凯发", "开端", "慨发"],
        "快捷键": ["快结件", "快截键", "快捷", "键入"],
        "自然": ["孜然", "自燃", "字燃", "滋然"],
        "世界": ["视界", "市街", "世杰", "事界"]
    ]

    private static let singleCharAlts: [Character: [String]] = [
        "你": ["尼", "泥", "逆", "呢"],
        "好": ["号", "豪", "浩", "耗"],
        "功": ["工", "公", "攻", "供"],
        "能": ["年", "内", "那", "呢"],
        "演": ["严", "研", "言", "延"],
        "示": ["是", "事", "市", "式"],
        "屏": ["平", "凭", "评", "瓶"],
        "幕": ["目", "木", "母", "牧"],
        "输": ["书", "数", "术", "属"],
        "入": ["如", "乳", "辱", "儒"],
        "测": ["侧", "策", "册", "厕"],
        "试": ["是", "事", "市", "式"],
        "代": ["带", "待", "贷", "戴"],
        "码": ["马", "吗", "妈", "骂"],
        "开": ["凯", "慨", "楷", "揩"],
        "发": ["法", "罚", "乏", "伐"],
        "快": ["块", "筷", "侩", "郐"],
        "捷": ["结", "节", "杰", "截"],
        "键": ["见", "建", "件", "间"],
        "自": ["字", "子", "紫", "资"],
        "然": ["燃", "染", "冉", "苒"],
        "世": ["是", "事", "市", "式"],
        "界": ["接", "结", "解", "介"]
    ]

    private func generateProgressiveSecondaries(
        target: String,
        revealedMain: String,
        typedLength: Int,
        fullLength: Int
    ) -> [String] {
        var pool: [String] = []

        // Early stage: mostly single-character lookalikes (real IME before phrase locks in)
        let early = typedLength < max(2, fullLength / 2)
        if early, let first = revealedMain.first,
           let singles = Self.singleCharAlts[first] {
            pool.append(contentsOf: singles)
        }

        // Mid/late: shorter prefixes of the target word as competing candidates
        if target.count > 1 {
            for len in 1..<min(revealedMain.count + 1, target.count) {
                let prefix = String(target.prefix(len))
                if prefix != revealedMain { pool.append(prefix) }
            }
        }

        // Full-word alternatives once enough pinyin is typed
        if typedLength >= max(2, fullLength * 2 / 3) {
            if let alts = Self.fullWordAlts[target] {
                pool.append(contentsOf: alts)
            } else if revealedMain.count == target.count {
                // Synthetic near-misses for unknown words
                if target.count >= 2 {
                    pool.append(String(target.prefix(target.count - 1)))
                    pool.append(String(target.dropFirst()))
                }
            }
        }

        // If main is still a prefix of the final word, offer the full word later in the list
        // (real IMEs often keep the phrase as a lower-ranked option mid-input)
        if revealedMain != target, typedLength >= 2 {
            pool.append(target)
        }

        var unique: [String] = []
        for item in pool {
            if item != revealedMain, !unique.contains(item) {
                unique.append(item)
            }
            if unique.count >= 4 { break }
        }

        let filler = ["选择", "提示", "输入", "其他"]
        for item in filler where unique.count < 4 {
            if item != revealedMain, !unique.contains(item) {
                unique.append(item)
            }
        }
        return Array(unique.prefix(4))
    }
}

public struct FakeIMEView: View {
    @ObservedObject var overlay: FakeIMEOverlay
    @ObservedObject private var appState = AppState.shared

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text("1")
                    .font(.system(size: 13, weight: .bold))
                Text(overlay.mainCandidate)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(appState.imeThemeColor)
            )
            .fixedSize()

            ForEach(Array(overlay.secondaryCandidates.enumerated()), id: \.offset) { index, cand in
                HStack(spacing: 4) {
                    Text("\(index + 2)")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(TyperTheme.textTertiary)
                    Text(cand)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(TyperTheme.textPrimary)
                }
                .fixedSize()
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(TyperTheme.textSecondary)
                .padding(.trailing, 4)
        }
        .padding(.leading, 5)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(6)
        .fixedSize()
        .ignoresSafeArea()
    }
}
