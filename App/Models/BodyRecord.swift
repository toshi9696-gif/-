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
}
