import XCTest
@testable import BodyCompCore

final class TrendsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 2026-10-05（月）を基準に、日数と時刻を指定した測定値を作る。
    private func point(day: Int, hour: Int = 21, _ value: Double) -> DataPoint {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + day, hour: hour))!
        return DataPoint(date: date, value: value)
    }

    func testDailyLatestKeepsLastMeasurementOfTheDay() {
        let daily = Trends.dailyLatest([point(day: 0, hour: 7, 65.2), point(day: 0, hour: 21, 64.8)], calendar: calendar)
        XCTAssertEqual(daily.map(\.value), [64.8])
    }

    func testMovingAverageUsesOnlyTheLastSevenDays() {
        let points = [point(day: 0, 64.8), point(day: 1, 65.0), point(day: 2, 64.6), point(day: 9, 64.0)]
        let averages = Trends.movingAverage(points, calendar: calendar).map(\.value)
        XCTAssertEqual(averages.count, 4)
        XCTAssertEqual(averages[2], 64.8, accuracy: 1e-9)
        XCTAssertEqual(averages[3], 64.0, accuracy: 1e-9)
    }

    func testWeeklyMedianGroupsByMondayStartWeeks() {
        let points = [point(day: 0, 11), point(day: 1, 12), point(day: 6, 11), point(day: 7, 12), point(day: 8, 10)]
        let weekly = Trends.weeklyMedian(points, calendar: calendar)
        XCTAssertEqual(weekly.map(\.value), [11, 11])
        XCTAssertEqual(weekly.first?.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
    }

    func testMuscleGuardWarnsAfterOneKilogramDrop() throws {
        var points = (0..<3).map { point(day: $0, 51.0) }
        points += (20..<27).map { point(day: $0, 49.8) }
        let result = try XCTUnwrap(MuscleGuard.evaluate(points, calendar: calendar))
        XCTAssertEqual(result.baseline, 51.0, accuracy: 1e-9)
        XCTAssertEqual(result.current, 49.8, accuracy: 1e-9)
        XCTAssertTrue(result.isWarning)

        let stable = try XCTUnwrap(MuscleGuard.evaluate([point(day: 0, 51.0), point(day: 20, 50.7)], calendar: calendar))
        XCTAssertFalse(stable.isWarning)
    }
}
