import Foundation

/// Apple Watch / ヘルスケアから集計した1日分の活動データ。値がない日は nil。
public struct DailyActivity: Equatable, Sendable {
    /// その日の 0:00。
    public var date: Date
    public var steps: Double?
    public var activeEnergy: Double?
    public var exerciseMinutes: Double?
    public var zone2Minutes: Double?
    public var restingHeartRate: Double?
    public var hrv: Double?
    /// その日の朝に目覚めた夜の睡眠時間。
    public var sleepHours: Double?

    public init(date: Date) {
        self.date = date
    }

    public func value(_ metric: ActivityMetric) -> Double? {
        switch metric {
        case .steps: steps
        case .activeEnergy: activeEnergy
        case .exercise: exerciseMinutes
        case .zone2: zone2Minutes
        case .restingHeartRate: restingHeartRate
        case .hrv: hrv
        case .sleep: sleepHours
        }
    }
}

public enum ActivityMetric: String, CaseIterable, Hashable, Sendable {
    case steps, zone2, exercise, activeEnergy, sleep, restingHeartRate, hrv

    public var displayName: String {
        switch self {
        case .steps: "歩数"
        case .zone2: "Zone2"
        case .exercise: "エクササイズ"
        case .activeEnergy: "アクティブエネルギー"
        case .sleep: "睡眠"
        case .restingHeartRate: "安静時心拍"
        case .hrv: "心拍変動（HRV）"
        }
    }

    public var unit: String {
        switch self {
        case .steps: "歩"
        case .zone2, .exercise: "分"
        case .activeEnergy: "kcal"
        case .sleep: "時間"
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        }
    }

    /// 1日の合計を表す項目（棒グラフで表示する）。それ以外は平均値（折れ線で表示する）。
    public var isDailyTotal: Bool {
        switch self {
        case .steps, .zone2, .exercise, .activeEnergy, .sleep: true
        case .restingHeartRate, .hrv: false
        }
    }

    public func format(_ value: Double) -> String {
        switch self {
        case .sleep: String(format: "%.1f", value)
        default: String(format: "%.0f", value)
        }
    }
}

/// Zone2（脂肪が燃えやすい中強度）の心拍範囲と、その範囲にいた時間。
public enum Zone2 {
    public struct HeartRateSample: Equatable, Sendable {
        public var date: Date
        public var bpm: Double

        public init(date: Date, bpm: Double) {
            self.date = date
            self.bpm = bpm
        }
    }

    /// カルボーネン法：安静時心拍 + (最大心拍 − 安静時心拍) × 60〜70%。最大心拍は 220 − 年齢。
    public static func heartRateRange(age: Int, restingHeartRate: Double) -> ClosedRange<Double> {
        let reserve = Double(220 - age) - restingHeartRate
        return (restingHeartRate + reserve * 0.6)...(restingHeartRate + reserve * 0.7)
    }

    /// 連続する心拍サンプルの間隔のうち、始点が範囲内のものを合計する。
    /// 間隔が `maxGap` 秒より長い部分（計測が途切れた部分）は数えない。
    public static func minutes(
        _ samples: [HeartRateSample],
        in range: ClosedRange<Double>,
        maxGap: TimeInterval = 120
    ) -> Double {
        let sorted = samples.sorted { $0.date < $1.date }
        var seconds = 0.0
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            if gap <= maxGap, range.contains(current.bpm) {
                seconds += gap
            }
        }
        return seconds / 60
    }
}

public enum Sleep {
    /// 重なりをまとめた合計時間（Apple Watch と iPhone の両方に記録がある場合の二重計上を防ぐ）。
    public static func totalDuration(_ intervals: [DateInterval]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let merged = current, interval.start <= merged.end {
                current = DateInterval(start: merged.start, end: max(merged.end, interval.end))
            } else {
                total += current?.duration ?? 0
                current = interval
            }
        }
        return total + (current?.duration ?? 0)
    }

    /// 起床日ごとの睡眠時間（時間）。前日 18:00 〜 当日 18:00 に始まった睡眠を、当日の分として数える。
    public static func nightlyHours(_ intervals: [DateInterval], calendar: Calendar = .current) -> [Date: Double] {
        let nights = Dictionary(grouping: intervals) {
            calendar.startOfDay(for: $0.start.addingTimeInterval(6 * 3600))
        }
        return nights.mapValues { totalDuration($0) / 3600 }
    }
}

/// 1週間（月曜始まり）の活動のまとめ。合計系は週の合計、それ以外は記録のある日の平均。
public struct WeeklyActivitySummary: Equatable, Sendable {
    public var dayCount = 0
    public var averageSteps: Double?
    public var zone2Minutes: Double?
    public var exerciseMinutes: Double?
    public var averageSleepHours: Double?
    public var averageRestingHeartRate: Double?
    public var averageHRV: Double?

    public init() {}

    public static func make(
        _ days: [DailyActivity],
        weekContaining date: Date,
        calendar: Calendar = .current
    ) -> WeeklyActivitySummary {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return WeeklyActivitySummary() }
        let inWeek = days.filter { week.contains($0.date) && $0.date < week.end }

        func average(_ metric: ActivityMetric) -> Double? {
            let values = inWeek.compactMap { $0.value(metric) }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func total(_ metric: ActivityMetric) -> Double? {
            let values = inWeek.compactMap { $0.value(metric) }
            return values.isEmpty ? nil : values.reduce(0, +)
        }

        var summary = WeeklyActivitySummary()
        summary.dayCount = inWeek.count
        summary.averageSteps = average(.steps)
        summary.zone2Minutes = total(.zone2)
        summary.exerciseMinutes = total(.exercise)
        summary.averageSleepHours = average(.sleep)
        summary.averageRestingHeartRate = average(.restingHeartRate)
        summary.averageHRV = average(.hrv)
        return summary
    }
}
