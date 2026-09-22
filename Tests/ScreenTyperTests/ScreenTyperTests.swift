import Testing
@testable import ScreenTyper

@Test func testLexiconSegmentation() async throws {
    let engine = PinyinEngine.shared
    let text = "支持精准剪刀裁切、长词拖拽合并，零失误拟真打字。"
    let segments = engine.parse(text: text)
    let words = segments.map(\.raw)

    #expect(words.contains("精准"))
    #expect(words.contains("裁切"))
    #expect(words.contains("长词"))
    #expect(words.contains("零失误"))
    #expect(words.contains("拟真"))
    #expect(words.contains("剪刀"))
    #expect(words.contains("拖拽"))
    #expect(words.contains("合并"))
    #expect(words.contains("打字"))
}

@Test func testNoWeirdCombinations() async throws {
    let engine = PinyinEngine.shared
    let s1 = engine.parse(text: "我一个人在家看书").map(\.raw)
    #expect(!s1.contains("我一"))

    let s2 = engine.parse(text: "我把书借给他了").map(\.raw)
    #expect(!s2.contains("书借给"))

    let s3 = engine.parse(text: "机器学习与深度学习").map(\.raw)
    #expect(!s3.contains("与深度"))
}
