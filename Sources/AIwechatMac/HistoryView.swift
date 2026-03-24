import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [HistoryRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(red: 0.3, green: 0.4, blue: 0.55))
                    Text("暂无历史记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(records.reversed()) { record in
                            historyCard(record)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 400, height: 450)
        .background(Color(red: 0.06, green: 0.09, blue: 0.15))
        .onAppear { loadRecords() }
    }

    private var titleBar: some View {
        HStack {
            Text("历史记录")
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

    private func historyCard(_ record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.recognitionMode == .vision ? "视觉" : "剪贴板")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(record.recognitionMode == .vision
                        ? Color(red: 0.2, green: 0.4, blue: 0.6)
                        : Color(red: 0.15, green: 0.35, blue: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.5, green: 0.55, blue: 0.65))
            }

            Text("对方：\(record.sourceMessage)")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.75, green: 0.8, blue: 0.9))
                .lineLimit(2)

            if let chosen = record.chosen {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.05, green: 0.72, blue: 0.49))
                    Text(chosen)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            if record.recognizedCount > 0 {
                Text("上下文 \(record.recognizedCount) 条")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.4, green: 0.5, blue: 0.6))
            }
        }
        .padding(10)
        .background(Color(red: 0.07, green: 0.11, blue: 0.19))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.18, green: 0.25, blue: 0.38), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadRecords() {
        records = HistoryManager.shared.loadRecords()
    }
}
