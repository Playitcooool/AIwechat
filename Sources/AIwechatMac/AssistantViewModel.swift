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
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var pendingRecognizedMessages: RecognizedMessages?
    @Published var streamingText: String = ""
    @Published var historyCount: Int = 0
    @Published var isStreaming: Bool = false

    private var timer: Timer?
    private var lastClipboard = ""
    private var isGenerating = false
    private var pendingMessage = ""

    private var contextMessages: [String] = []
    private var lastUserMessage = ""
    private var lastContextSnapshot: [String] = []
    private var styleProfile: StyleProfile?

    private var visionRecognizer: VisionMessageRecognizer?

    var effectiveContextWindowSize: Int {
        SettingsManager.shared.settings.contextWindowSize
    }

    var effectiveWechatOnlyMode: Bool {
        SettingsManager.shared.settings.wechatOnlyMode
    }

    var effectivePollInterval: TimeInterval {
        AppConfig.pollInterval
    }

    var effectiveSystemPrompt: String {
        let settings = SettingsManager.shared.settings
        if settings.language == "en" {
            return "You are a WeChat chat assistant. Generate 3 different style reply suggestions based on the other person's message. Requirements: natural, conversational, not exaggerated."
        }
        return AppConfig.systemPrompt
    }

    func startMonitoring() {
        refreshStyleProfile()
        stopMonitoring()
        let interval = effectivePollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
        appendFeedback(chosen: suggestion, recognizedCount: contextMessages.count)
        recordHistory(chosen: suggestion)
        statusText = "已点赞并复制"
    }

    func dislikeSuggestion(_ suggestion: String) {
        appendFeedback(chosen: nil, recognizedCount: contextMessages.count, rejected: suggestion)
        statusText = "已反馈"
    }

    func copyAllSuggestions() {
        copyAll()
    }

    func refreshHistory() {
        historyCount = HistoryManager.shared.loadRecords().count
    }

    func reloadSettings() {
        if recognitionMode == .clipboard {
            stopMonitoring()
            startMonitoring()
        }
        visionRecognizer = nil
    }

    private func pollClipboard() {
        if effectiveWechatOnlyMode && !isWechatForeground {
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
            if contextMessages.count > effectiveContextWindowSize {
                contextMessages.removeFirst(contextMessages.count - effectiveContextWindowSize)
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
            return buildBasicPrompt(userMessage, styleHint: styleHint)
        }

        let history = contextMessages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return buildContextPrompt(history: history, currentMessage: userMessage, styleHint: styleHint)
    }

    private func buildBasicPrompt(_ message: String, styleHint: String) -> String {
        if SettingsManager.shared.settings.language == "en" {
            return "Message:\n\(message)\n\nGenerate 3 different style reply suggestions.\n\(styleHint)\nOutput JSON array: [\"reply1\",\"reply2\",\"reply3\"]."
        }
        return "对方消息：\n\(message)\n\n请输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
    }

    private func buildContextPrompt(history: String, currentMessage: String, styleHint: String) -> String {
        if SettingsManager.shared.settings.language == "en" {
            return "Recent messages:\n\(history.isEmpty ? "(none)" : history)\n\nCurrent message:\n\(currentMessage)\n\nGenerate 3 different style reply suggestions.\n\(styleHint)\nOutput JSON array: [\"reply1\",\"reply2\",\"reply3\"]."
        }
        return "最近消息：\n\(history.isEmpty ? "(无)" : history)\n\n当前消息：\n\(currentMessage)\n\n请输出3条不同风格的中文回复建议。\n\(styleHint)\n请严格输出一个 JSON 数组，示例：[\"回复1\",\"回复2\",\"回复3\"]。"
    }

    private func generateReply(for userMessage: String) {
        isGenerating = true
        isStreaming = false
        lastUserMessage = userMessage
        lastContextSnapshot = contextMessages
        statusText = "生成中..."

        Task {
            do {
                let content = try await fetchCompletionStreaming(prompt: buildPrompt(userMessage))
                let parsed = parseSuggestions(content)
                await MainActor.run {
                    self.suggestions = Array(parsed.prefix(3))
                    let count = AppConfig.enableContextMemory ? self.contextMessages.count : 0
                    self.statusText = count > 0 ? "已生成（上下文 \(count) 条）" : "已生成"
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    self.suggestions = []
                    self.statusText = "生成失败：\(error.localizedDescription)"
                    self.isStreaming = false
                }
            }

            await MainActor.run {
                self.isGenerating = false
                self.consumePendingIfNeeded()
            }
        }
    }

    private func consumePendingIfNeeded() {
        guard !pendingMessage.isEmpty else { return }
        let next = pendingMessage
        pendingMessage = ""
        generateReply(for: next)
    }

    private func fetchCompletion(prompt: String) async throws -> String {
        let settings = SettingsManager.shared.settings
        let base = settings.openAIBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.openAIAPIKey.isEmpty {
            request.setValue("Bearer \(settings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ChatCompletionRequest(
            model: settings.openAIModel,
            temperature: 0.7,
            messages: [
                .init(role: "system", content: effectiveSystemPrompt),
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

    private func fetchCompletionStreaming(prompt: String) async throws -> String {
        let settings = SettingsManager.shared.settings
        let base = settings.openAIBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.openAIAPIKey.isEmpty {
            request.setValue("Bearer \(settings.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let streamBody: [String: Any] = [
            "model": settings.openAIModel,
            "temperature": 0.7,
            "stream": true,
            "messages": [
                ["role": "system", "content": effectiveSystemPrompt],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: streamBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "AIwechatMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "请求失败"])
        }

        var fullContent = ""
        var buffer = Data()

        for try await byte in bytes {
            if byte == 10 { // newline
                let line = String(data: buffer, encoding: .utf8) ?? ""
                buffer = Data()
                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if jsonStr == "[DONE]" { break }
                    if let data = jsonStr.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                        let delta = chunk.choices.first?.delta.content ?? ""
                        if !delta.isEmpty {
                            fullContent += delta
                            await MainActor.run {
                                self.streamingText = fullContent
                            }
                        }
                    }
                }
            } else {
                buffer.append(byte)
            }
        }

        await MainActor.run {
            self.streamingText = ""
        }
        return fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private func parseSuggestions(_ content: String) -> [String] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let parsed = array.compactMap { obj -> String? in
                let s = String(describing: obj).trimmingCharacters(in: CharacterSet(charactersIn: "\"[] "))
                return s.isEmpty ? nil : s
            }
            if !parsed.isEmpty { return parsed }
        }

        let lines = text.components(separatedBy: "\n")
        let parsed = lines.compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "^[0-9]+[\\).、:：\\s]*", with: "", options: .regularExpression)
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]“”‘’ "))
            return s.isEmpty ? nil : s
        }
        return parsed.isEmpty ? [text] : parsed
    }

    private func appendFeedback(chosen: String?, recognizedCount: Int = 0, rejected: String? = nil) {
        let record: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sourceMessage": lastUserMessage,
            "contextMessages": lastContextSnapshot,
            "candidates": suggestions,
            "chosen": chosen as Any,
            "rejected": rejected as Any,
            "model": SettingsManager.shared.settings.openAIModel
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

    private func recordHistory(chosen: String?) {
        let record = HistoryRecord(
            contextMessages: lastContextSnapshot,
            sourceMessage: lastUserMessage,
            candidates: suggestions,
            chosen: chosen,
            model: SettingsManager.shared.settings.openAIModel,
            recognitionMode: recognitionMode == .vision ? "vision" : "clipboard",
            recognizedCount: contextMessages.count
        )
        HistoryManager.shared.append(record)
        historyCount = HistoryManager.shared.loadRecords().count
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
            return SettingsManager.shared.settings.language == "en"
                ? "Style: natural, conversational."
                : "风格：自然口语，简洁清晰。"
        }
        return SettingsManager.shared.settings.language == "en"
            ? "User preference: avg \(profile.avgLength) chars per reply, keep natural."
            : "用户偏好：平均\(profile.avgLength)字每条，保持自然。"
    }

    private func refreshStyleProfile() {
        guard SettingsManager.shared.settings.enableStyleLearning else { return }
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
                let imageData: Data
                if SettingsManager.shared.settings.captureWechatWindowOnly {
                    imageData = try ScreenCapture.captureWindow(named: AppConfig.wechatAppName)
                } else {
                    imageData = try ScreenCapture.captureScreen()
                }
                try await recognizeImage(imageData, retries: 2)
            } catch {
                await MainActor.run {
                    statusText = "截图失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func recognizeImage(_ imageData: Data, retries: Int) async throws {
        await MainActor.run {
            statusText = "识别消息中..."
        }

        if visionRecognizer == nil {
            visionRecognizer = VisionMessageRecognizer()
        }

        guard let recognizer = visionRecognizer else { return }

        var lastError: Error?
        for attempt in 0...(retries > 0 ? retries : 0) {
            do {
                let messages = try await recognizer.recognize(imageData: imageData)
                await MainActor.run {
                    processRecognizedMessages(messages)
                }
                return
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        await MainActor.run {
            statusText = "识别失败: \(lastError?.localizedDescription ?? "未知错误")"
        }
    }

    private func processRecognizedMessages(_ messages: RecognizedMessages) {
        var allMessages: [String] = []
        allMessages.append(contentsOf: messages.their)
        allMessages.append(contentsOf: messages.mine)

        guard !allMessages.isEmpty else {
            statusText = "未识别到消息"
            return
        }

        contextMessages = allMessages
        pendingRecognizedMessages = messages

        if let lastTheirMessage = messages.their.last {
            lastUserMessage = lastTheirMessage
            lastContextSnapshot = contextMessages
            generateReplyFromVision(for: lastTheirMessage)
        } else {
            statusText = "没有对方消息"
        }
    }

    func confirmRecognizedMessages(editedTheir: [String], editedMine: [String]) {
        var allMessages: [String] = []
        allMessages.append(contentsOf: editedTheir)
        allMessages.append(contentsOf: editedMine)

        contextMessages = allMessages
        pendingRecognizedMessages = nil

        if let lastTheirMessage = editedTheir.last {
            lastUserMessage = lastTheirMessage
            lastContextSnapshot = contextMessages
            generateReplyFromVision(for: lastTheirMessage)
        }
    }

    func cancelRecognition() {
        pendingRecognizedMessages = nil
        contextMessages.removeAll()
        statusText = "已取消识别"
    }

    private func generateReplyFromVision(for userMessage: String) {
        isGenerating = true
        isStreaming = false
        statusText = "生成中..."

        Task {
            do {
                let content = try await fetchCompletionStreaming(prompt: buildPromptFromVision(userMessage))
                let parsed = parseSuggestions(content)
                await MainActor.run {
                    self.suggestions = Array(parsed.prefix(3))
                    let count = self.contextMessages.count
                    self.statusText = "已生成（识别 \(count) 条消息）"
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    self.suggestions = []
                    self.statusText = "生成失败: \(error.localizedDescription)"
                    self.isStreaming = false
                }
            }

            await MainActor.run {
                self.isGenerating = false
            }
        }
    }

    private func buildPromptFromVision(_ userMessage: String) -> String {
        let styleHint = styleInstructionBlock()
        let theirMessages = contextMessages.filter { msg in
            !AppConfig.ignoreSelfPrefixes.contains { msg.hasPrefix($0) }
        }

        if theirMessages.count <= 1 {
            return buildBasicPrompt(userMessage, styleHint: styleHint)
        }

        let history = contextMessages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return buildContextPrompt(history: history, currentMessage: userMessage, styleHint: styleHint)
    }

    func toggleRecognitionMode() {
        switch recognitionMode {
        case .clipboard:
            recognitionMode = .vision
            stopMonitoring()
            contextMessages.removeAll()
            statusText = "视觉模式（快捷键 ⌘⇧V 触发）"
        case .vision:
            recognitionMode = .clipboard
            pendingRecognizedMessages = nil
            startMonitoring()
            statusText = "剪贴板模式"
        }
    }
}
