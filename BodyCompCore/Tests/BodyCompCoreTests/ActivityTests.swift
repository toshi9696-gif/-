import XCTest
@testable import BodyCompCore

final class ActivityTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testZone2RangeMatchesSpecExample() {
        // 仕様書の例：59歳・安静時心拍 60 → 121〜131 bpm
        let range = Zone2.heartRateRange(age: 59, restingHeartRate: 60)
        XCTAssertEqual(range.lowerBound, 120.6, accuracy: 1e-9)
        XCTAssertEqual(range.upperBound, 130.7, accuracy: 1e-9)
    }

    func testZone2MinutesSkipsGapsAndOutOfRangeSamples() {
        let start = date(day: 12, hour: 7)
        // 1分ごとに 10 サンプル（125bpm）→ 9分。その後 140bpm が 3 サンプル → 数えない。
        var samples = (0..<10).map { Zone2.HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: 125) }
        samples += (10..<13).map { Zone2.HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: 140) }
        // 1時間後に範囲内のサンプルが1つ → 間隔が長すぎるので数えない。
        samples.append(Zone2.HeartRateSample(date: start.addingTimeInterval(3600), bpm: 125))
        let minutes = Zone2.minutes(samples, in: 120.6...130.7)
        XCTAssertEqual(minutes, 10, accuracy: 1e-9) // 9分 + 125→140 の境目の1分
    }

    func testSleepMergesOverlapsAndAssignsToWakeDay() {
        let watch = DateInterval(start: date(day: 11, hour: 23), end: date(day: 12, hour: 6))
        let phone = DateInterval(start: date(day: 12, hour: 1), end: date(day: 12, hour: 6, minute: 30))
        let nap = DateInterval(start: date(day: 12, hour: 14), end: date(day: 12, hour: 14, minute: 30))
        let nights = Sleep.nightlyHours([watch, phone, nap], calendar: calendar)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[calendar.startOfDay(for: date(day: 12, hour: 0))] ?? 0, 8.0, accuracy: 1e-9)
    }

    func testWeeklySummaryAveragesAndTotals() {
        var monday = DailyActivity(date: date(day: 12, hour: 0))
        monday.steps = 8000
        monday.zone2Minutes = 30
        monday.sleepHours = 7
        var tuesday = DailyActivity(date: date(day: 13, hour: 0))
        tuesday.steps = 6000
        tuesday.zone2Minutes = 20
        var nextMonday = DailyActivity(date: date(day: 19, hour: 0))
        nextMonday.steps = 20000

        let summary = WeeklyActivitySummary.make([monday, tuesday, nextMonday], weekContaining: date(day: 15, hour: 12), calendar: calendar)
        XCTAssertEqual(summary.dayCount, 2)
        XCTAssertEqual(summary.averageSteps, 7000)
        XCTAssertEqual(summary.zone2Minutes, 50)
        XCTAssertEqual(summary.averageSleepHours, 7)
        XCTAssertNil(summary.averageHRV)
    }
}
