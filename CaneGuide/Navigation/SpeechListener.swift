import AVFoundation
import Speech

/// Listens for one spoken request with Apple's speech recognition and returns
/// the transcript once the person pauses.
final class SpeechListener {
    private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var transcript = ""
    private var completion: ((String?) -> Void)?

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { done(status == .authorized && granted) }
            }
        }
    }

    /// Call on the main thread. `completion` gets the transcript, or nil if nothing was heard.
    func listen(completion: @escaping (String?) -> Void) {
        guard !isListening, let recognizer, recognizer.isAvailable else {
            completion(nil)
            return
        }
        self.completion = completion
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        isListening = true
        do {
            try audioEngine.start()
        } catch {
            finish()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isListening else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    result.isFinal ? self.finish() : self.restartSilenceTimer(after: 1.5)
                } else if error != nil {
                    self.finish()
                }
            }
        }
        // Give up if nothing is said at all.
        restartSilenceTimer(after: 6)
    }

    /// Stops listening and delivers whatever was heard so far.
    func finish() {
        guard isListening else { return }
        isListening = false
        silenceTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = completion
        completion = nil
        done?(text.isEmpty ? nil : text)
    }

    private func restartSilenceTimer(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.finish()
        }
    }
}
