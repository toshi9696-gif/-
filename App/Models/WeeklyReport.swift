import BodyCompCore
import Foundation
import SwiftData

/// Claude が作成した週次レポート。週（月曜始まり）ごとに1件だけ持ち、作り直すと上書きする。
@Model
final class WeeklyReport {
    @Attribute(.unique) var weekStart: Date
    var createdAt: Date
    var modelName: String
    /// Claude の回答（WeeklyReportContent の JSON）。
    var contentJSON: String
    /// Claude に送った集計データ（確認用）。
    var inputJSON: String

    init(weekStart: Date, model: String, content: WeeklyReportContent, input: WeeklyReportInput) {
        self.weekStart = weekStart
        createdAt = Date()
        modelName = model
        contentJSON = Self.encode(content)
        inputJSON = Self.encode(input)
    }

    func update(model: String, content: WeeklyReportContent, input: WeeklyReportInput) {
        createdAt = Date()
        modelName = model
        contentJSON = Self.encode(content)
        inputJSON = Self.encode(input)
    }

    var content: WeeklyReportContent? {
        contentJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode(WeeklyReportContent.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
