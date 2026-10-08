import BodyCompCore
import Charts
import SwiftData
import SwiftUI

enum ChartPeriod: String, CaseIterable, Identifiable {
    case month1 = "1か月"
    case month3 = "3か月"
    case month6 = "6か月"
    case all = "全期間"

    var id: Self { self }

    var days: Int? {
        switch self {
        case .month1: 31
        case .month3: 92
        case .month6: 183
        case .all: nil
        }
    }
}

/// 体組成の各項目の推移。点が毎日の実測、線が傾向（7日平均、内臓脂肪レベルは週の中央値）。
struct ChartsView: View {
    @Query(sort: \BodyRecord.measuredAt) private var records: [BodyRecord]
    @AppStorage(SettingsKey.goalVisceral) private var goalVisceral = GoalDefaults.visceral
    @AppStorage(SettingsKey.goalMuscleFloor) private var goalMuscleFloor = GoalDefaults.muscleFloor
    @AppStorage(SettingsKey.birthdayEnabled) private var birthdayEnabled = false
    @AppStorage(SettingsKey.birthday) private var birthdayInterval: Double = 0

    @State private var field: ReceiptField = .visceralLevel
    @State private var period: ChartPeriod = .month1

    private let fields: [ReceiptField] = [
        .visceralLevel, .weight, .fatPercent, .muscleMass, .fatMass, .bmr, .legScore, .bmi,
    ]

    private var points: [DataPoint] {
        let all = records.points(field)
        guard let days = period.days,
              let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return all }
        return all.filter { $0.date >= start }
    }

    private var trend: [DataPoint] {
        field == .visceralLevel ? Trends.weeklyMedian(points) : Trends.movingAverage(points)
    }

    private var goal: (label: String, value: Double)? {
        switch field {
        case .visceralLevel: ("目標", goalVisceral)
        case .muscleMass: ("下限", goalMuscleFloor)
        default: nil
        }
    }

    /// 期間内の誕生日。TANITA の推定値は年齢で変わるため、前後の段差は体の変化ではない可能性がある。
    private var birthdays: [Date] {
        guard birthdayEnabled, let first = points.first?.date, let last = points.last?.date else { return [] }
        let calendar = Calendar.current
        let birthday = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: birthdayInterval))
        let years = calendar.component(.year, from: first)...calendar.component(.year, from: last)
        return years.compactMap {
            calendar.date(from: DateComponents(year: $0, month: birthday.month, day: birthday.day))
        }
        .filter { $0 >= first && $0 <= last }
    }

    var body: some View {
        List {
            Section {
                Picker("項目", selection: $field) {
                    ForEach(fields, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("期間", selection: $period) {
                    ForEach(ChartPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if points.isEmpty {
                    Text("この期間の記録がありません")
                        .foregroundStyle(.secondary)
                } else {
                    chart.frame(height: 280)
                }
            } footer: {
                Text(field == .visceralLevel
                     ? "点は毎日の測定値、線は週ごとの中央値です。内臓脂肪レベルは整数でしか変わらず日々ぶれるため、週単位で判断します。"
                     : "点は毎日の測定値、線は7日間の平均です。1日ごとの上下ではなく、線の向きを見てください。")
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points, id: \.date) { point in
                PointMark(x: .value("日付", point.date), y: .value(field.displayName, point.value))
                    .foregroundStyle(.gray.opacity(0.5))
                    .symbolSize(24)
            }
            ForEach(trend, id: \.date) { point in
                LineMark(x: .value("日付", point.date), y: .value(field.displayName, point.value))
                    .interpolationMethod(field == .visceralLevel ? .stepEnd : .monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let goal {
                RuleMark(y: .value(goal.label, goal.value))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(goal.label) \(field.format(goal.value))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
            }
            ForEach(birthdays, id: \.self) { date in
                RuleMark(x: .value("誕生日", date))
                    .foregroundStyle(.orange.opacity(0.6))
                    .annotation(position: .top) {
                        Text("年齢更新").font(.caption2).foregroundStyle(.orange)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
