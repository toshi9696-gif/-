import XCTest
@testable import BodyCompCore

final class ReceiptParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 2026-09-30 のレシートを、等幅印字の空白を含めて書き起こしたもの。
    private let sampleRows = [
        "TANITA",
        "体組成計",
        "DC-430A",
        "2026/09/30(水)21:25",
        "氏名",
        "入力項目",
        "体型モード スタンダード",
        "性別 男性",
        "年令 5 9 才",
        "身長 1 6 7. 0 cm",
        "着衣量 (PT) 0. 5 kg",
        "測定結果",
        "体重 6 4. 8 kg",
        "体脂肪率 1 6. 8 %",
        "脂肪量 1 0. 9 kg",
        "除脂肪量 5 3. 9 kg",
        "筋肉量 5 1. 1 kg",
        "推定骨量 2. 8 kg",
        "基礎代謝量 1 4 5 9 kcal",
        "内臓脂肪レベル 1 1",
        "脚点 9 6 点",
        "BMI 2 3. 2",
        "判定",
        "◇体脂肪率",
        "やせ |標 準|軽肥満|肥満",
        "◇BMI",
        "やせ |普 通|肥満1|肥満2",
        "◇内臓脂肪レベル",
        "標 準 |やや過剰| 過剰",
        "◇筋肉量",
        "少 | 平均 | 多",
        "◇基礎代謝レベル",
        "燃えにくい|標 準|燃えやすい",
        "◇脚点",
        "低 |やや低| 良",
        "◇体脂肪率と筋肉量による体型判定",
        "☆標準☆",
    ]

    func testParsesSampleReceipt() throws {
        let m = ReceiptParser.parse(rows: sampleRows, calendar: calendar)

        let expected: [ReceiptField: Double] = [
            .age: 59, .height: 167.0, .clothes: 0.5,
            .weight: 64.8, .fatPercent: 16.8, .fatMass: 10.9, .leanMass: 53.9, .muscleMass: 51.1,
            .boneMass: 2.8, .bmr: 1459, .visceralLevel: 11, .legScore: 96, .bmi: 23.2,
        ]
        XCTAssertEqual(m.values, expected)
        XCTAssertEqual(m.bodyType, "標準")

        let date = try XCTUnwrap(m.measuredAt)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 30, 21, 25])

        XCTAssertEqual(ReceiptValidator.validate(m, calendar: calendar), [])
    }

    func testCorrectsLookalikeCharacters() {
        let m = ReceiptParser.parse(rows: [
            "体重 6O. 5 kg",
            "基礎代謝量 1 4 5 9 kca1",
            "BMl 2 3. 2",
            "内臓脂肪レベル l l",
        ], calendar: calendar)
        XCTAssertEqual(m[.weight], 60.5)
        XCTAssertEqual(m[.bmr], 1459)
        XCTAssertEqual(m[.bmi], 23.2)
        XCTAssertEqual(m[.visceralLevel], 11)
    }

    func testFullWidthCharactersAndDateWithMisreadWeekday() throws {
        let m = ReceiptParser.parse(rows: ["２０２６/０９/３０(7k)２１:２５", "体重 ６４．８ ｋｇ"], calendar: calendar)
        XCTAssertEqual(m[.weight], 64.8)
        let c = calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(m.measuredAt))
        XCTAssertEqual([c.hour, c.minute], [21, 25])
    }

    func testGroupsBoxesIntoRows() {
        let boxes = [
            TextBox(text: "64. 8 kg", minX: 0.6, midY: 0.502, height: 0.02),
            TextBox(text: "体重", minX: 0.1, midY: 0.500, height: 0.02),
            TextBox(text: "体脂肪率", minX: 0.1, midY: 0.470, height: 0.02),
            TextBox(text: "16. 8 %", minX: 0.6, midY: 0.468, height: 0.02),
        ]
        XCTAssertEqual(ReceiptParser.rows(from: boxes), ["体重 64. 8 kg", "体脂肪率 16. 8 %"])
    }

    func testDetectsMisreadWeight() {
        var rows = sampleRows
        rows[rows.firstIndex(of: "体重 6 4. 8 kg")!] = "体重 6 1. 8 kg"
        let issues = ReceiptValidator.validate(ReceiptParser.parse(rows: rows, calendar: calendar), calendar: calendar)
        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(issues.allSatisfy { $0.fields.contains(.weight) })
    }

    func testDetectsAgeMismatchWithBirthday() {
        let m = ReceiptParser.parse(rows: sampleRows, calendar: calendar)
        let birthday = calendar.date(from: DateComponents(year: 1967, month: 5, day: 9))!
        XCTAssertEqual(ReceiptValidator.validate(m, birthday: birthday, calendar: calendar), [])

        let wrongBirthday = calendar.date(from: DateComponents(year: 1966, month: 5, day: 9))!
        let issues = ReceiptValidator.validate(m, birthday: wrongBirthday, calendar: calendar)
        XCTAssertEqual(issues.map(\.fields), [[.age]])
    }
}
