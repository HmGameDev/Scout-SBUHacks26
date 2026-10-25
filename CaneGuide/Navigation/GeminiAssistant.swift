import Foundation

/// Turns a spoken request ("take me to the library on campus") into a place to
/// search for in Apple Maps, plus a short sentence to say back.
actor GeminiAssistant {
    struct Answer: Decodable {
        /// Apple Maps search text; empty when the request isn't about going somewhere.
        var destination: String
        var reply: String
    }

    private let apiKey: String
    private let model: String

    init?(apiKey: String, model: String) {
        guard !apiKey.isEmpty else { return nil }
        self.apiKey = apiKey
        self.model = model
    }

    func interpret(_ spoken: String) async throws -> Answer {
        let instructions = """
        You help a blind pedestrian who is walking with a white cane. Read what they said and reply with JSON.
        destination: a short search query for Apple Maps naming the place they want to walk to \
        (for example "Stony Brook University Library" or "coffee shop"). Use an empty string if they \
        are not asking to go somewhere.
        reply: one short, friendly sentence to speak aloud, such as "Finding a walking route to the library." \
        If they asked something else, answer it in one short sentence.
        """
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": [["text": spoken]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "destination": ["type": "STRING"],
                        "reply": ["type": "STRING"],
                    ],
                    "required": ["destination", "reply"],
                ],
            ],
        ]

        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct Response: Decodable {
            struct Candidate: Decodable { var content: Content }
            struct Content: Decodable { var parts: [Part] }
            struct Part: Decodable { var text: String? }
            var candidates: [Candidate]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let json = decoded.candidates.first?.content.parts.compactMap(\.text).joined(),
              let jsonData = json.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        return try JSONDecoder().decode(Answer.self, from: jsonData)
    }
}
