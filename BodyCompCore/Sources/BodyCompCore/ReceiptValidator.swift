import Foundation

public struct ValidationIssue: Equatable, Sendable {
    public let fields: Set<ReceiptField>
    public let message: String

    public init(fields: Set<ReceiptField>, message: String) {
        self.fields = fields
        self.message = message
    }
}

/// レシートの数値どうしの整合性を確かめる。値は互いに計算で検証できるため、OCR の読み間違いを検出できる。
public enum ReceiptValidator {
    public static func validate(
        _ m: BodyMeasurement,
        birthday: Date? = nil,
        calendar: Calendar = .current
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if m.measuredAt == nil {
            issues.append(ValidationIssue(fields: [], message: "日時を読み取れませんでした"))
        }

        let missing = ReceiptField.allCases.filter { m[$0] == nil }
        if !missing.isEmpty {
            let names = missing.map(\.displayName).joined(separator: "・")
            issues.append(ValidationIssue(fields: Set(missing), message: "読み取れなかった項目: \(names)"))
        }

        for field in ReceiptField.allCases {
            guard let value = m[field], !field.validRange.contains(value) else { continue }
            issues.append(ValidationIssue(
                fields: [field],
                message: "\(field.displayName)（\(field.format(value))）が想定範囲外です"
            ))
        }

        func check(_ computed: Double?, _ printed: Double?, tolerance: Double,
                   _ fields: Set<ReceiptField>, _ message: (Double, Double) -> String) {
            guard let computed, let printed, abs(computed - printed) > tolerance + 1e-9 else { return }
            issues.append(ValidationIssue(fields: fields, message: message(computed, printed)))
        }

        if let fat = m[.fatMass], let lean = m[.leanMass] {
            check(fat + lean, m[.weight], tolerance: 0.2, [.fatMass, .leanMass, .weight]) {
                "脂肪量 + 除脂肪量（\(String(format: "%.1f", $0))kg）が体重（\(String(format: "%.1f", $1))kg）と合いません"
            }
        }
        if let fat = m[.fatMass], let weight = m[.weight], weight > 0 {
            check(fat / weight * 100, m[.fatPercent], tolerance: 0.3, [.fatMass, .weight, .fatPercent]) {
                "脂肪量 ÷ 体重（\(String(format: "%.1f", $0))%）が体脂肪率（\(String(format: "%.1f", $1))%）と合いません"
            }
        }
        if let muscle = m[.muscleMass], let bone = m[.boneMass] {
            check(muscle + bone, m[.leanMass], tolerance: 0.2, [.muscleMass, .boneMass, .leanMass]) {
                "筋肉量 + 推定骨量（\(String(format: "%.1f", $0))kg）が除脂肪量（\(String(format: "%.1f", $1))kg）と合いません"
            }
        }
        if let weight = m[.weight], let height = m[.height], height > 0 {
            let meters = height / 100
            check(weight / (meters * meters), m[.bmi], tolerance: 0.2, [.weight, .height, .bmi]) {
                "体重 ÷ 身長²（\(String(format: "%.1f", $0))）が BMI（\(String(format: "%.1f", $1))）と合いません"
            }
        }

        if let birthday, let measuredAt = m.measuredAt, let age = m[.age],
           let expected = calendar.dateComponents([.year], from: birthday, to: measuredAt).year,
           Int(age) != expected {
            issues.append(ValidationIssue(
                fields: [.age],
                message: "レシートの年齢（\(Int(age))才）が誕生日から計算した年齢（\(expected)才）と違います"
            ))
        }

        return issues
    }
}
