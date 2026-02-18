import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AssistantViewModel

    var body: some View {
        VStack(spacing: 10) {
            titleBar

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
                    if viewModel.suggestions.isEmpty {
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
        .padding(14)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
    }

    private var titleBar: some View {
        HStack {
            Text("AI 回复助手")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("点赞并复制")
        }
        .padding(10)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
