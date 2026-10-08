import BodyCompCore
import Foundation
import HealthKit

/// Apple Watch が記録した活動・睡眠・心拍のデータをヘルスケアから読み出し、日ごとに集計する。
final class HealthKitReader {
    static let shared = HealthKitReader()

    private let store = HKHealthStore()
    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType(),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// `start` の日から `end` の日までの日ごとの活動データ。
    func dailyActivities(from start: Date, to end: Date, zone2Range: ClosedRange<Double>?) async throws -> [DailyActivity] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!

        let steps = try await dailyStatistics(.stepCount, .count(), .cumulativeSum, startDay, endDay)
        let energy = try await dailyStatistics(.activeEnergyBurned, .kilocalorie(), .cumulativeSum, startDay, endDay)
        let exercise = try await dailyStatistics(.appleExerciseTime, .minute(), .cumulativeSum, startDay, endDay)
        let resting = try await dailyStatistics(
            .restingHeartRate, .count().unitDivided(by: .minute()), .discreteAverage, startDay, endDay
        )
        let hrv = try await dailyStatistics(
            .heartRateVariabilitySDNN, .secondUnit(with: .milli), .discreteAverage, startDay, endDay
        )
        let sleep = try await nightlySleep(startDay, endDay)
        let zone2 = try await dailyZone2Minutes(startDay, endDay, range: zone2Range)

        var days: [DailyActivity] = []
        var day = startDay
        while day < endDay {
            var activity = DailyActivity(date: day)
            activity.steps = steps[day]
            activity.activeEnergy = energy[day]
            activity.exerciseMinutes = exercise[day]
            activity.restingHeartRate = resting[day]
            activity.hrv = hrv[day]
            activity.sleepHours = sleep[day]
            // ワークアウトの記録がある日だけ Zone2 を数える。Apple Watch を着けていた日は 0 分として扱う。
            activity.zone2Minutes = zone2[day] ?? (exercise[day] != nil ? 0 : nil)
            days.append(activity)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    /// 直近 `days` 日間の安静時心拍の中央値（Zone2 の計算に使う）。
    func restingHeartRateMedian(days: Int = 30) async throws -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let samples = try await quantitySamples(.restingHeartRate, start, end)
        let values = samples.map { $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }
        return values.isEmpty ? nil : Trends.median(values)
    }

    func latestVO2Max() async throws -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -180, to: end)!
        let samples = try await quantitySamples(.vo2Max, start, end)
        return samples.last?.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
    }

    // MARK: - 個別の読み出し

    private func dailyStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        _ unit: HKUnit,
        _ options: HKStatisticsOptions,
        _ start: Date,
        _ end: Date
    ) async throws -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            ),
            options: options,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                result[Calendar.current.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return result
    }

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, _ start: Date, _ end: Date) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private func nightlySleep(_ start: Date, _ end: Date) async throws -> [Date: Double] {
        // 前日の夕方に始まった睡眠も含めるため、1日前から読む。
        let from = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: from, end: end)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let intervals = try await descriptor.result(for: store)
            .filter { asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return Sleep.nightlyHours(intervals).filter { $0.key >= start && $0.key < end }
    }

    /// ワークアウト中の心拍から、Zone2 の範囲にいた時間を日ごとに合計する。
    private func dailyZone2Minutes(_ start: Date, _ end: Date, range: ClosedRange<Double>?) async throws -> [Date: Double] {
        guard let range else { return [:] }
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)

        var result: [Date: Double] = [:]
        for workout in workouts {
            let samples = try await quantitySamples(.heartRate, workout.startDate, workout.endDate).map {
                Zone2.HeartRateSample(
                    date: $0.startDate,
                    bpm: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                )
            }
            let day = Calendar.current.startOfDay(for: workout.startDate)
            result[day, default: 0] += Zone2.minutes(samples, in: range)
        }
        return result
    }
}
