import AppKit
import Foundation

struct AppConfig {
    static let openAIModel = "lmstudio-community-qwen3-4b-instruct-2507-mlx"
    static let openAIBaseURL = "http://127.0.0.1:1234/v1"
    static let systemPrompt = "你是一个微信聊天助手。请基于对方消息，生成3条不同风格的中文回复建议。要求：自然口语、不过度夸张。"

    static let enableContextMemory = true
    static let contextWindowSize = 6
    static let wechatOnlyMode = true
    static let wechatAppName = "WeChat"
    static let ignoreSelfPrefixes = ["我:", "我：", "Me:", "Me："]
    static let myName = ""
    static let pollInterval: TimeInterval = 0.8

    // 视觉识别配置
    static let visionModel = "gpt-4o"
    static let visionBaseURL = "https://api.openai.com/v1"
}

enum RecognitionMode {
    case clipboard
    case vision
}

struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

struct StyleProfile: Codable {
    let updatedAt: String
    let avgLength: Int
    let instruction: String
}

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var statusText: String = "自动监听中"
    @Published var suggestions: [String] = []
    @Published var recognitionMode: RecognitionMode = .clipboard

    private var timer: Timer?
    private var lastClipboard = ""
    private var isGenerating = false
    private var pendingMessage = ""

    private var contextMessages: [String] = []
    private var lastUserMessage = ""
    private var lastContextSnapshot: [String] = []
    private var styleProfile: StyleProfile?

    private var visionRecognizer: VisionMessageRecognizer?

    func startMonitoring() {
        refreshStyleProfile()
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: AppConfig.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func clearContext() {
        contextMessages.removeAll()
        statusText = "上下文已清空"
    }

    func copyAll() {
        let text = suggestions.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "已复制全部"
    }

    func likeSuggestion(_ suggestion: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion, forType: .string)
        appendFeedback(chosen: suggestion)
        statusText = "已点赞并复制"
    }

    private func pollClipboard() {
        if AppConfig.wechatOnlyMode && !isWechatForeground {
            return
        }
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNewMessage(text) else { return }

        lastClipboard = text
        if looksLikeSelfMessage(text) {
            statusText = "已忽略疑似自己消息"
            return
        }

        if AppConfig.enableContextMemory {
            contextMessages.append(text)
            if contextMessages.count > AppConfig.contextWindowSize {
                contextMessages.removeFirst(contextMessages.count - AppConfig.contextWindowSize)
            }
        }

        if isGenerating {
            pendingMessage = text
            statusText = "生成中，已缓存最新消息"
            return
        }

        generateReply(for: text)
    }

    private func isNewMessage(_ text: String) -> Bool {
        if text.isEmpty || text == lastClipboard { return false }
        if text.count < 2 || text.count > 1200 { return false }
        if text.range(of: "^[\\d\\W_]+$", options: .regularExpression) != nil { return false }
        return true
    }

    private func looksLikeSelfMessage(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in AppConfig.ignoreSelfPrefixes {
            if stripped.hasPrefix(prefix) { return true }
        }
        if !AppConfig.myName.isEmpty {
            if stripped.hasPrefix("\(AppConfig.myName):") || stripped.hasPrefix("\(AppConfig.myName)：") {
                return true
            }
        }
        return false
    }

    private var isWechatForeground: Bool {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return true
        }
        return appName.contains(AppConfig.wechatAppName)
    }

    private func buildPrompt(_ userMessage: String) -> String {
        let styleHint = styleInstructionBlock()
        if !AppConfig.enableContextMemory {
            return "对方消息：\n\(userMessage)\n\n请输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
        }

        let history = contextMessages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "最近消息：\n\(history.isEmpty ? "(无)" : history)\n\n当前消息：\n\(userMessage)\n\n请输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
    }

    private func generateReply(for userMessage: String) {
        isGenerating = true
        lastUserMessage = userMessage
        lastContextSnapshot = contextMessages
        statusText = "生成中..."

        Task {
            do {
                let content = try await fetchCompletion(prompt: buildPrompt(userMessage))
                let parsed = parseSuggestions(content)
                suggestions = Array(parsed.prefix(3))
                let count = AppConfig.enableContextMemory ? contextMessages.count : 0
                statusText = count > 0 ? "已生成（上下文 \(count) 条）" : "已生成"
            } catch {
                suggestions = []
                statusText = "生成失败：\(error.localizedDescription)"
            }

            isGenerating = false
            consumePendingIfNeeded()
        }
    }

    private func consumePendingIfNeeded() {
        guard !pendingMessage.isEmpty else { return }
        let next = pendingMessage
        pendingMessage = ""
        generateReply(for: next)
    }

    private func fetchCompletion(prompt: String) async throws -> String {
        let base = AppConfig.openAIBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: AppConfig.openAIModel,
            temperature: 0.7,
            messages: [
                .init(role: "system", content: AppConfig.systemPrompt),
                .init(role: "user", content: prompt),
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "请求失败"
            throw NSError(domain: "AIwechatMac", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func parseSuggestions(_ content: String) -> [String] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        // Try JSON array first
        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let parsed = array.compactMap { obj -> String? in
                let s = String(describing: obj).trimmingCharacters(in: CharacterSet(charactersIn: "\"[] "))
                return s.isEmpty ? nil : s
            }
            if !parsed.isEmpty { return parsed }
        }

        // Fallback: split by lines, strip numbering
        let lines = text.components(separatedBy: "\n")
        let parsed = lines.compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "^[0-9]+[\\).、:：\\s]*", with: "", options: .regularExpression)
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]“”‘’ "))
            return s.isEmpty ? nil : s
        }
        return parsed.isEmpty ? [text] : parsed
    }

    private func appendFeedback(chosen: String) {
        let record: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sourceMessage": lastUserMessage,
            "contextMessages": lastContextSnapshot,
            "candidates": suggestions,
            "chosen": chosen,
            "model": AppConfig.openAIModel
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let line = String(data: data, encoding: .utf8) else { return }

        let fileURL = feedbackFileURL
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try? FileHandle(forWritingTo: fileURL)
            try? handle?.seekToEnd()
            try? handle?.write(contentsOf: "\(line)\n".data(using: .utf8)!)
            try? handle?.close()
        } else {
            try? "\(line)\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        refreshStyleProfile()
    }

    private var feedbackFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat/preferences.jsonl")
    }

    private var styleProfileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat/style_profile.json")
    }

    private func styleInstructionBlock() -> String {
        guard let profile = styleProfile else {
            return "风格：自然口语，简洁清晰。"
        }
        return "用户偏好：平均\(profile.avgLength)字每条，保持自然。"
    }

    private func refreshStyleProfile() {
        guard let data = try? Data(contentsOf: feedbackFileURL),
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n").filter { !$0.isEmpty }
        guard lines.count >= 5 else { return }

        let chosenTexts = lines.suffix(300).compactMap { line -> String? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chosen = json["chosen"] as? String else { return nil }
            return chosen
        }

        let lengths = chosenTexts.map { $0.count }
        let avg = lengths.isEmpty ? 0 : lengths.reduce(0, +) / lengths.count

        let profile = StyleProfile(
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            avgLength: avg,
            instruction: "句长约\(avg)字"
        )

        try? FileManager.default.createDirectory(at: styleProfileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(profile).write(to: styleProfileURL)

        styleProfile = profile
    }

    // MARK: - Vision Mode

    func captureAndRecognize() {
        statusText = "截取屏幕中..."
        Task {
            do {
                let imageData = try ScreenCapture.captureScreen()
                try await recognizeImage(imageData)
            } catch {
                await MainActor.run {
                    statusText = "截图失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func recognizeImage(_ imageData: Data) async throws {
        await MainActor.run {
            statusText = "识别消息中..."
        }

        if visionRecognizer == nil {
            visionRecognizer = VisionMessageRecognizer()
        }

        guard let recognizer = visionRecognizer else { return }

        do {
            let messages = try await recognizer.recognize(imageData: imageData)
            await MainActor.run {
                processRecognizedMessages(messages)
            }
        } catch {
            await MainActor.run {
                statusText = "识别失败: \(error.localizedDescription)"
            }
        }
    }

    private func processRecognizedMessages(_ messages: RecognizedMessages) {
        // 构建上下文消息列表：先放对方消息，再放我的消息
        var allMessages: [String] = []
        allMessages.append(contentsOf: messages.their)
        allMessages.append(contentsOf: messages.mine)

        guard !allMessages.isEmpty else {
            statusText = "未识别到消息"
            return
        }

        // 更新上下文
        contextMessages = allMessages

        // 使用最后一条对方消息生成回复
        if let lastTheirMessage = messages.their.last {
            lastUserMessage = lastTheirMessage
            lastContextSnapshot = contextMessages
            generateReplyFromVision(for: lastTheirMessage)
        } else {
            statusText = "没有对方消息"
        }
    }

    private func generateReplyFromVision(for userMessage: String) {
        isGenerating = true
        statusText = "生成中..."

        Task {
            do {
                let content = try await fetchCompletion(prompt: buildPromptFromVision(userMessage))
                let parsed = parseSuggestions(content)
                suggestions = Array(parsed.prefix(3))
                await MainActor.run {
                    let count = contextMessages.count
                    statusText = "已生成（识别 \(count) 条消息）"
                }
            } catch {
                await MainActor.run {
                    suggestions = []
                    statusText = "生成失败: \(error.localizedDescription)"
                }
            }

            isGenerating = false
        }
    }

    private func buildPromptFromVision(_ userMessage: String) -> String {
        let styleHint = styleInstructionBlock()

        // 构建视觉模式下的上下文信息
        let theirMessages = contextMessages.filter { msg in
            !AppConfig.ignoreSelfPrefixes.contains { msg.hasPrefix($0) }
        }

        if theirMessages.count <= 1 {
            return "对方消息：\n\(userMessage)\n\n请输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
        }

        // 多条消息时，显示完整上下文
        let history = contextMessages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "聊天上下文：\n\(history)\n\n请基于以上上下文，输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
    }

    func toggleRecognitionMode() {
        switch recognitionMode {
        case .clipboard:
            recognitionMode = .vision
            stopMonitoring()
            statusText = "视觉模式（快捷键 ⌘⇧V 触发）"
        case .vision:
            recognitionMode = .clipboard
            startMonitoring()
            statusText = "剪贴板模式"
        }
    }
}
