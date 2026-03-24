import Foundation

struct HistoryRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let contextMessages: [String]
    let sourceMessage: String
    let candidates: [String]
    let chosen: String?
    let model: String
    let recognitionMode: String
    let recognizedCount: Int

    init(contextMessages: [String], sourceMessage: String, candidates: [String], chosen: String?, model: String, recognitionMode: String, recognizedCount: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.contextMessages = contextMessages
        self.sourceMessage = sourceMessage
        self.candidates = candidates
        self.chosen = chosen
        self.model = model
        self.recognitionMode = recognitionMode
        self.recognizedCount = recognizedCount
    }
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let maxRecords = 500

    private init() {}

    func append(_ record: HistoryRecord) {
        var records = loadRecords()
        records.append(record)
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
        saveRecords(records)
    }

    func loadRecords() -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: historyFileURL),
              let records = try? JSONDecoder().decode([HistoryRecord].self, from: data) else {
            return []
        }
        return records
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: historyFileURL)
    }

    private var historyFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat/history.json")
    }

    private func saveRecords(_ records: [HistoryRecord]) {
        try? FileManager.default.createDirectory(at: historyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: historyFileURL)
        }
    }
}
