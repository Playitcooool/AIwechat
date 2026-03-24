import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AssistantViewModel
    @State private var settings: AppSettings

    init(viewModel: AssistantViewModel) {
        self.viewModel = viewModel
        _settings = State(initialValue: SettingsManager.shared.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(spacing: 20) {
                    visionSection
                    replyModelSection
                    behaviorSection
                    historySection
                }
                .padding(16)
            }

            saveButton
        }
        .frame(width: 380, height: 500)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
    }

    private var titleBar: some View {
        HStack {
            Text("设置")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var visionSection: some View {
        sectionHeader("视觉识别 (Vision)", icon: "camera.viewfinder") {
            VStack(spacing: 12) {
                LabeledField(label: "API Base URL", placeholder: "https://api.openai.com/v1", text: $settings.visionBaseURL)
                LabeledField(label: "模型名称", placeholder: "gpt-4o", text: $settings.visionModel)
                SecureInputField(label: "API Key", placeholder: "sk-...", key: $settings.visionAPIKey)
                Toggle(isOn: $settings.captureWechatWindowOnly) {
                    Text("仅截取微信窗口")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.7, green: 0.75, blue: 0.85))
                }
                .tint(Color(red: 0.2, green: 0.6, blue: 0.8))
            }
        }
    }

    private var replyModelSection: some View {
        sectionHeader("回复模型 (Reply)", icon: "brain") {
            VStack(spacing: 12) {
                LabeledField(label: "API Base URL", placeholder: "http://127.0.0.1:1234/v1", text: $settings.openAIBaseURL)
                LabeledField(label: "模型名称", placeholder: "lmstudio-community-qwen3-4b", text: $settings.openAIModel)
                SecureInputField(label: "API Key", placeholder: "可选", key: $settings.openAIAPIKey)
                Stepper(value: $settings.contextWindowSize, in: 2...20) {
                    HStack {
                        Text("上下文窗口")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.7, green: 0.75, blue: 0.85))
                        Spacer()
                        Text("\(settings.contextWindowSize) 条")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        sectionHeader("行为", icon: "gearshape") {
            VStack(spacing: 12) {
                Toggle(isOn: $settings.wechatOnlyMode) {
                    Text("仅在微信前台时监听剪贴板")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.7, green: 0.75, blue: 0.85))
                }
                .tint(Color(red: 0.2, green: 0.6, blue: 0.8))

                Toggle(isOn: $settings.enableStyleLearning) {
                    Text("启用风格学习")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.7, green: 0.75, blue: 0.85))
                }
                .tint(Color(red: 0.2, green: 0.6, blue: 0.8))

                Picker(selection: $settings.language) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                } label: {
                    Text("语言")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.7, green: 0.75, blue: 0.85))
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var historySection: some View {
        sectionHeader("历史", icon: "clock") {
            HStack {
                Button {
                    HistoryManager.shared.clearHistory()
                    viewModel.refreshHistory()
                } label: {
                    Text("清空历史记录")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.4))
                }
                .buttonStyle(.plain)

                Spacer()

                if SettingsManager.shared.settings.menuBarMode {
                    Button {
                        var s = settings
                        s.menuBarMode = false
                        settings = s
                        SettingsManager.shared.settings = s
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "dock.left")
                                .font(.system(size: 10))
                            Text("退出菜单栏模式")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.2, green: 0.4, blue: 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        var s = settings
                        s.menuBarMode = true
                        settings = s
                        SettingsManager.shared.settings = s
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "menubar.rectangle")
                                .font(.system(size: 10))
                            Text("启用菜单栏模式")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.12, green: 0.16, blue: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            SettingsManager.shared.settings = settings
            viewModel.reloadSettings()
            dismiss()
        } label: {
            Text("保存")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(red: 0.05, green: 0.72, blue: 0.49))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            content()
        }
        .padding(12)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.6, green: 0.68, blue: 0.8))
            TextField(placeholder, text: $text)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color(red: 0.1, green: 0.14, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.4), lineWidth: 1))
        }
    }
}

struct SecureInputField: View {
    let label: String
    let placeholder: String
    @Binding var key: String
    @State private var isSecure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.6, green: 0.68, blue: 0.8))
                Spacer()
                Button {
                    isSecure.toggle()
                } label: {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.7))
                }
                .buttonStyle(.plain)
            }
            Group {
                if isSecure {
                    SwiftUI.SecureField(placeholder, text: $key)
                } else {
                    TextField(placeholder, text: $key)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(8)
            .background(Color(red: 0.1, green: 0.14, blue: 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.4), lineWidth: 1))
        }
    }
}
