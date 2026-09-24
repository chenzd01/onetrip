import AVFoundation
import XCTest
@testable import TripJournal

@MainActor final class PhraseSpeechPlayerTests: XCTestCase {
    private final class RecordingSynthesizer: AVSpeechSynthesizer {
        var utterances: [AVSpeechUtterance] = []
        var stops = 0
        override func speak(_ utterance: AVSpeechUtterance) { utterances.append(utterance) }
        override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { stops += 1; return true }
    }

    func testRowTapSpeaksOnlyLocalTextAndSecondTapStops() {
        let synth = RecordingSynthesizer()
        let player = PhraseSpeechPlayer(synthesizer: synth)
        defer { player.stop() }
        let phrase = Phrase(id: "basics-0", native: "请慢一点", local: "Slower, please.", note: "备注不朗读")
        player.toggle(phrase)
        XCTAssertNil(player.errorMessage)
        XCTAssertEqual(player.playingPhraseID, phrase.id)
        XCTAssertEqual(synth.utterances.map(\.speechString), [phrase.local])
        XCTAssertEqual(synth.utterances.first?.voice?.language, TripConfig.current.speech.language)
        player.toggle(phrase)
        XCTAssertNil(player.playingPhraseID)
        XCTAssertEqual(synth.utterances.count, 1)
    }

    func testSwitchIgnoresLateCancellationAndCompletionOfPreviousPhrase() async throws {
        let synth = RecordingSynthesizer()
        let player = PhraseSpeechPlayer(synthesizer: synth)
        defer { player.stop() }
        player.toggle(.init(id: "a-0", native: "第一句", local: "First phrase."))
        let old = try XCTUnwrap(synth.utterances.last)
        player.toggle(.init(id: "a-1", native: "第二句", local: "Second phrase."))
        let current = try XCTUnwrap(synth.utterances.last)
        player.speechSynthesizer(synth, didCancel: old)
        player.speechSynthesizer(synth, didFinish: old)
        await Task.yield()
        XCTAssertEqual(player.playingPhraseID, "a-1")
        XCTAssertEqual(synth.utterances.count, 2)
        XCTAssertGreaterThanOrEqual(synth.stops, 2)
        player.speechSynthesizer(synth, didFinish: current)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(player.playingPhraseID)
    }

    func testPhrasebookDecodesStableIDsFromContent() throws {
        let raw = Data(#"[{"id":"food","title":"餐厅","items":[{"native":"一位","local":"One, please."},{"native":"买单","local":"The bill, please.","note":"示例"}]}]"#.utf8)
        let sections = try JSONDecoder().decode([PhraseSection].self, from: raw)
        XCTAssertEqual(sections[0].items.map(\.id), ["food-0", "food-1"])
        XCTAssertEqual(sections[0].items[1].note, "示例")
        XCTAssertFalse(try ContentCatalog.load().phrases.isEmpty)
    }

    func testStopAndReplaySamePhraseIgnoresOldCallback() async throws {
        let synth = RecordingSynthesizer()
        let player = PhraseSpeechPlayer(synthesizer: synth)
        defer { player.stop() }
        let phrase = Phrase(id: "a-2", native: "请再说一遍", local: "Could you say that again?")
        player.toggle(phrase)
        let old = try XCTUnwrap(synth.utterances.last)
        player.stop()
        XCTAssertNil(player.playingPhraseID)
        player.toggle(phrase)
        player.speechSynthesizer(synth, didCancel: old)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(player.playingPhraseID, phrase.id)
        player.speechSynthesizer(synth, didCancel: try XCTUnwrap(synth.utterances.last))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(player.playingPhraseID)
    }
}
