import Foundation

/// TANITA DC-430A のレシートに印字される数値項目。
public enum ReceiptField: String, CaseIterable, Hashable, Sendable {
    case age, height, clothes
    case weight, fatPercent, fatMass, leanMass, muscleMass, boneMass, bmr, visceralLevel, legScore, bmi

    public static let inputFields: [ReceiptField] = [.age, .height, .clothes]
    public static let resultFields: [ReceiptField] = [
        .weight, .fatPercent, .fatMass, .leanMass, .muscleMass, .boneMass, .bmr, .visceralLevel, .legScore, .bmi,
    ]

    public var displayName: String {
        switch self {
        case .age: "年齢"
        case .height: "身長"
        case .clothes: "着衣量"
        case .weight: "体重"
        case .fatPercent: "体脂肪率"
        case .fatMass: "脂肪量"
        case .leanMass: "除脂肪量"
        case .muscleMass: "筋肉量"
        case .boneMass: "推定骨量"
        case .bmr: "基礎代謝量"
        case .visceralLevel: "内臓脂肪レベル"
        case .legScore: "脚点"
        case .bmi: "BMI"
        }
    }

    public var unit: String {
        switch self {
        case .age: "才"
        case .height: "cm"
        case .clothes, .weight, .fatMass, .leanMass, .muscleMass, .boneMass: "kg"
        case .fatPercent: "%"
        case .bmr: "kcal"
        case .legScore: "点"
        case .visceralLevel, .bmi: ""
        }
    }

    public var fractionDigits: Int {
        switch self {
        case .age, .bmr, .visceralLevel, .legScore: 0
        default: 1
        }
    }

    /// 明らかな読み間違いを弾くための範囲。
    public var validRange: ClosedRange<Double> {
        switch self {
        case .age: 5...99
        case .height: 90...220
        case .clothes: 0...5
        case .weight: 30...150
        case .fatPercent: 3...60
        case .fatMass: 1...100
        case .leanMass: 20...120
        case .muscleMass: 15...110
        case .boneMass: 1...6
        case .bmr: 600...4000
        case .visceralLevel: 1...59
        case .legScore: 0...200
        case .bmi: 10...60
        }
    }

    /// レシート上の項目名（空白を除いた形）。OCR でよく起きる読み違いも含める。
    var receiptLabels: [String] {
        switch self {
        case .age: ["年令", "年齢"]
        case .height: ["身長"]
        case .clothes: ["着衣量"]
        case .weight: ["体重"]
        case .fatPercent: ["体脂肪率"]
        case .fatMass: ["脂肪量"]
        case .leanMass: ["除脂肪量"]
        case .muscleMass: ["筋肉量"]
        case .boneMass: ["推定骨量"]
        case .bmr: ["基礎代謝量"]
        case .visceralLevel: ["内臓脂肪レベル"]
        case .legScore: ["脚点"]
        case .bmi: ["BMI", "BMl", "BM1"]
        }
    }

    public func format(_ value: Double) -> String {
        String(format: "%.\(fractionDigits)f", value)
    }
}

/// レシート1枚分の測定値。
public struct BodyMeasurement: Equatable, Sendable {
    public var measuredAt: Date?
    public var bodyType: String?
    public private(set) var values: [ReceiptField: Double]

    public init(measuredAt: Date? = nil, values: [ReceiptField: Double] = [:], bodyType: String? = nil) {
        self.measuredAt = measuredAt
        self.values = values
        self.bodyType = bodyType
    }

    public subscript(field: ReceiptField) -> Double? {
        get { values[field] }
        set { values[field] = newValue }
    }
}
