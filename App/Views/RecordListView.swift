import SwiftData
import SwiftUI

struct RecordListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyRecord.measuredAt, order: .reverse) private var records: [BodyRecord]
    @State private var editing: BodyRecord?

    var body: some View {
        List {
            ForEach(records) { record in
                Button { editing = record } label: {
                    RecordRow(record: record)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for index in offsets {
                    let date = records[index].measuredAt
                    context.delete(records[index])
                    // このアプリがヘルスケアに書き込んだ値も消す。
                    Task { try? await HealthKitWriter.shared.delete(measuredAt: date) }
                }
            }
        }
        .sheet(item: $editing) { record in
            ConfirmView(editing: record)
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "記録がありません",
                    systemImage: "doc.text.viewfinder",
                    description: Text("右上のカメラボタンからレシートを撮影してください")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !records.isEmpty {
                Text("記録をタップすると修正、左にスワイプすると削除できます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct RecordRow: View {
    let record: BodyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.measuredAt, format: .dateTime.year().month().day().weekday().hour().minute())
                    .font(.subheadline)
                Spacer()
                if record.healthKitSynced {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .accessibilityLabel("ヘルスケアに書き込み済み")
                }
            }
            HStack(spacing: 16) {
                metric("体重", record.weight, "%.1f", "kg")
                metric("体脂肪率", record.fatPercent, "%.1f", "%")
                metric("内臓脂肪", record.visceralLevel, "%.0f", "")
                metric("筋肉量", record.muscleMass, "%.1f", "kg")
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ title: String, _ value: Double?, _ format: String, _ unit: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: format, $0) + unit } ?? "—")
                .font(.body.monospacedDigit())
        }
    }
}
