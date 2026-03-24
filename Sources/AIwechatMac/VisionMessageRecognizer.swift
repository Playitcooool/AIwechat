import Foundation

struct RecognizedMessages: Codable {
    let their: [String]  // 对方消息
    let mine: [String]  // 我的消息
}

struct VisionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [VisionContent]
    }

    struct VisionContent: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?
    }

    struct ImageURL: Encodable {
        let url: String
    }

    let model: String
    let messages: [Message]
}

struct VisionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    let choices: [Choice]
}

enum VisionRecognizerError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case parseFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .requestFailed(let msg): return "请求失败: \(msg)"
        case .parseFailed: return "解析响应失败"
        case .apiError(let msg): return "API 错误: \(msg)"
        }
    }
}

actor VisionMessageRecognizer {
    private let baseURL: String
    private let model: String

    init(baseURL: String = AppConfig.visionBaseURL, model: String = AppConfig.visionModel) {
        self.baseURL = baseURL
        self.model = model
    }

    private let systemPrompt = """
你是一个微信聊天消息识别助手。请分析这张微信聊天截图，识别并提取所有消息。

要求：
1. 区分"对方消息"（对方发送的，通常在左侧）和"我的消息"（我发送的，通常在右侧）
2. 按时间顺序返回（从上到下）
3. 只提取实际的消息内容，不要包含时间戳、头像等信息
4. 如果消息有明显的"我:"或"对方:"前缀，忽略这些前缀
5. 返回标准 JSON 格式，不要包含 markdown 代码块

输出格式：
{"their":["对方消息1","对方消息2"],"mine":["我的消息1","我的消息2"]}

只输出 JSON，不要其他内容。
"""

    func recognize(imageData: Data) async throws -> RecognizedMessages {
        let base64Image = ScreenCapture.imageToBase64(imageData)
        let imageURL = "data:image/png;base64,\(base64Image)"
        return try await recognizeFromURL(imageURL)
    }

    func recognizeFromBase64(base64String: String) async throws -> RecognizedMessages {
        let imageURL = "data:image/png;base64,\(base64String)"
        return try await recognizeFromURL(imageURL)
    }

    private func recognizeFromURL(_ imageURL: String) async throws -> RecognizedMessages {
        let request = VisionRequest(
            model: model,
            messages: [
                VisionRequest.Message(
                    role: "user",
                    content: [
                        VisionRequest.VisionContent(type: "text", text: systemPrompt, image_url: nil),
                        VisionRequest.VisionContent(
                            type: "image_url",
                            text: nil,
                            image_url: VisionRequest.ImageURL(url: imageURL)
                        )
                    ]
                )
            ]
        )
        let content = try await sendRequest(request)
        return try parseResponse(content)
    }

    private func sendRequest(_ request: VisionRequest) async throws -> String {
        let base = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(base)/chat/completions") else {
            throw VisionRecognizerError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw VisionRecognizerError.requestFailed("无效的响应")
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "请求失败"
            throw VisionRecognizerError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(VisionResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func parseResponse(_ content: String) throws -> RecognizedMessages {
        var cleaned = content
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw VisionRecognizerError.parseFailed
        }

        do {
            let messages = try JSONDecoder().decode(RecognizedMessages.self, from: data)
            return messages
        } catch {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let their = json["their"] as? [String],
               let mine = json["mine"] as? [String] {
                return RecognizedMessages(their: their, mine: mine)
            }
            throw VisionRecognizerError.parseFailed
        }
    }
}
