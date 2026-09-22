import SwiftUI
import Cocoa

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
                // Permission Banner (Only shown if unpermitted)
                permissionBanner

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Segmented Tabs
                        tabsBar
                            .padding(.top, appState.hasAccessibilityPermission ? 12 : 6)

                        // Script Text Area (Floating card with diffused shadow)
                        scriptEditorSection

                        // Word Segmentation Area (Floating card)
                        segmentPlanningSection

                        // Settings: Speed & Countdown (Dropdown Menus)
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

            // Centered Modal Dialog for Editing Pinyin
            if let segment = appState.editingSegment {
                pinyinEditModal(segment: segment)
            }

            // Centered Modal Dialog for Renaming Preset (Matching Pinyin Modal Design)
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

    // MARK: - Permission Banner
    @ViewBuilder
    private var permissionBanner: some View {
        if !appState.hasAccessibilityPermission {
            Button(action: {
                if !appState.checkPermissions(prompt: false) {
                    appState.requestAccessibilityPermission()
                }
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 6, height: 6)

                    Text("模拟按键权限未开启")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.textSecondary)

                    Spacer()

                    Text("去系统设置开启")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.activeBorder)

                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TyperTheme.activeBorder)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TyperTheme.cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TyperTheme.borderFaint, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .help("macOS 将模拟击键归入「系统设置 -> 辅助功能」。若已开启点击可立即刷新。")
        }
    }

    // MARK: - Tabs Bar
    private var tabsBar: some View {
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

    // MARK: - Settings Section (Dropdown Menus)
    private var settingsSection: some View {
        VStack(spacing: 0) {
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
                        Text("\(appState.speed.shortTitle) (\(appState.speed.speedLabel))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TyperTheme.textPrimary)

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
                            .foregroundColor(TyperTheme.textPrimary)

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
                Text(appState.isTyping ? "停止" : "开始输入")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 24)
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

    // MARK: - Centered Modal Dialog for Editing Pinyin
    private func pinyinEditModal(segment: WordSegment) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.editingSegment = nil
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("修改拼音")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TyperTheme.textPrimary)
                    Spacer()
                    Button(action: {
                        appState.editingSegment = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TyperTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Text("当前词块：")
                        .font(.system(size: 13))
                        .foregroundColor(TyperTheme.textSecondary)
                    Text("「\(segment.raw)」")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TyperTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("拼音设定")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TyperTheme.textSecondary)

                    TextField("输入拼音，如: dian", text: $appState.editPinyinText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
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
                            confirmPinyinEdit(segment)
                        }
                }

                HStack(spacing: 10) {
                    Button(action: {
                        let def = PinyinEngine.shared.convertToPinyin(segment.raw)
                        appState.editPinyinText = def
                    }) {
                        Text("恢复默认")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TyperTheme.textSecondary)
                            .padding(.horizontal, 13)
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

                    Spacer()

                    Button(action: {
                        appState.editingSegment = nil
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
                        confirmPinyinEdit(segment)
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

    private func confirmPinyinEdit(_ segment: WordSegment) {
        appState.updateSegmentPinyin(segmentId: segment.id, newPinyin: appState.editPinyinText)
        appState.editingSegment = nil
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
