struct ChatPayload<RF: Encodable>: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let stream: Bool
    let response_format: RF?
    init(
        model: String,
        messages: [ChatMessage],
        temperature: Double,
        stream: Bool,
        response_format: RF? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
        self.response_format = response_format
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String?
        }
        let index: Int
        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
    let id: String
    let choices: [Choice]
}
