import AVFoundation
import Observation

@MainActor @Observable final class PhraseSpeechPlayer: NSObject {
    private(set) var playingPhraseID: String?
    var errorMessage: String?
    private let synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?

    init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ phrase: Phrase) {
        if playingPhraseID == phrase.id {
            stop()
            return
        }
        stop()
        errorMessage = nil
        let speech = TripConfig.current.speech
        guard let voice = AVSpeechSynthesisVoice(language: speech.language) else {
            errorMessage = "暂时没有可用的\(speech.label)语音，请在系统设置中检查语音资源。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
        } catch {
            errorMessage = "暂时无法播放语音，请稍后再试。"
            return
        }
        let utterance = AVSpeechUtterance(string: phrase.local)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance
        playingPhraseID = phrase.id
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        playingPhraseID = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finished(_ id: ObjectIdentifier) {
        guard let currentUtterance, ObjectIdentifier(currentUtterance) == id else { return }
        self.currentUtterance = nil
        playingPhraseID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension PhraseSpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
}
