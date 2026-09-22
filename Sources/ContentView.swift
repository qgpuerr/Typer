import SwiftUI
import Cocoa
import Carbon

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 16

    struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        guard !subviews.isEmpty else { return [] }
        let maxWidth = proposal.width ?? 500
        var rows: [Row] = [Row()]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let currentWidth = rows.last?.width ?? 0

            if currentWidth + size.width > maxWidth && !rows.last!.items.isEmpty {
                var newRow = Row()
                newRow.items.append(RowItem(subview: subview, size: size))
                newRow.width = size.width
                newRow.height = size.height
                rows.append(newRow)
            } else {
                let addWidth = rows.last!.items.isEmpty ? size.width : (size.width + horizontalSpacing)
                rows[rows.count - 1].items.append(RowItem(subview: subview, size: size))
                rows[rows.count - 1].width += addWidth
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows.filter { !$0.items.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else {
            return CGSize(width: proposal.width ?? 500, height: 40)
        }
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let maxWidth = proposal.width ?? 500
        return CGSize(width: maxWidth, height: max(totalHeight, 40))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var currentY = bounds.minY

        for row in rows {
            var currentX = bounds.minX
            for item in row.items {
                // Bottom alignment within the row so text baselines match Chinese characters
                let offsetY = row.height - item.size.height
                item.subview.place(at: CGPoint(x: currentX, y: currentY + offsetY), proposal: .unspecified)
                currentX += item.size.width + horizontalSpacing
            }
            currentY += row.height + verticalSpacing
        }
    }
}

public struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var showRenameModal: Bool = false
    @State private var renameTargetId: UUID? = nil
    @State private var renameText: String = ""
    @State private var hoveredGapIndex: Int? = nil
    @State private var showHelpPopover: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Segmented Tabs with top-right permission indicator
                        tabsBar
                            .padding(.top, 14)

                        // Script Text Area (Floating card with diffused shadow)
                        scriptEditorSection

                        // Word Segmentation Area (Floating card)
                        segmentPlanningSection

                        // Settings: Input Method, Shortcut, Speed & Countdown
                        settingsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // Footer Control Bar
                footerControlBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(TyperTheme.windowBg)
                    .overlay(
                        Rectangle()
                            .fill(TyperTheme.borderFaint)
                            .frame(height: 1),
                        alignment: .top
                    )
            }

            // Centered Modal Dialog for Renaming Preset (Matching Design)
            if showRenameModal, let targetId = renameTargetId {
                renamePresetModal(targetId: targetId)
            }
        }
        .frame(minWidth: 520, idealWidth: 580, maxWidth: .infinity, minHeight: 560, idealHeight: 650, maxHeight: .infinity)
        .background(TyperTheme.windowBg.ignoresSafeArea())
        .onAppear {
            appState.checkPermissions(prompt: false)
        }
    }

    // MARK: - Tabs Bar
    private var tabsBar: some View {
        HStack(alignment: .center, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(appState.presets) { preset in
                        let isActive = preset.id == appState.activePresetId

                        Text(preset.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                            .foregroundColor(isActive ? TyperTheme.textPrimary : TyperTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isActive ? TyperTheme.cardBg : TyperTheme.itemBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isActive ? TyperTheme.activeBorder : Color.clear, lineWidth: 1.5)
                            )
                            .shadow(color: isActive ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectPreset(preset)
                            }
                            .contextMenu {
                                Button("重命名") {
                                    renameTargetId = preset.id
                                    renameText = preset.name
                                    showRenameModal = true
                                }
                                if appState.presets.count > 1 {
                                    Button("删除预设", role: .destructive) {
                                        appState.deletePreset(id: preset.id)
                                    }
                                }
                            }
                    }

                    // Add new preset button (Icon only)
                    Button(action: {
                        appState.addPreset()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TyperTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(TyperTheme.itemBg.opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("新建台词预设")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }

            Spacer(minLength: 6)

            // Top-right compact permission button (Only shown when permission is missing)
            if !appState.hasAccessibilityPermission {
                Button(action: {
                    if !appState.checkPermissions(prompt: false) {
                        appState.requestAccessibilityPermission()
                    }
                }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange.opacity(0.9))
                            .frame(width: 6, height: 6)

                        Text("权限未开启")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TyperTheme.textSecondary)

                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(TyperTheme.activeBorder)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(TyperTheme.cardBg)
                            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                    )
                    .overlay(
                        Capsule()
                            .stroke(TyperTheme.borderFaint, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("点击前往系统设置开启辅助功能模拟按键权限")
                .fixedSize()
            }
        }
    }

    // MARK: - Script Editor Section (Floating Card matching Reference Design)
    private var scriptEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("台词内容")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TyperTheme.textSecondary)

            ZStack(alignment: .topLeading) {
                if appState.currentText.isEmpty {
                    Text("在此输入或粘贴录屏台词内容...")
                        .font(.system(size: 14))
                        .foregroundColor(TyperTheme.textTertiary)
                        .padding(.top, 10)
                        .padding(.leading, 15)
                }

                TextEditor(text: Binding(
                    get: { appState.currentText },
                    set: { appState.onTextChanged($0) }
                ))
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundColor(TyperTheme.textPrimary)
                .frame(minHeight: 72, maxHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                    .fill(TyperTheme.cardBg)
                    .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
                    .shadow(color: Color.black.opacity(0.015), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                    .stroke(TyperTheme.borderFaint, lineWidth: 1)
            )
        }
    }

    // MARK: - Word Segmentation Planning (Floating Card)
    private var segmentPlanningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text("拆分预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TyperTheme.textSecondary)

                // Circular question mark button with popover
                Button(action: {
                    showHelpPopover.toggle()
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(showHelpPopover ? TyperTheme.activeBorder : TyperTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHelpPopover, arrowEdge: .bottom) {
                    helpPopoverView
                }

                Spacer()
            }

            Group {
                if appState.segments.isEmpty {
                    HStack {
                        Spacer()
                        Text("暂无台词分词，请在上方输入台词")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(TyperTheme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                } else {
                    FlowLayout(horizontalSpacing: 4, verticalSpacing: 16) {
                        ForEach(Array(appState.segments.enumerated()), id: \.element.id) { index, segment in
                            let isLeft = (hoveredGapIndex == index)
                            let isRight = (hoveredGapIndex == index - 1)
                            let isHighlighted = (isLeft || isRight) && segment.type == .chinese

                            WordCardView(
                                appState: appState,
                                segment: segment,
                                isHighlightedForMerge: isHighlighted
                            )

                            // ONLY show merge connector if BOTH this segment and the next segment are Chinese words
                            if index < appState.segments.count - 1 {
                                let nextSegment = appState.segments[index + 1]
                                if segment.type == .chinese && nextSegment.type == .chinese {
                                    MergeConnectorView(
                                        index: index,
                                        hoveredGapIndex: $hoveredGapIndex,
                                        onMerge: {
                                            appState.mergeAdjacentSegments(at: index)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                    .fill(TyperTheme.cardBg)
                    .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
                    .shadow(color: Color.black.opacity(0.015), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                    .stroke(TyperTheme.borderFaint, lineWidth: 1)
            )
        }
    }

    // MARK: - Help Popover View (Redesigned with Typer Theme)
    private var helpPopoverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("快捷操作")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TyperTheme.textPrimary)

                Spacer()

                Button(action: { showHelpPopover = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(TyperTheme.textTertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(TyperTheme.itemBg)
                        )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(TyperTheme.borderFaint)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                // Split Row
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(TyperTheme.itemBg)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("拆分词块")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TyperTheme.textPrimary)
                        Text("鼠标移至字缝处，出现竖线与剪刀后点击拆分。")
                            .font(.system(size: 11))
                            .foregroundColor(TyperTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Merge Row
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(TyperTheme.itemBg)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("合并词块")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TyperTheme.textPrimary)
                        Text("拖拽一个词块到另一个词块上，即可无缝合并。")
                            .font(.system(size: 11))
                            .foregroundColor(TyperTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Pinyin Row
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(TyperTheme.itemBg)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("修改拼音")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TyperTheme.textPrimary)
                        Text("直接点击词块上方的拼音文字，弹窗快速更正。")
                            .font(.system(size: 11))
                            .foregroundColor(TyperTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Settings Section (Dropdown Menus & Shortcut Recorder)
    private var settingsSection: some View {
        VStack(spacing: 0) {
            // Shortcut Recording Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("快捷键")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                    Text("点击即可录制新按键")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(TyperTheme.textSecondary)
                }

                Spacer()

                ShortcutRecorderView(appState: appState)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            // Divider line
            Rectangle()
                .fill(TyperTheme.borderFaint)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Speed Dropdown Row
            HStack(alignment: .center) {
                Text("速度")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TyperTheme.textPrimary)

                Spacer()

                Menu {
                    ForEach(TypingSpeed.allCases) { sp in
                        Button(action: {
                            appState.speed = sp
                        }) {
                            HStack {
                                Text("\(sp.shortTitle) · \(sp.speedLabel)")
                                if appState.speed == sp {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(appState.speed.shortTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(TyperTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TyperTheme.itemBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TyperTheme.borderFaint, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Divider line
            Rectangle()
                .fill(TyperTheme.borderFaint)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Countdown Dropdown Row
            HStack(alignment: .center) {
                Text("倒计时")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TyperTheme.textPrimary)

                Spacer()

                Menu {
                    Button(action: { appState.countdownDuration = 0 }) {
                        HStack {
                            Text("无倒计时")
                            if appState.countdownDuration == 0 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { appState.countdownDuration = 3 }) {
                        HStack {
                            Text("3 秒")
                            if appState.countdownDuration == 3 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { appState.countdownDuration = 5 }) {
                        HStack {
                            Text("5 秒")
                            if appState.countdownDuration == 5 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        let text = appState.countdownDuration == 0 ? "无倒计时" : "\(appState.countdownDuration) 秒"
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(TyperTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TyperTheme.itemBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TyperTheme.borderFaint, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Divider line
            Rectangle()
                .fill(TyperTheme.borderFaint)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Floating IME Theme Color Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("浮窗配色")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                    Text("候选词高亮色彩")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(TyperTheme.textSecondary)
                }

                Spacer()

                IMEThemeColorPickerView(appState: appState)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                .fill(TyperTheme.cardBg)
                .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
                .shadow(color: Color.black.opacity(0.015), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TyperTheme.radiusCard, style: .continuous)
                .stroke(TyperTheme.borderFaint, lineWidth: 1)
        )
    }

    // MARK: - Footer Control Bar
    private var footerControlBar: some View {
        HStack(alignment: .center) {
            // Status message
            if appState.isTyping {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.88, green: 0.28, blue: 0.28))
                        .frame(width: 6, height: 6)
                    Text(appState.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TyperTheme.textPrimary)
                }
            }

            Spacer()

            // Main Action Button (Text only, Capsule pill, deep slate navy)
            Button(action: {
                appState.toggleTyping()
            }) {
                let sc = appState.hotKeyOption.display
                Text(appState.isTyping ? "停止 (\(sc))" : "开始输入 (\(sc))")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(appState.isTyping ? Color(red: 0.88, green: 0.28, blue: 0.28) : TyperTheme.activeNavyButton)
                    )
                    .foregroundColor(.white)
                    .shadow(
                        color: (appState.isTyping ? Color.red : TyperTheme.activeNavyButton).opacity(0.28),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            }
            .buttonStyle(.plain)
        }
    }



    // MARK: - Centered Modal Dialog for Renaming Preset (Matching Pinyin Edit Modal)
    private func renamePresetModal(targetId: UUID) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    showRenameModal = false
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("重命名预设")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TyperTheme.textPrimary)
                    Spacer()
                    Button(action: {
                        showRenameModal = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TyperTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Text("当前预设：")
                        .font(.system(size: 13))
                        .foregroundColor(TyperTheme.textSecondary)
                    if let preset = appState.presets.first(where: { $0.id == targetId }) {
                        Text("「\(preset.name)」")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TyperTheme.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("预设名称")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.textSecondary)

                    TextField("输入预设名称，如: 台词1", text: $renameText)
                        .font(.system(size: 14, weight: .medium))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(TyperTheme.itemBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(TyperTheme.borderSubtle, lineWidth: 1)
                        )
                        .onSubmit {
                            confirmRename(targetId: targetId)
                        }
                }

                HStack(spacing: 10) {
                    Spacer()

                    Button(action: {
                        showRenameModal = false
                    }) {
                        Text("取消")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TyperTheme.textSecondary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(TyperTheme.itemBg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(TyperTheme.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        confirmRename(targetId: targetId)
                    }) {
                        Text("保存")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(TyperTheme.activeNavyButton)
                            )
                            .shadow(color: TyperTheme.activeNavyButton.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TyperTheme.cardBg)
            )
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TyperTheme.borderSubtle, lineWidth: 1)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func confirmRename(targetId: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appState.renamePreset(id: targetId, newName: trimmed)
        }
        showRenameModal = false
    }
}

// MARK: - Interactive Shortcut Recorder View
struct ShortcutRecorderView: View {
    @ObservedObject var appState: AppState
    @State private var isRecording: Bool = false
    @State private var localMonitor: Any? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.50, blue: 0.95))
                            .frame(width: 6, height: 6)
                        Text("请按下快捷键...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.15, green: 0.35, blue: 0.85))
                    } else {
                        Text(appState.hotKeyOption.display)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.blue.opacity(0.08) : TyperTheme.itemBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isRecording ? Color.blue.opacity(0.5) : TyperTheme.borderFaint, lineWidth: isRecording ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "请在键盘上按下你想要的快捷键组合，按 Esc 取消" : "点击即可直接按下键盘录制快捷键")

            // Reset to default button (shown when custom)
            if appState.hotKeyOption != .defaultOption && !isRecording {
                Button(action: {
                    appState.setHotKeyOption(.defaultOption)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TyperTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(TyperTheme.itemBg)
                        )
                }
                .buttonStyle(.plain)
                .help("恢复默认快捷键 (⌥T)")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Handle Esc key to cancel
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            // Parse modifiers and key
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let isFunctionKey = (event.keyCode >= 96 && event.keyCode <= 101) || event.keyCode == 103 || (event.keyCode >= 109 && event.keyCode <= 122)

            // Ignore bare modifier key presses or plain letters without modifiers
            if flags.isEmpty && !isFunctionKey {
                return nil
            }

            var display = ""
            var carbonMods: UInt32 = 0
            if flags.contains(.control) {
                display += "⌃"
                carbonMods |= UInt32(controlKey)
            }
            if flags.contains(.option) {
                display += "⌥"
                carbonMods |= UInt32(optionKey)
            }
            if flags.contains(.shift) {
                display += "⇧"
                carbonMods |= UInt32(shiftKey)
            }
            if flags.contains(.command) {
                display += "⌘"
                carbonMods |= UInt32(cmdKey)
            }

            let keyName: String
            switch Int(event.keyCode) {
            case kVK_Space: keyName = "Space"
            case kVK_Return: keyName = "↩"
            case kVK_Tab: keyName = "⇥"
            case kVK_F1: keyName = "F1"
            case kVK_F2: keyName = "F2"
            case kVK_F3: keyName = "F3"
            case kVK_F4: keyName = "F4"
            case kVK_F5: keyName = "F5"
            case kVK_F6: keyName = "F6"
            case kVK_F7: keyName = "F7"
            case kVK_F8: keyName = "F8"
            case kVK_F9: keyName = "F9"
            case kVK_F10: keyName = "F10"
            case kVK_F11: keyName = "F11"
            case kVK_F12: keyName = "F12"
            default:
                keyName = event.charactersIgnoringModifiers?.uppercased() ?? "Key"
            }

            display += keyName
            let title = "\(display) (\(display))"
            let newOption = HotKeyOption(keyCode: UInt32(event.keyCode), modifiers: carbonMods, display: display, title: title)

            DispatchQueue.main.async {
                self.appState.setHotKeyOption(newOption)
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
    }
}

// MARK: - IME Floating Window Theme Color Picker View
struct IMEThemeColorPickerView: View {
    @ObservedObject var appState: AppState

    private let presets: [(hex: String, name: String)] = [
        ("#263D59", "藏青"),
        ("#1E1E24", "暗黑"),
        ("#007AFF", "科技蓝"),
        ("#E65D24", "珊瑚橙")
    ]

    var body: some View {
        HStack(spacing: 8) {
            // 4 Built-in Preset Color Buttons
            HStack(spacing: 6) {
                ForEach(presets, id: \.hex) { preset in
                    let isSelected = appState.imeThemeColorHex.uppercased() == preset.hex.uppercased()

                    Button(action: {
                        appState.setIMEThemeColor(preset.hex)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 18, height: 18)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(isSelected ? TyperTheme.activeBorder : Color.black.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("预设色彩：\(preset.name)")
                }
            }

            // Subtle vertical separator
            Rectangle()
                .fill(TyperTheme.borderFaint)
                .frame(width: 1, height: 16)

            // Custom Hex Input with Live Color Swatch
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(appState.imeThemeColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                    )

                Text("#")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TyperTheme.textTertiary)

                TextField("263D59", text: Binding(
                    get: {
                        appState.imeThemeColorHex.replacingOccurrences(of: "#", with: "").uppercased()
                    },
                    set: { newVal in
                        let filtered = String(newVal.filter { $0.isHexDigit }.prefix(6)).uppercased()
                        appState.imeThemeColorHex = "#" + filtered
                        if filtered.count == 6 || filtered.count == 3 {
                            appState.saveData()
                        }
                    }
                ))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(TyperTheme.textPrimary)
                .frame(width: 50)
                .textFieldStyle(.plain)
                .onSubmit {
                    appState.setIMEThemeColor(appState.imeThemeColorHex)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TyperTheme.itemBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TyperTheme.borderFaint, lineWidth: 1)
            )

            // Native Eyedropper Button
            Button(action: {
                NSColorSampler().show { selectedColor in
                    guard let selectedColor = selectedColor else { return }
                    DispatchQueue.main.async {
                        appState.setIMEThemeColor(selectedColor.hexString)
                    }
                }
            }) {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TyperTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TyperTheme.itemBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TyperTheme.borderFaint, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("屏幕吸色（点击即可在屏幕任意位置吸取颜色）")
        }
    }
}

