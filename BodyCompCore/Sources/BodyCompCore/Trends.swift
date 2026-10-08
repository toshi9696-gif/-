import Foundation

public struct DataPoint: Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// 毎日の測定値から傾向を計算する。体組成計の値は日々ぶれるため、判断には平均や中央値を使う。
public enum Trends {
    /// 1日に複数の測定があるときは、その日の最後の測定を代表値にする。
    public static func dailyLatest(_ points: [DataPoint], calendar: Calendar = .current) -> [DataPoint] {
        var byDay: [Date: DataPoint] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.date)
            if let existing = byDay[day], existing.date >= point.date { continue }
            byDay[day] = point
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 各測定日について、その日を含む直近 `days` 日間の平均を返す（測定のない日は除いて計算する）。
    public static func movingAverage(_ points: [DataPoint], days: Int = 7, calendar: Calendar = .current) -> [DataPoint] {
        let daily = dailyLatest(points, calendar: calendar)
        return daily.map { point in
            let end = calendar.startOfDay(for: point.date)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: end)!
            let window = daily.filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= start && day <= end
            }
            return DataPoint(date: point.date, value: window.map(\.value).reduce(0, +) / Double(window.count))
        }
    }

    /// 週（月曜始まり）ごとの中央値を返す。日付は週の初日。
    public static func weeklyMedian(_ points: [DataPoint], calendar: Calendar = .current) -> [DataPoint] {
        var calendar = calendar
        calendar.firstWeekday = 2
        let daily = dailyLatest(points, calendar: calendar)
        let weeks = Dictionary(grouping: daily) { calendar.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        return weeks
            .map { DataPoint(date: $0.key, value: median($0.value.map(\.value))) }
            .sorted { $0.date < $1.date }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// 筋肉量が落ちていないかの判定。最初の7日間の平均と、直近の7日平均を比べる。
public struct MuscleGuard: Equatable, Sendable {
    public static let threshold = 1.0

    public let baseline: Double
    public let current: Double

    public var drop: Double { baseline - current }
    public var isWarning: Bool { drop >= Self.threshold - 1e-9 }

    public static func evaluate(_ points: [DataPoint], calendar: Calendar = .current) -> MuscleGuard? {
        let daily = Trends.dailyLatest(points, calendar: calendar)
        guard let first = daily.first,
              let latest = Trends.movingAverage(daily, calendar: calendar).last else { return nil }
        let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: first.date))!
        let baseline = daily.filter { $0.date < end }.map(\.value)
        return MuscleGuard(baseline: baseline.reduce(0, +) / Double(baseline.count), current: latest.value)
    }
}
