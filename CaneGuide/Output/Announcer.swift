import AVFoundation

/// Speaks obstacle warnings and route directions.
///
/// Warnings use the on-device voice: instant, offline, and they cut off anything else.
/// Directions use ElevenLabs when a key is configured, wait for warnings to finish,
/// and fall back to the on-device voice if the network call fails.
final class Announcer {
    private let synthesizer = AVSpeechSynthesizer()
    private let cloudVoice: ElevenLabsVoice?
    private var player: AVAudioPlayer?
    private var directionRequest = 0
    private var lastWarning = Date.distantPast

    init(cloudVoice: ElevenLabsVoice?) {
        self.cloudVoice = cloudVoice
        let session = AVAudioSession.sharedInstance()
        // Play and record, so the microphone can listen for spoken requests between announcements.
        try? session.setCategory(.playAndRecord, mode: .default,
                                 options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)
    }

    func warn(_ text: String, interrupt: Bool) {
        if interrupt {
            player?.stop()
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakLocally(text, rate: 0.55)
        lastWarning = Date()
    }

    /// Silences everything so the microphone doesn't hear the app talking.
    func hush() {
        directionRequest += 1
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func direct(_ text: String) {
        directionRequest += 1
        let request = directionRequest
        guard let cloudVoice else {
            whenQuiet(request) { self.speakLocally(text, rate: AVSpeechUtteranceDefaultSpeechRate) }
            return
        }
        Task {
            let audio = try? await cloudVoice.audio(for: text)
            DispatchQueue.main.async {
                self.whenQuiet(request) {
                    if let audio, let player = try? AVAudioPlayer(data: audio) {
                        self.player = player
                        player.play()
                    } else {
                        self.speakLocally(text, rate: AVSpeechUtteranceDefaultSpeechRate)
                    }
                }
            }
        }
    }

    /// Runs `play` once nothing is being said, unless a newer direction replaced this one.
    private func whenQuiet(_ request: Int, _ play: @escaping () -> Void) {
        guard request == directionRequest else { return }
        let busy = synthesizer.isSpeaking || (player?.isPlaying ?? false)
            || Date().timeIntervalSince(lastWarning) < 1
        guard busy else { play(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.whenQuiet(request, play)
        }
    }

    private func speakLocally(_ text: String, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = Self.bestVoice
        synthesizer.speak(utterance)
    }

    /// The highest-quality voice installed for the phone's language. Enhanced and Premium voices
    /// sound far more natural; download one in Settings → Accessibility → Spoken Content → Voices.
    private static let bestVoice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(String(language.prefix(2))) && $0.quality != .default
        }
        // Prefer quality, then an exact regional match (en-US over en-GB for a US phone).
        let best = candidates.max { a, b in
            (a.quality.rawValue, a.language == language ? 1 : 0) < (b.quality.rawValue, b.language == language ? 1 : 0)
        }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }()
}
