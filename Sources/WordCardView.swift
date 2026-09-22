import SwiftUI
import Cocoa
import UniformTypeIdentifiers

@MainActor
final class CursorManager {
    static let shared = CursorManager()

    lazy var scissorCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let base = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil) else { return false }
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [NSColor(white: 0.15, alpha: 1.0)]))
            guard let sym = base.withSymbolConfiguration(config) else { return false }

            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: rect.width / 2, y: rect.height / 2)
            ctx.rotate(by: .pi / 2) // Counterclockwise 90 degrees
            ctx.translateBy(x: -rect.width / 2, y: -rect.height / 2)

            let symSize = sym.size
            let drawRect = NSRect(
                x: (rect.width - symSize.width) / 2,
                y: (rect.height - symSize.height) / 2,
                width: symSize.width,
                height: symSize.height
            )
            sym.draw(in: drawRect)
            ctx.restoreGState()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 12, y: 18))
    }()
}

struct CustomCursorView: NSViewRepresentable {
    let cursor: NSCursor?

    func makeNSView(context: Context) -> CursorHostingNSView {
        let view = CursorHostingNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorHostingNSView, context: Context) {
        nsView.cursor = cursor
    }
}

final class CursorHostingNSView: NSView {
    var cursor: NSCursor? {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let cursor = cursor {
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

public struct WordCardView: View {
    @ObservedObject var appState: AppState
    let segment: WordSegment
    var isHighlightedForMerge: Bool = false

    @State private var isHovering: Bool = false
    @State private var cutLineX: CGFloat? = nil
    @State private var nearestCutIndex: Int? = nil
    @State private var isDropTarget: Bool = false

    private var canBeCut: Bool {
        segment.raw.count >= 2 && segment.type == .chinese
    }

    public var body: some View {
        Group {
            if segment.type == .chinese {
                // Only Chinese words with Pinyin have the card box
                chineseCardView
            } else {
                // Numbers, Punctuation, English: Pure unboxed text with matching baseline
                inlineTextView
            }
        }
    }

    // MARK: - Inline Text View (Numbers, Punctuation, English - No Box, Baseline Aligned)
    private var inlineTextView: some View {
        Text(segment.raw)
            .font(.system(size: 14, weight: segment.type == .number ? .semibold : .medium))
            .foregroundColor(TyperTheme.textPrimary)
            .frame(height: 22)
            .padding(.horizontal, segment.type == .punctuation ? 2 : 4)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlightedForMerge ? TyperTheme.cardBg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isHighlightedForMerge ? TyperTheme.activeBorder : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isHighlightedForMerge ? 1.05 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isHighlightedForMerge)
    }

    // MARK: - Chinese Card View (With Pinyin, Cut capability, and Card Box)
    private var chineseCardView: some View {
        let cardContent = VStack(spacing: 2) {
            // Top: Pinyin Text (Clean floating text, NO background frame)
            pinyinBadgeView

            // Bottom: Characters Box with Razor Cutting Overlay
            charactersBoxView
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHighlightedForMerge ? TyperTheme.cardBg : (isDropTarget ? TyperTheme.cardBg : TyperTheme.itemBg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isHighlightedForMerge ? TyperTheme.activeBorder : (isDropTarget ? TyperTheme.activeBorder : TyperTheme.borderFaint),
                    lineWidth: isHighlightedForMerge ? 1.8 : 1
                )
        )
        .scaleEffect(isHighlightedForMerge ? 1.04 : 1.0)
        .shadow(
            color: isHighlightedForMerge ? Color.black.opacity(0.08) : Color.black.opacity(0.02),
            radius: isHighlightedForMerge ? 6 : 2,
            x: 0,
            y: isHighlightedForMerge ? 2 : 1
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isHighlightedForMerge)

        return Group {
            if canBeCut {
                cardContent
            } else {
                cardContent
                    .onDrag {
                        NSItemProvider(object: segment.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], isTargeted: $isDropTarget) { providers in
                        guard let provider = providers.first else { return false }
                        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                            guard let data = data as? Data,
                                  let idString = String(data: data, encoding: .utf8),
                                  let sourceId = UUID(uuidString: idString) else {
                                return
                            }
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                                    self.appState.mergeSegments(sourceId: sourceId, targetId: self.segment.id)
                                }
                            }
                        }
                        return true
                    }
            }
        }
    }

    // MARK: - Pinyin Badge (No background frame, clean floating text)
    private var pinyinBadgeView: some View {
        Button(action: {
            appState.editPinyinText = segment.pinyin
            appState.editingSegment = segment
        }) {
            Text(segment.pinyin)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(TyperTheme.textSecondary)
                .frame(height: 12)
                .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .help("点击修改拼音")
    }

    // MARK: - Characters Box & Razor Cut
    private var charactersBoxView: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segment.raw.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .overlay(
                CustomCursorView(cursor: canBeCut ? CursorManager.shared.scissorCursor : nil)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .leading) {
                if isHovering, let cutX = cutLineX, canBeCut {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0)
                        .offset(x: cutX - 1)
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                guard canBeCut else { return }
                switch phase {
                case .active(let loc):
                    self.isHovering = true
                    calculateCutPosition(mouseX: loc.x, totalWidth: geo.size.width)
                case .ended:
                    self.isHovering = false
                    self.cutLineX = nil
                    self.nearestCutIndex = nil
                }
            }
            .onTapGesture {
                if canBeCut, let cutIdx = nearestCutIndex {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                        appState.splitSegment(id: segment.id, atCharIndex: cutIdx)
                    }
                }
            }
        }
        .frame(minWidth: CGFloat(max(1, segment.raw.count)) * 17)
        .frame(height: 22)
    }

    // Calculate nearest character boundary based on mouse X
    private func calculateCutPosition(mouseX: CGFloat, totalWidth: CGFloat) {
        let count = segment.raw.count
        guard count >= 2 else { return }

        let charWidth = totalWidth / CGFloat(count)
        var bestIndex = 1
        var minDiff = CGFloat.greatestFiniteMagnitude

        for i in 1..<count {
            let boundaryX = CGFloat(i) * charWidth
            let diff = abs(mouseX - boundaryX)
            if diff < minDiff {
                minDiff = diff
                bestIndex = i
            }
        }

        self.nearestCutIndex = bestIndex
        self.cutLineX = CGFloat(bestIndex) * charWidth
    }
}

// MARK: - Merge Gap Connector (Vertically Centered)
public struct MergeConnectorView: View {
    let index: Int
    @Binding var hoveredGapIndex: Int?
    let onMerge: () -> Void

    @State private var isLocallyHovered: Bool = false

    private var isActive: Bool {
        hoveredGapIndex == index
    }

    public var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                onMerge()
            }
        }) {
            ZStack(alignment: .center) {
                // Fixed constant width so hover never causes layout jump
                Color.clear
                    .frame(width: 12, height: 22)

                if isActive {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(TyperTheme.activeNavyButton)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .scaleEffect(isLocallyHovered ? 1.15 : 1.0)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // Invisible placeholder with identical width to keep stable flow without distracting line
                    Color.clear
                        .frame(width: 2, height: 14)
                }
            }
            .frame(width: 12, height: 22)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isLocallyHovered = h
                if h {
                    hoveredGapIndex = index
                } else if hoveredGapIndex == index {
                    hoveredGapIndex = nil
                }
            }
        }
        .help("点击合并两侧词块")
    }
}
