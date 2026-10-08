import XCTest
@testable import BodyCompCore

final class WeeklyReportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testBuildsWeeklyAggregatesWithoutDailyValues() throws {
        let body: [ReceiptField: [DataPoint]] = [
            .weight: [DataPoint(date: date(10, 5), value: 64.8), DataPoint(date: date(10, 7), value: 64.8)],
            .visceralLevel: [DataPoint(date: date(10, 5), value: 11), DataPoint(date: date(10, 7), value: 12)],
            .muscleMass: [DataPoint(date: date(10, 5), value: 50.8), DataPoint(date: date(10, 7), value: 50.8)],
        ]
        var monday = DailyActivity(date: calendar.startOfDay(for: date(10, 5)))
        monday.steps = 9000
        monday.zone2Minutes = 0
        let deadline = calendar.date(from: DateComponents(year: 2027, month: 3, day: 31))!

        let input = WeeklyReportBuilder.make(
            body: body, activity: [monday], age: 59, goalVisceral: 9, goalMuscle: 50.5,
            deadline: deadline, zone2Range: 120.4...130.4, vo2Max: 31.74,
            today: date(10, 8, hour: 12), calendar: calendar
        )

        XCTAssertEqual(input.reportWeekStart, "2026-10-05")
        XCTAssertEqual(input.goals.daysLeft, 174)
        XCTAssertEqual(input.bodyWeeks.count, 1)
        let week = try XCTUnwrap(input.bodyWeeks.first)
        XCTAssertEqual(week.measurementDays, 2)
        XCTAssertEqual(week.visceralLevelMedian, 11.5)
        XCTAssertEqual(week.weightKgAverage, 64.8)
        XCTAssertEqual(week.muscleMassKgAverage, 50.8)
        XCTAssertEqual(input.baselineWeek, week)
        XCTAssertEqual(input.activityWeeks.map(\.stepsPerDay), [9000])
        XCTAssertEqual(input.zone2RangeBpm, [120, 130])
        XCTAssertEqual(input.vo2Max, 31.7)
        XCTAssertEqual(input.muscleCheck?.warning, false)

        // 送る JSON に日ごとの日時が含まれないこと。
        let json = String(data: try JSONEncoder().encode(input), encoding: .utf8)!
        XCTAssertFalse(json.contains("2026-10-07"))
    }
}
