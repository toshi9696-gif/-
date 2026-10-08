import BodyCompCore
import Charts
import SwiftData
import SwiftUI

/// 目標（内臓脂肪レベル）までの進み具合と、体重・筋肉量の傾向をまとめて見る画面。
struct HomeView: View {
    @Query(sort: \BodyRecord.measuredAt) private var records: [BodyRecord]
    @AppStorage(SettingsKey.goalVisceral) private var goalVisceral = GoalDefaults.visceral
    @AppStorage(SettingsKey.goalMuscleFloor) private var goalMuscleFloor = GoalDefaults.muscleFloor
    @AppStorage(SettingsKey.goalDeadline) private var goalDeadline = GoalDefaults.deadline
    @Environment(ActivityModel.self) private var activity

    var body: some View {
        ScrollView {
            if records.isEmpty {
                ContentUnavailableView(
                    "記録がありません",
                    systemImage: "doc.text.viewfinder",
                    description: Text("右上のカメラボタンからレシートを撮影してください")
                )
                .padding(.top, 80)
            } else {
                VStack(spacing: 16) {
                    VisceralCard(
                        points: records.points(.visceralLevel),
                        goal: goalVisceral,
                        deadline: Date(timeIntervalSince1970: goalDeadline)
                    )
                    WeightCard(points: records.points(.weight))
                    MuscleCard(points: records.points(.muscleMass), floor: goalMuscleFloor)
                    ActivityCard(model: activity)
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 内臓脂肪レベル

private struct VisceralCard: View {
    let points: [DataPoint]
    let goal: Double
    let deadline: Date

    private var weekly: [DataPoint] { Trends.weeklyMedian(points) }

    /// 週の中央値が2週連続で目標以下なら達成とみなす。
    private var achieved: Bool {
        let lastTwo = weekly.suffix(2)
        return lastTwo.count == 2 && lastTwo.allSatisfy { $0.value <= goal }
    }

    private var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0)
    }

    var body: some View {
        Card(title: "内臓脂肪レベル", systemImage: "target") {
            if let current = weekly.last?.value {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text("今週").font(.caption).foregroundStyle(.secondary)
                        Text(format(current)).font(.system(size: 44, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("目標 \(format(goal)) 以下")
                        if let start = points.first?.value {
                            Text("開始時 \(format(start))").foregroundStyle(.secondary)
                        }
                        Text("期限まで \(daysLeft) 日").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                if achieved {
                    Label("2週連続で目標を達成しています", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if current > goal {
                    Text("目標まであと \(format(current - goal))")
                        .foregroundStyle(.orange)
                }

                if weekly.count >= 2 {
                    Chart {
                        ForEach(weekly, id: \.date) { point in
                            LineMark(x: .value("週", point.date), y: .value("レベル", point.value))
                                .interpolationMethod(.stepEnd)
                            PointMark(x: .value("週", point.date), y: .value("レベル", point.value))
                        }
                        RuleMark(y: .value("目標", goal))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 140)
                } else {
                    Text("2週間分の記録がたまると、週ごとの推移のグラフが表示されます")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("内臓脂肪レベルは日々±1程度ぶれるため、週ごとの中央値で判断します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - 体重

private struct WeightCard: View {
    let points: [DataPoint]

    private var average: [DataPoint] { Trends.movingAverage(points) }

    var body: some View {
        Card(title: "体重（7日平均）", systemImage: "scalemass") {
            if let latest = average.last, let first = average.first {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f kg", latest.value))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Spacer()
                    Text("開始時から \(signed(latest.value - first.value)) kg")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                RecentTrendChart(points: points, average: average, unit: "kg")
                Text("目安は月 −0.5kg 前後の緩やかな減少です。急に減らすと筋肉も落ちやすくなります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 筋肉量

private struct MuscleCard: View {
    let points: [DataPoint]
    let floor: Double

    private var average: [DataPoint] { Trends.movingAverage(points) }

    var body: some View {
        Card(title: "筋肉量（7日平均）", systemImage: "figure.strengthtraining.traditional") {
            if let latest = average.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f kg", latest.value))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Spacer()
                    Text(String(format: "下限 %.1f kg", floor))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                RecentTrendChart(points: points, average: average, unit: "kg", floor: floor)

                if let guardResult = MuscleGuard.evaluate(points), guardResult.isWarning {
                    Label(
                        "開始時から \(String(format: "%.1f", guardResult.drop)) kg 減っています。減量より、筋トレと食事量の維持を優先しましょう。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                } else if latest.value < floor {
                    Label("下限を下回っています。筋トレと食事量の維持を優先しましょう。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("筋肉量は維持できています", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - 今週の活動（Apple Watch）

private struct ActivityCard: View {
    let model: ActivityModel

    /// 仕様書の目安：中強度の有酸素運動を週150分。
    private let zone2WeeklyTarget = 150.0

    private var summary: WeeklyActivitySummary {
        WeeklyActivitySummary.make(model.days, weekContaining: Date())
    }

    var body: some View {
        Card(title: "今週の活動（Apple Watch）", systemImage: "applewatch") {
            if let error = model.errorMessage {
                Text("ヘルスケアのデータを読めませんでした：\(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if summary.dayCount == 0 {
                Text(model.isLoading ? "読み込み中…" : "今週のデータがありません。設定画面の「ヘルスケアへのアクセスを許可」から、読み取りを許可してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let zone2 = summary.zone2Minutes ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Zone2")
                        Spacer()
                        Text("\(Int(zone2)) / \(Int(zone2WeeklyTarget)) 分")
                            .font(.body.monospacedDigit())
                    }
                    ProgressView(value: min(zone2, zone2WeeklyTarget), total: zone2WeeklyTarget)
                        .tint(zone2 >= zone2WeeklyTarget ? .green : .blue)
                    if let range = model.zone2Range {
                        Text("Zone2 の心拍範囲：\(Int(range.lowerBound.rounded()))〜\(Int(range.upperBound.rounded())) bpm（ワークアウト中のみ集計）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        metric("歩数（1日平均）", summary.averageSteps.map { String(format: "%.0f 歩", $0) })
                        metric("エクササイズ（合計）", summary.exerciseMinutes.map { String(format: "%.0f 分", $0) })
                    }
                    GridRow {
                        metric("睡眠（平均）", summary.averageSleepHours.map { String(format: "%.1f 時間", $0) })
                        metric("安静時心拍（平均）", summary.averageRestingHeartRate.map { String(format: "%.0f bpm", $0) })
                    }
                    GridRow {
                        metric("HRV（平均）", summary.averageHRV.map { String(format: "%.0f ms", $0) })
                        metric("VO2max（最新）", model.vo2Max.map { String(format: "%.1f", $0) })
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").font(.body.monospacedDigit())
        }
    }
}

// MARK: - 共通部品

/// 直近30日の実測（点）と7日平均（線）。
private struct RecentTrendChart: View {
    let points: [DataPoint]
    let average: [DataPoint]
    let unit: String
    var floor: Double?

    var body: some View {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let recentPoints = points.filter { $0.date >= start }
        let recentAverage = average.filter { $0.date >= start }
        Chart {
            ForEach(recentPoints, id: \.date) { point in
                PointMark(x: .value("日付", point.date), y: .value(unit, point.value))
                    .foregroundStyle(.gray.opacity(0.5))
                    .symbolSize(20)
            }
            ForEach(recentAverage, id: \.date) { point in
                LineMark(x: .value("日付", point.date), y: .value(unit, point.value))
                    .interpolationMethod(.monotone)
            }
            if let floor {
                RuleMark(y: .value("下限", floor))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 120)
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private func signed(_ value: Double) -> String {
    String(format: "%+.1f", value).replacingOccurrences(of: "-", with: "−")
}
