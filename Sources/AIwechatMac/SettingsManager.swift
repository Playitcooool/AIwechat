import Foundation
import AppKit

struct AppSettings: Codable {
    var openAIModel: String = "gpt-4o"
    var openAIBaseURL: String = "https://api.openai.com/v1"
    var openAIAPIKey: String = ""
    var visionModel: String = "gpt-4o"
    var visionBaseURL: String = "https://api.openai.com/v1"
    var visionAPIKey: String = ""
    var language: String = "zh"
    var menuBarMode: Bool = false
    var contextWindowSize: Int = 6
    var wechatOnlyMode: Bool = true
    var enableStyleLearning: Bool = true
    var captureWechatWindowOnly: Bool = true

    static let `default` = AppSettings()

    static var current: AppSettings {
        get {
            if let data = UserDefaults.standard.data(forKey: "appSettings"),
               let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return settings
            }
            return .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "appSettings")
            }
        }
    }
}

final class SettingsManager {
    static let shared = SettingsManager()

    private init() {}

    var settings: AppSettings {
        get { AppSettings.current }
        set { AppSettings.current = newValue }
    }

    var isVisionConfigured: Bool {
        !settings.visionAPIKey.isEmpty || settings.visionBaseURL.contains("lmstudio")
    }

    var effectiveVisionBaseURL: String {
        let base = settings.visionBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var effectiveVisionAPIKey: String {
        settings.visionAPIKey
    }

    func openSettingsFile() {
        let url = settingsFileURL
        NSWorkspace.shared.open(url)
    }

    private var settingsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AIwechat/settings.json")
    }
}
