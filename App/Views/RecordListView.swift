import SwiftData
import SwiftUI

struct RecordListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyRecord.measuredAt, order: .reverse) private var records: [BodyRecord]

    var body: some View {
        List {
            ForEach(records) { record in
                RecordRow(record: record)
            }
            .onDelete { offsets in
                // ヘルスケアに書き込んだデータは消えない（ヘルスケア側で削除する）。
                for index in offsets {
                    context.delete(records[index])
                }
            }
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
