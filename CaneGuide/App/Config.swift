enum Config {
    /// Gemini API key from https://aistudio.google.com/apikey. It interprets spoken requests
    /// ("take me to the library"). Leave empty to send what was heard straight to Apple Maps search.
    /// Don't commit a real key to a public repo.
    static let geminiAPIKey = ""
    /// "gemini-flash-latest" always points at Google's current Flash model.
    static let geminiModel = "gemini-flash-latest"

    /// Paste an ElevenLabs API key here to use its voice for route directions.
    /// Leave it empty to use the built-in iOS voice. Don't commit a real key to a public repo.
    static let elevenLabsAPIKey = ""
    /// ElevenLabs premade voice "Rachel". Any voice ID from your ElevenLabs account works.
    static let elevenLabsVoiceID = "21m00Tcm4TlvDq8ikWAM"
}
