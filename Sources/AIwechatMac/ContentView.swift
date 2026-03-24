import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(spacing: 10) {
            titleBar

            if let pending = viewModel.pendingRecognizedMessages {
                recognitionConfirmationView(pending)
            } else {
                mainContent
            }

            modeToggleBar
        }
        .padding(14)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showHistory) {
            HistoryView()
        }
    }

    private var titleBar: some View {
        HStack {
            Text("AI 回复助手")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                viewModel.showHistory = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    if viewModel.historyCount > 0 {
                        Text("\(viewModel.historyCount)")
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                .foregroundStyle(Color(red: 0.6, green: 0.7, blue: 0.85))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.6, green: 0.7, blue: 0.85))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func recognitionConfirmationView(_ messages: RecognizedMessages) -> some View {
        VStack(spacing: 8) {
            Text("识别结果确认")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !messages.their.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("对方消息 (\(messages.their.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.7))
                    ForEach(Array(messages.their.enumerated()), id: \.offset) { idx, msg in
                        Text("\(idx + 1). \(msg)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.8, green: 0.85, blue: 0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(red: 0.05, green: 0.15, blue: 0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            if !messages.mine.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的消息 (\(messages.mine.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.7))
                    ForEach(Array(messages.mine.enumerated()), id: \.offset) { idx, msg in
                        Text("\(idx + 1). \(msg)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.8, green: 0.85, blue: 0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            HStack(spacing: 8) {
                Button("重新识别") {
                    viewModel.cancelRecognition()
                    viewModel.captureAndRecognize()
                }
                .buttonStyle(ActionButtonStyle(bg: Color(red: 0.2, green: 0.4, blue: 0.6)))

                Button("确认") {
                    viewModel.confirmRecognizedMessages(editedTheir: messages.their, editedMine: messages.mine)
                }
                .buttonStyle(ActionButtonStyle(bg: Color(red: 0.05, green: 0.72, blue: 0.49)))

                Button("取消") {
                    viewModel.cancelRecognition()
                }
                .buttonStyle(ActionButtonStyle(bg: Color(red: 0.12, green: 0.16, blue: 0.22)))
            }
        }
        .padding(10)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var mainContent: some View {
        VStack(spacing: 10) {
            Text(viewModel.statusText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(red: 0.66, green: 0.73, blue: 0.86))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(red: 0.07, green: 0.13, blue: 0.23))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                        streamingCard(text: viewModel.streamingText)
                    }

                    if viewModel.suggestions.isEmpty && !viewModel.isStreaming {
                        Text("暂无建议")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(viewModel.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            suggestionCard(index: idx + 1, text: suggestion)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("复制全部") {
                    viewModel.copyAll()
                }
                .buttonStyle(ActionButtonStyle(bg: Color(red: 0.05, green: 0.72, blue: 0.49)))

                Button("清空上下文") {
                    viewModel.clearContext()
                }
                .buttonStyle(ActionButtonStyle(bg: Color(red: 0.12, green: 0.16, blue: 0.22)))
            }
        }
    }

    private func suggestionCard(index: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index). \(text)")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.likeSuggestion(text)
            } label: {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("点赞并复制")

            Button {
                viewModel.dislikeSuggestion(text)
            } label: {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.55))
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("踩，反馈错误")
        }
        .padding(10)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func streamingCard(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.9))
            Text(text.isEmpty ? "正在生成..." : text)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if text.isEmpty {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                }
        }
        .padding(10)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.5, blue: 0.8), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var modeToggleBar: some View {
        HStack(spacing: 12) {
            Text("模式：")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.66, green: 0.73, blue: 0.86))

            Button {
                viewModel.toggleRecognitionMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.recognitionMode == .clipboard ? "doc.on.clipboard" : "camera.viewfinder")
                        .font(.system(size: 10))
                    Text(viewModel.recognitionMode == .clipboard ? "剪贴板" : "视觉")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(viewModel.recognitionMode == .clipboard
                    ? Color(red: 0.12, green: 0.16, blue: 0.22)
                    : Color(red: 0.2, green: 0.4, blue: 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Spacer()

            if viewModel.recognitionMode == .vision {
                Text("⌘⇧V 截屏识别")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.5, green: 0.6, blue: 0.7))
            }
        }
        .padding(.top, 4)
    }
}

struct ActionButtonStyle: ButtonStyle {
    let bg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(bg.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
