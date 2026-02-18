import AppKit
import Foundation

struct AppConfig {
    static let openAIAPIKey = "no_need"
    static let openAIModel = "lmstudio-community-qwen3-4b-instruct-2507-mlx"
    static let openAIBaseURL = "http://127.0.0.1:1234/v1"
    static let systemPrompt = "你是一个微信聊天助手。请基于对方消息，生成3条不同风格的中文回复建议。要求：自然口语、不过度夸张。"

    static let enableContextMemory = true
    static let contextWindowSize = 6
    static let wechatOnlyMode = true
    static let strictWechatDetection = false
    static let wechatAppHints = ["WeChat", "微信"]
    static let ignoreSelfPrefixes = ["我:", "我：", "Me:", "Me："]
    static let myName = ""
    static let pollInterval: TimeInterval = 0.8
    static let enableStyleLearning = true
    static let minFeedbackForStyle = 5
    static let maxStyleSamples = 300
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

struct FeedbackRecord: Codable {
    let timestamp: String
    let sourceMessage: String
    let contextMessages: [String]
    let candidates: [String]
    let chosen: String
    let model: String
}

struct StyleProfile: Codable {
    let updatedAt: String
    let sampleCount: Int
    let avgLength: Int
    let concisePreference: String
    let questionTone: String
    let emojiTone: String
    let punctuationTone: String
    let commonEndings: [String]
    let instruction: String
}

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var statusText: String = "自动监听中（微信前台 + 剪贴板）"
    @Published var suggestions: [String] = []

    private var timer: Timer?
    private var lastClipboard = ""
    private var isGenerating = false
    private var pendingMessage = ""

    private var contextMessages: [String] = []
    private var lastUserMessage = ""
    private var lastContextSnapshot: [String] = []
    private var styleProfile: StyleProfile?

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
        if AppConfig.wechatOnlyMode && !isWechatForeground() {
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
        if AppConfig.ignoreSelfPrefixes.contains(where: { stripped.hasPrefix($0) }) { return true }
        if !AppConfig.myName.isEmpty {
            if stripped.hasPrefix("\(AppConfig.myName):") || stripped.hasPrefix("\(AppConfig.myName)：") {
                return true
            }
        }
        return false
    }

    private func isWechatForeground() -> Bool {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return !AppConfig.strictWechatDetection
        }
        return AppConfig.wechatAppHints.contains(where: { appName.contains($0) })
    }

    private func buildPrompt(_ userMessage: String) -> String {
        let outputRule = "请严格输出一个 JSON 数组，长度必须是3。示例：[\"回复1\",\"回复2\",\"回复3\"]。每个元素必须是一条完整回复，不要输出额外文字。"
        let styleRule = styleInstructionBlock()
        if !AppConfig.enableContextMemory {
            return "对方消息：\n\(userMessage)\n\n请输出3条不同风格的中文回复建议。\n\(styleRule)\n\(outputRule)"
        }

        let history = contextMessages.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let historyBlock = history.isEmpty ? "(无)" : history
        return "以下是最近复制到剪贴板的消息（按时间从旧到新）：\n\(historyBlock)\n\n当前最新消息：\n\(userMessage)\n\n请结合上下文输出3条不同风格的中文回复建议。\n\(styleRule)\n\(outputRule)"
    }

    private func generateReply(for userMessage: String) {
        if AppConfig.openAIAPIKey.isEmpty || AppConfig.openAIAPIKey == "your_openai_api_key" {
            statusText = "请在 AssistantViewModel.swift 设置 openAIAPIKey"
            return
        }

        isGenerating = true
        lastUserMessage = userMessage
        lastContextSnapshot = contextMessages
        statusText = "生成中..."

        Task {
            do {
                let content = try await fetchCompletion(prompt: buildPrompt(userMessage))
                let parsed = parseSuggestions(content)
                suggestions = Array(parsed.prefix(3))
                statusText = AppConfig.enableContextMemory ? "已生成（上下文 \(contextMessages.count) 条）" : "已生成"
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
        let base = AppConfig.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.openAIAPIKey)", forHTTPHeaderField: "Authorization")

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

        func clean(_ raw: String) -> String {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "\\n", with: " ")
            s = s.replacingOccurrences(of: "\\\"", with: "\"")
            s = s.replacingOccurrences(of: "^[0-9]+[\\).、:：\\s]*", with: "", options: .regularExpression)
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]“”‘’ "))
            return s
        }

        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let parsed = array.compactMap { clean(String(describing: $0)) }.filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }

        let numbered = text.replacingOccurrences(of: "(?s).*?(?=1[\\).、:：])", with: "", options: .regularExpression)
        let regex = try? NSRegularExpression(pattern: "(?:^|\\s)(?:[1-9])[\\.、\\)）:：]\\s*(.*?)(?=(?:\\s(?:[1-9])[\\.、\\)）:：]\\s*)|$)")
        if let regex {
            let ns = numbered as NSString
            let matches = regex.matches(in: numbered, range: NSRange(location: 0, length: ns.length))
            let parsed = matches.compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                return clean(ns.substring(with: match.range(at: 1)))
            }.filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }

        let lineParsed = text.split(separator: "\n").map { clean(String($0)) }.filter { !$0.isEmpty }
        if !lineParsed.isEmpty { return lineParsed }

        return [clean(text)]
    }

    private func appendFeedback(chosen: String) {
        let record = FeedbackRecord(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sourceMessage: lastUserMessage,
            contextMessages: lastContextSnapshot,
            candidates: suggestions,
            chosen: chosen,
            model: AppConfig.openAIModel
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else { return }

            let fileURL = feedbackFileURL()
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                if let bytes = "\(line)\n".data(using: .utf8) {
                    try handle.write(contentsOf: bytes)
                }
                try handle.close()
            } else {
                try "\(line)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            refreshStyleProfile()
        } catch {
            statusText = "记录偏好失败：\(error.localizedDescription)"
        }
    }

    private func feedbackFileURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat", isDirectory: true)
        return dir.appendingPathComponent("preferences.jsonl")
    }

    private func styleProfileFileURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat", isDirectory: true)
        return dir.appendingPathComponent("style_profile.json")
    }

    private func styleInstructionBlock() -> String {
        guard AppConfig.enableStyleLearning else {
            return "风格约束：自然口语，简洁清晰。"
        }
        guard let profile = styleProfile else {
            return "风格约束：自然口语，简洁清晰。若有合适语气可轻微幽默。"
        }
        return "用户风格偏好（来自历史点赞反馈）：\(profile.instruction)"
    }

    private func refreshStyleProfile() {
        guard AppConfig.enableStyleLearning else { return }
        let records = loadFeedbackRecords()
        guard records.count >= AppConfig.minFeedbackForStyle else {
            styleProfile = nil
            return
        }
        let chosenTexts = records.suffix(AppConfig.maxStyleSamples).map { $0.chosen }
        let profile = buildStyleProfile(from: chosenTexts)
        styleProfile = profile
        persistStyleProfile(profile)
    }

    private func loadFeedbackRecords() -> [FeedbackRecord] {
        let fileURL = feedbackFileURL()
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        var output: [FeedbackRecord] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let lineData = line.data(using: .utf8) else { continue }
            if let item = try? decoder.decode(FeedbackRecord.self, from: lineData) {
                output.append(item)
            }
        }
        return output
    }

    private func buildStyleProfile(from chosenTexts: [String]) -> StyleProfile {
        let sampleCount = chosenTexts.count
        let lengths = chosenTexts.map { $0.count }
        let avgLength = max(1, lengths.reduce(0, +) / max(1, lengths.count))

        let questionCount = chosenTexts.filter { $0.contains("?") || $0.contains("？") }.count
        let exclamationCount = chosenTexts.filter { $0.contains("!") || $0.contains("！") }.count
        let emojiRegex = try? NSRegularExpression(pattern: "[\\u{1F300}-\\u{1FAFF}]")
        let emojiCount = chosenTexts.reduce(0) { partial, text in
            guard let emojiRegex else { return partial }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            return partial + emojiRegex.numberOfMatches(in: text, range: range)
        }

        let endingTokens = extractCommonEndings(from: chosenTexts)
        let concisePreference = avgLength <= 18 ? "偏短句" : (avgLength <= 32 ? "中等长度" : "偏长句")
        let questionTone = ratioText(questionCount, total: sampleCount, low: "少用反问", mid: "偶尔反问", high: "常用提问句")
        let punctuationTone = ratioText(exclamationCount, total: sampleCount, low: "少用感叹号", mid: "适度感叹", high: "偏热情感叹")
        let emojiTone = emojiCount == 0 ? "几乎不用 emoji" : (emojiCount < sampleCount ? "偶尔使用 emoji" : "较常使用 emoji")

        var rules: [String] = []
        rules.append("句长：\(concisePreference)（平均\(avgLength)字）")
        rules.append("语气：\(questionTone)，\(punctuationTone)，\(emojiTone)")
        if !endingTokens.isEmpty {
            rules.append("常见收尾：\(endingTokens.joined(separator: "、"))")
        }
        rules.append("尽量贴近以上风格，但保持自然，不要机械复读")

        return StyleProfile(
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            sampleCount: sampleCount,
            avgLength: avgLength,
            concisePreference: concisePreference,
            questionTone: questionTone,
            emojiTone: emojiTone,
            punctuationTone: punctuationTone,
            commonEndings: endingTokens,
            instruction: rules.joined(separator: "；")
        )
    }

    private func ratioText(_ value: Int, total: Int, low: String, mid: String, high: String) -> String {
        guard total > 0 else { return low }
        let r = Double(value) / Double(total)
        if r < 0.2 { return low }
        if r < 0.45 { return mid }
        return high
    }

    private func extractCommonEndings(from texts: [String]) -> [String] {
        var counter: [String: Int] = [:]
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            let tail2 = String(trimmed.suffix(2))
            let tail3 = String(trimmed.suffix(min(3, trimmed.count)))
            counter[tail2, default: 0] += 1
            counter[tail3, default: 0] += 1
        }
        let ranked = counter
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { $0.key }
        return Array(ranked.prefix(5))
    }

    private func persistStyleProfile(_ profile: StyleProfile) {
        do {
            let url = styleProfileFileURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(profile)
            try data.write(to: url, options: .atomic)
        } catch {
            statusText = "写入风格画像失败：\(error.localizedDescription)"
        }
    }
}
