import Foundation
import SwiftUI
import Combine

public struct Preset: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var text: String

    public init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

public enum TypingSpeed: String, CaseIterable, Identifiable {
    case slow = "慢速 (120字/分)"
    case normal = "标准 (240字/分)"
    case fast = "极速 (400字/分)"
    case natural = "自然手感 (微抖动)"

    public var id: String { rawValue }

    public var strokeDelaySeconds: Double {
        switch self {
        case .slow: return 0.12
        case .normal: return 0.05
        case .fast: return 0.025
        case .natural: return 0.045
        }
    }

    public var shortTitle: String {
        switch self {
        case .slow: return "慢速"
        case .normal: return "标准"
        case .fast: return "极速"
        case .natural: return "自然"
        }
    }

    public var speedLabel: String {
        switch self {
        case .slow: return "120字/分"
        case .normal: return "240字/分"
        case .fast: return "400字/分"
        case .natural: return "拟真抖动"
        }
    }

    public var jitterRange: Double {
        switch self {
        case .natural: return 0.02
        default: return 0.0
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Published Properties
    @Published public var presets: [Preset] = []
    @Published public var activePresetId: UUID = UUID()
    @Published public var currentText: String = ""
    @Published public var segments: [WordSegment] = []
    @Published public var customPinyinMap: [String: String] = [:]

    @Published public var speed: TypingSpeed = .normal
    @Published public var countdownDuration: Int = 3
    @Published public var isTyping: Bool = false
    @Published public var countdownRemaining: Int = 0

    // Popover / Sheet editing
    @Published public var editingSegment: WordSegment?
    @Published public var editPinyinText: String = ""
    @Published public var editingPresetId: UUID?
    @Published public var editingPresetName: String = ""

    // Status indicator
    @Published public var statusMessage: String = "就绪"
    @Published public var saveStatus: String = "已保存"

    // Permission tracking
    @Published public var hasAccessibilityPermission: Bool = false

    private var saveCancellable: AnyCancellable?
    private var isUpdatingInternally: Bool = false
    private var activeTypingTask: Task<Void, Never>?

    private let presetsKey = "screen_typer_presets_v1"
    private let customPinyinKey = "screen_typer_custom_pinyin_v1"
    private let activePresetKey = "screen_typer_active_preset_id_v1"

    public init() {
        loadData()
        checkPermissions(prompt: false)
    }

    @discardableResult
    public func checkPermissions(prompt: Bool = false) -> Bool {
        let trusted = PermissionManager.shared.checkAccessibility(prompt: prompt)
        self.hasAccessibilityPermission = trusted
        return trusted
    }

    public func requestAccessibilityPermission() {
        if checkPermissions(prompt: false) {
            return
        }
        PermissionManager.shared.openAccessibilitySettings()
    }

    // MARK: - Persistence
    private func loadData() {
        if let customData = UserDefaults.standard.dictionary(forKey: customPinyinKey) as? [String: String] {
            // Clean up false positives where custom pinyin is identical to system default
            var cleaned: [String: String] = [:]
            for (word, py) in customData {
                let defaultPy = PinyinEngine.shared.convertToPinyin(word)
                let cleanPy = py.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cleanPy != defaultPy.lowercased() {
                    cleaned[word] = cleanPy
                }
            }
            UserDefaults.standard.set(cleaned, forKey: customPinyinKey)
            self.customPinyinMap = cleaned
        } else {
            self.customPinyinMap = [:]
        }

        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data),
           !saved.isEmpty {
            self.presets = saved
        } else {
            self.presets = [
                Preset(name: "默认台词", text: "点一下屏幕，输入0和123，我们一起去天安门广场看升旗！"),
                Preset(name: "问候开场", text: "各位观众朋友大家好，今天为大家演示智能输入。"),
                Preset(name: "功能演示", text: "支持精准剪刀裁切、长词拖拽合并，零失误拟真打字。")
            ]
        }

        if let savedActiveString = UserDefaults.standard.string(forKey: activePresetKey),
           let savedActiveId = UUID(uuidString: savedActiveString),
           presets.contains(where: { $0.id == savedActiveId }) {
            self.activePresetId = savedActiveId
        } else {
            self.activePresetId = presets.first?.id ?? UUID()
        }

        if let current = presets.first(where: { $0.id == activePresetId }) {
            self.currentText = current.text
            self.segments = PinyinEngine.shared.parse(text: current.text, customMap: self.customPinyinMap)
        }
    }

    public func saveData() {
        if let index = presets.firstIndex(where: { $0.id == activePresetId }) {
            presets[index].text = currentText
        }

        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
        UserDefaults.standard.set(activePresetId.uuidString, forKey: activePresetKey)
        UserDefaults.standard.set(customPinyinMap, forKey: customPinyinKey)

        self.saveStatus = "已保存"
    }

    // MARK: - Presets Operations
    public func selectPreset(_ preset: Preset) {
        guard preset.id != activePresetId else { return }
        if let idx = presets.firstIndex(where: { $0.id == activePresetId }) {
            presets[idx].text = currentText
        }
        activePresetId = preset.id
        currentText = preset.text
        rebuildSegments()

        Task(priority: .utility) { @MainActor in
            self.saveData()
        }
    }

    public func addPreset() {
        saveData()
        let count = presets.count + 1
        let newPreset = Preset(name: "台词预设 \(count)", text: "")
        presets.append(newPreset)
        activePresetId = newPreset.id
        currentText = ""
        segments = []
        saveData()
    }

    public func deletePreset(id: UUID) {
        guard presets.count > 1 else { return }
        if let idx = presets.firstIndex(where: { $0.id == id }) {
            presets.remove(at: idx)
            if activePresetId == id {
                activePresetId = presets.first?.id ?? UUID()
                currentText = presets.first?.text ?? ""
                rebuildSegments()
            }
            saveData()
        }
    }

    public func renamePreset(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = presets.firstIndex(where: { $0.id == id }) {
            presets[idx].name = trimmed
            saveData()
        }
    }

    // MARK: - Text & Segment Synchronization
    public func onTextChanged(_ newText: String) {
        guard !isUpdatingInternally else { return }
        currentText = newText
        rebuildSegments()
        saveData()
    }

    public func rebuildSegments() {
        self.segments = PinyinEngine.shared.parse(text: currentText, customMap: customPinyinMap)
    }

    private func syncTextFromSegments() {
        isUpdatingInternally = true
        currentText = segments.map(\.raw).joined()
        isUpdatingInternally = false
        saveData()
    }

    // MARK: - Merge Operations
    public func mergeAdjacentSegments(at index: Int) {
        guard index >= 0 && index < segments.count - 1 else { return }
        let first = segments[index]
        let second = segments[index + 1]

        let mergedRaw = first.raw + second.raw
        let mergedPinyin: String
        let isCustom: Bool

        if let custom = customPinyinMap[mergedRaw] {
            mergedPinyin = custom
            isCustom = true
        } else {
            mergedPinyin = first.pinyin + second.pinyin
            isCustom = first.isCustomized || second.isCustomized
        }

        let mergedSegment = WordSegment(
            raw: mergedRaw,
            pinyin: mergedPinyin,
            isCustomized: isCustom,
            type: first.type == .chinese || second.type == .chinese ? .chinese : first.type
        )

        segments.remove(at: index + 1)
        segments[index] = mergedSegment

        syncTextFromSegments()
    }

    public func mergeSegments(sourceId: UUID, targetId: UUID) {
        guard sourceId != targetId,
              let srcIndex = segments.firstIndex(where: { $0.id == sourceId }),
              let tgtIndex = segments.firstIndex(where: { $0.id == targetId }) else {
            return
        }

        let firstIndex = min(srcIndex, tgtIndex)
        let secondIndex = max(srcIndex, tgtIndex)

        let first = segments[firstIndex]
        let second = segments[secondIndex]

        let mergedRaw = first.raw + second.raw
        let mergedPinyin: String
        let isCustom: Bool

        if let custom = customPinyinMap[mergedRaw] {
            mergedPinyin = custom
            isCustom = true
        } else {
            mergedPinyin = first.pinyin + second.pinyin
            isCustom = first.isCustomized || second.isCustomized
        }

        let mergedSegment = WordSegment(
            raw: mergedRaw,
            pinyin: mergedPinyin,
            isCustomized: isCustom,
            type: first.type == .chinese || second.type == .chinese ? .chinese : first.type
        )

        segments.remove(at: secondIndex)
        segments[firstIndex] = mergedSegment

        syncTextFromSegments()
    }

    // MARK: - Razor Cut
    public func splitSegment(id: UUID, atCharIndex: Int) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let seg = segments[index]
        let raw = seg.raw
        guard atCharIndex > 0 && atCharIndex < raw.count else { return }

        let splitIndex = raw.index(raw.startIndex, offsetBy: atCharIndex)
        let leftRaw = String(raw[..<splitIndex])
        let rightRaw = String(raw[splitIndex...])

        let leftType = PinyinEngine.shared.detectType(leftRaw)
        let rightType = PinyinEngine.shared.detectType(rightRaw)

        let leftPinyin = customPinyinMap[leftRaw] ?? (leftType == .chinese ? PinyinEngine.shared.convertToPinyin(leftRaw) : leftRaw)
        let rightPinyin = customPinyinMap[rightRaw] ?? (rightType == .chinese ? PinyinEngine.shared.convertToPinyin(rightRaw) : rightRaw)

        let leftSeg = WordSegment(
            raw: leftRaw,
            pinyin: leftPinyin,
            isCustomized: customPinyinMap[leftRaw] != nil,
            type: leftType
        )
        let rightSeg = WordSegment(
            raw: rightRaw,
            pinyin: rightPinyin,
            isCustomized: customPinyinMap[rightRaw] != nil,
            type: rightType
        )

        segments.remove(at: index)
        segments.insert(rightSeg, at: index)
        segments.insert(leftSeg, at: index)

        syncTextFromSegments()
    }

    // MARK: - Edit Pinyin
    public func updateSegmentPinyin(segmentId: UUID, newPinyin: String) {
        guard let index = segments.firstIndex(where: { $0.id == segmentId }) else { return }
        let cleanPinyin = newPinyin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanPinyin.isEmpty else { return }

        segments[index].pinyin = cleanPinyin
        segments[index].isCustomized = true

        // Persist override in custom map
        customPinyinMap[segments[index].raw] = cleanPinyin
        saveData()
    }

    // MARK: - Typing Control
    public func toggleTyping() {
        if isTyping {
            stopTyping()
        } else {
            startTyping()
        }
    }

    public func startTyping() {
        guard !isTyping else { return }

        // Check Accessibility Permission
        if !PermissionManager.shared.checkAccessibility(prompt: true) {
            self.hasAccessibilityPermission = false
            PermissionManager.shared.openAccessibilitySettings()
            return
        }
        self.hasAccessibilityPermission = true

        guard !segments.isEmpty else {
            statusMessage = "没有可输入的台词内容"
            return
        }

        isTyping = true

        activeTypingTask = Task { [weak self] in
            guard let self = self else { return }

            if self.countdownDuration > 0 {
                // Hide panel so focus immediately returns to user's target app
                AppDelegate.shared?.panel.orderOut(nil)

                for i in stride(from: self.countdownDuration, through: 1, by: -1) {
                    if Task.isCancelled { break }
                    self.countdownRemaining = i
                    self.statusMessage = "倒计时 \(i) 秒..."
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } else {
                // Hide panel and wait 350ms so target window gains key focus
                AppDelegate.shared?.panel.orderOut(nil)
                try? await Task.sleep(nanoseconds: 350_000_000)
            }

            guard !Task.isCancelled else {
                self.isTyping = false
                self.statusMessage = "已取消"
                return
            }

            self.statusMessage = "正在模拟原生击键输入..."
            await KeyDriver.shared.executeTyping(segments: self.segments, speed: self.speed)

            self.isTyping = false
            self.countdownRemaining = 0
            self.statusMessage = "输入完成 ✅"
            NSSound.beep()
        }
    }

    public func stopTyping() {
        activeTypingTask?.cancel()
        activeTypingTask = nil
        KeyDriver.shared.cancel()
        isTyping = false
        countdownRemaining = 0
        statusMessage = "已停止输入"
    }
}
