import BodyCompCore
import Foundation
import SwiftData

/// レシート1枚分、または手入力（体重・腹囲）の記録。日時が同じ記録は1件だけ持つ。
@Model
final class BodyRecord {
    @Attribute(.unique) var measuredAt: Date
    var age: Double?
    var height: Double?
    var clothes: Double?
    var weight: Double?
    var fatPercent: Double?
    var fatMass: Double?
    var leanMass: Double?
    var muscleMass: Double?
    var boneMass: Double?
    var bmr: Double?
    var visceralLevel: Double?
    var legScore: Double?
    var bmi: Double?
    var waist: Double?
    var skeletalMusclePercent: Double?
    var bodyType: String?
    /// 体組成計のレシートではなく、手入力した記録。
    var isManual: Bool = false
    /// 体組成を測った機器（ScaleDevice の rawValue）。体重・腹囲だけの手入力は "none"。
    var deviceRaw: String = ScaleDevice.tanita.rawValue
    var healthKitSynced: Bool = false
    var updatedAt: Date = Date()

    init(measurement: BodyMeasurement) {
        measuredAt = measurement.measuredAt ?? Date()
        apply(measurement)
    }

    func apply(_ m: BodyMeasurement) {
        measuredAt = m.measuredAt ?? measuredAt
        age = m[.age]
        height = m[.height]
        clothes = m[.clothes]
        weight = m[.weight]
        fatPercent = m[.fatPercent]
        fatMass = m[.fatMass]
        leanMass = m[.leanMass]
        muscleMass = m[.muscleMass]
        boneMass = m[.boneMass]
        bmr = m[.bmr]
        visceralLevel = m[.visceralLevel]
        legScore = m[.legScore]
        bmi = m[.bmi]
        waist = m[.waist]
        skeletalMusclePercent = m[.skeletalMusclePercent]
        bodyType = m.bodyType
        healthKitSynced = false
        updatedAt = Date()
    }

    func value(_ field: ReceiptField) -> Double? {
        switch field {
        case .age: age
        case .height: height
        case .clothes: clothes
        case .weight: weight
        case .fatPercent: fatPercent
        case .fatMass: fatMass
        case .leanMass: leanMass
        case .muscleMass: muscleMass
        case .boneMass: boneMass
        case .bmr: bmr
        case .visceralLevel: visceralLevel
        case .legScore: legScore
        case .bmi: bmi
        case .waist: waist
        case .skeletalMusclePercent: skeletalMusclePercent
        }
    }

    var measurement: BodyMeasurement {
        var m = BodyMeasurement(measuredAt: measuredAt, bodyType: bodyType)
        for field in ReceiptField.allCases {
            m[field] = value(field)
        }
        return m
    }
}

/// 体組成計の機種。機種によって計算方法が違うため、体重・腹囲以外の値は機種ごとに分けて扱う。
enum ScaleDevice: String, CaseIterable, Identifiable {
    case tanita, omron

    var id: Self { self }

    var displayName: String {
        switch self {
        case .tanita: "タニタ"
        case .omron: "オムロン"
        }
    }
}

extension BodyRecord {
    /// 体脂肪率や内臓脂肪レベルなど、機種によって変わる値を持つ記録か。
    var hasDeviceSpecificValues: Bool {
        ReceiptField.deviceSpecificFields.contains { value($0) != nil }
    }

    /// 体組成を測った機器。体重・腹囲だけの手入力は nil。
    var device: ScaleDevice? {
        get { ScaleDevice(rawValue: deviceRaw) }
        set { deviceRaw = newValue?.rawValue ?? "none" }
    }
}

extension Array where Element == BodyRecord {
    /// 指定した項目の値を、グラフや傾向の計算に使う形に変換する。
    /// 機種によって値が変わる項目は、`device` を指定するとその機種の記録だけにする。
    func points(_ field: ReceiptField, device: ScaleDevice? = nil) -> [DataPoint] {
        let filterByDevice = device != nil && ReceiptField.deviceSpecificFields.contains(field)
        return compactMap { record in
            if filterByDevice && record.device != device { return nil }
            return record.value(field).map { DataPoint(date: record.measuredAt, value: $0) }
        }
    }

    /// 最後に体組成（体重・腹囲以外）を測った機器。記録がなければタニタ。
    var currentDevice: ScaleDevice {
        filter(\.hasDeviceSpecificValues).max { $0.measuredAt < $1.measuredAt }?.device ?? .tanita
    }

    /// その機器で最初に体組成を測った日時（週次レポートの出発点に使う）。
    func firstMeasurement(of device: ScaleDevice) -> Date? {
        filter { $0.hasDeviceSpecificValues && $0.device == device }.map(\.measuredAt).min()
    }
}
