import Foundation

/// Text to speech through the ElevenLabs API. Only used for route directions;
/// obstacle warnings never wait on the network.
actor ElevenLabsVoice {
    private let apiKey: String
    private let voiceID: String
    private var cache: [String: Data] = [:]

    init?(apiKey: String, voiceID: String) {
        guard !apiKey.isEmpty else { return nil }
        self.apiKey = apiKey
        self.voiceID = voiceID
    }

    /// MP3 audio for `text`. Throws on network or API errors so the caller can fall back.
    func audio(for text: String) async throws -> Data {
        if let cached = cache[text] { return cached }

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_flash_v2_5",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        cache[text] = data
        return data
    }
}
