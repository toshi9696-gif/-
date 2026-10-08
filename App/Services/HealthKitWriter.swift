import BodyCompCore
import Foundation
import HealthKit

/// 体重・体脂肪率・除脂肪量・BMI（初回のみ身長）をヘルスケアに書き込む。
/// 内臓脂肪レベルなど HealthKit に対応する型がない項目はアプリ内にだけ保存する。
final class HealthKitWriter {
    static let shared = HealthKitWriter()

    private let store = HKHealthStore()
    private let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.leanBodyMass),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.height),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    /// このアプリが指定日時の測定として書き込んだ値をヘルスケアから消す。
    func delete(measuredAt date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for identifier in Self.writtenIdentifiers {
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: [Self.syncID(date, identifier)]
            )
            _ = try await store.deleteObjects(of: HKQuantityType(identifier), predicate: predicate)
        }
    }

    private static let writtenIdentifiers: [HKQuantityTypeIdentifier] = [
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .height,
    ]

    private static func syncID(_ date: Date, _ identifier: HKQuantityTypeIdentifier) -> String {
        "tanita-\(Int(date.timeIntervalSince1970))-\(identifier.rawValue)"
    }

    func write(_ m: BodyMeasurement) async throws {
        guard HKHealthStore.isHealthDataAvailable(), let date = m.measuredAt else { return }
        try await requestAuthorization()

        // 同期 ID を測定日時から作り、同じレシートを上書き保存したときはヘルスケア側も置き換える。
        let version = Int(Date().timeIntervalSince1970)
        var samples: [HKQuantitySample] = []
        func add(_ identifier: HKQuantityTypeIdentifier, _ value: Double?, _ unit: HKUnit) {
            guard let value else { return }
            let syncID = Self.syncID(date, identifier)
            samples.append(HKQuantitySample(
                type: HKQuantityType(identifier),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date,
                metadata: [HKMetadataKeySyncIdentifier: syncID, HKMetadataKeySyncVersion: version]
            ))
        }

        add(.bodyMass, m[.weight], .gramUnit(with: .kilo))
        add(.bodyFatPercentage, m[.fatPercent].map { $0 / 100 }, .percent())
        add(.leanBodyMass, m[.leanMass], .gramUnit(with: .kilo))
        add(.bodyMassIndex, m[.bmi], .count())

        let defaults = UserDefaults.standard
        let writesHeight = !defaults.bool(forKey: SettingsKey.heightWrittenToHealth) && m[.height] != nil
        if writesHeight {
            add(.height, m[.height], .meterUnit(with: .centi))
        }

        guard !samples.isEmpty else { return }
        try await store.save(samples)
        if writesHeight {
            defaults.set(true, forKey: SettingsKey.heightWrittenToHealth)
        }
    }
}
