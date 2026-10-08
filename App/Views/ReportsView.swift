import BodyCompCore
import SwiftData
import SwiftUI

/// Claude による週次レポートの作成と一覧。
struct ReportsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActivityModel.self) private var activity
    @Query(sort: \WeeklyReport.weekStart, order: .reverse) private var reports: [WeeklyReport]
    @Query(sort: \BodyRecord.measuredAt) private var records: [BodyRecord]
    @AppStorage(SettingsKey.goalVisceral) private var goalVisceral = GoalDefaults.visceral
    @AppStorage(SettingsKey.goalMuscleFloor) private var goalMuscleFloor = GoalDefaults.muscleFloor
    @AppStorage(SettingsKey.goalDeadline) private var goalDeadline = GoalDefaults.deadline

    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        HStack {
                            ProgressView()
                            Text("作成中…（1分ほどかかります）")
                        }
                    } else {
                        Label("今週のレポートを作成", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating || records.isEmpty)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Claude に送るのは、週ごとに集計した体組成と活動の値と目標だけです。日ごとの値や名前は送りません。同じ週に作り直すと上書きされます。")
            }

            if !reports.isEmpty {
                Section("これまでのレポート") {
                    ForEach(reports) { report in
                        NavigationLink {
                            ReportDetailView(report: report)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weekLabel(report.weekStart)).font(.headline)
                                if let summary = report.content?.summary {
                                    Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(reports[index]) }
                    }
                }
            }
        }
    }

    private func generate() async {
        guard let apiKey = Keychain.load(account: Keychain.claudeAPIKey), !apiKey.isEmpty else {
            errorMessage = ClaudeError.missingAPIKey.localizedDescription
            return
        }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let fields: [ReceiptField] = [.weight, .fatPercent, .fatMass, .muscleMass, .visceralLevel]
        let input = WeeklyReportBuilder.make(
            body: Dictionary(uniqueKeysWithValues: fields.map { ($0, records.points($0)) }),
            activity: activity.days,
            age: records.last?.age.map { Int($0) },
            goalVisceral: goalVisceral,
            goalMuscle: goalMuscleFloor,
            deadline: Date(timeIntervalSince1970: goalDeadline),
            zone2Range: activity.zone2Range,
            vo2Max: activity.vo2Max,
            today: Date()
        )
        do {
            let content = try await ClaudeClient(apiKey: apiKey).weeklyReport(for: input)
            var calendar = Calendar.current
            calendar.firstWeekday = 2
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
            if let existing = reports.first(where: { $0.weekStart == weekStart }) {
                existing.update(model: ClaudeClient.model, content: content, input: input)
            } else {
                context.insert(WeeklyReport(weekStart: weekStart, model: ClaudeClient.model, content: content, input: input))
            }
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReportDetailView: View {
    let report: WeeklyReport

    var body: some View {
        List {
            if let content = report.content {
                Section("今週の評価") {
                    Text(content.summary)
                }
                if !content.notableChanges.isEmpty {
                    Section("目立った変化") {
                        ForEach(content.notableChanges, id: \.self) { change in
                            Label(change, systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                Section("来週の重点") {
                    ForEach(Array(content.focus.enumerated()), id: \.offset) { index, focus in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(focus.title)").font(.headline)
                            Text(focus.detail)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Text("レポートを読み込めませんでした")
            }

            Section {
                DisclosureGroup("Claude に送ったデータ") {
                    Text(report.inputJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("\(report.createdAt.formatted(date: .abbreviated, time: .shortened)) 作成（\(report.modelName)）。医療的な診断ではありません。")
            }
        }
        .navigationTitle(weekLabel(report.weekStart))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func weekLabel(_ weekStart: Date) -> String {
    let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
    return "\(weekStart.formatted(.dateTime.month().day()))〜\(end.formatted(.dateTime.month().day())) の週"
}
