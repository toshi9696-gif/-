import BodyCompCore
import Foundation
import SwiftData

/// レシート1枚分の記録。日時が同じ記録は1件だけ持つ。
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
    var bodyType: String?
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

extension Array where Element == BodyRecord {
    /// 指定した項目の値を、グラフや傾向の計算に使う形に変換する。
    func points(_ field: ReceiptField) -> [DataPoint] {
        compactMap { record in
            record.value(field).map { DataPoint(date: record.measuredAt, value: $0) }
        }
    }
}
