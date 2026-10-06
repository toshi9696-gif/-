import Foundation

/// OCR で認識した文字の塊。座標は Vision と同じ正規化座標（原点は左下）。
public struct TextBox: Sendable {
    public var text: String
    public var minX: Double
    public var midY: Double
    public var height: Double

    public init(text: String, minX: Double, midY: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.midY = midY
        self.height = height
    }
}

public enum ReceiptParser {
    /// 文字の塊を、上から下・左から右の行に並べ直す。
    public static func rows(from boxes: [TextBox]) -> [String] {
        var rows: [[TextBox]] = []
        for box in boxes.sorted(by: { $0.midY > $1.midY }) {
            if let anchor = rows.last?.first,
               abs(anchor.midY - box.midY) < max(anchor.height, box.height) * 0.6 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { $0.sorted(by: { $0.minX < $1.minX }).map(\.text).joined(separator: " ") }
    }

    /// 行のテキストから測定値を取り出す。同じ項目が複数回出てきた場合は最初の値を使う。
    public static func parse(rows: [String], calendar: Calendar = .current) -> BodyMeasurement {
        let compact = rows.map(normalize)
        var measurement = BodyMeasurement()
        measurement.measuredAt = parseDate(compact, calendar: calendar)
        for row in compact {
            guard let match = matchLabel(row),
                  measurement[match.field] == nil,
                  let value = number(from: match.remainder) else { continue }
            measurement[match.field] = value
        }
        measurement.bodyType = parseBodyType(compact)
        return measurement
    }

    /// 全角英数字を半角にし、空白をすべて取り除く（レシートは等幅印字で数字の間に空白が入るため）。
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
    }

    /// 行を「項目名の部分」と「値の部分」に分け、項目名に最もよく一致する項目を選ぶ。
    /// OCR では太字の漢字（「量」「ベ」など）がよく読み違えられるため、完全一致ではなく
    /// 項目名の文字がどれだけ含まれているかで判定する。同点なら長い項目名を優先する（「脂肪量」と「除脂肪量」など）。
    static func matchLabel(_ row: String) -> (field: ReceiptField, remainder: Substring)? {
        let (prefix, remainder) = splitLabel(row)
        guard !prefix.isEmpty else { return nil }
        let characters = Set(prefix)
        var best: (field: ReceiptField, score: Double, length: Int)?
        for field in ReceiptField.allCases {
            for label in field.receiptLabels {
                let hits = label.filter { characters.contains($0) }.count
                let score = Double(hits) / Double(label.count)
                guard hits > 0, score >= 0.5 else { continue }
                if best == nil || score > best!.score || (score == best!.score && label.count > best!.length) {
                    best = (field, score, label.count)
                }
            }
        }
        guard let best else { return nil }
        return (best.field, remainder)
    }

    /// 最初の数字より前を項目名、それ以降を値とみなす。
    /// 数字がない行は、末尾に続く数字に似た文字（「ll」など2文字以上）を値とみなす。
    static func splitLabel(_ row: String) -> (prefix: Substring, remainder: Substring) {
        if let index = row.firstIndex(where: { $0.isASCII && $0.isNumber }) {
            return (row[..<index], row[index...])
        }
        var index = row.endIndex
        while index > row.startIndex, "lIoO|".contains(row[row.index(before: index)]) {
            index = row.index(before: index)
        }
        if row.distance(from: index, to: row.endIndex) < 2 {
            index = row.endIndex
        }
        return (row[..<index], row[index...])
    }

    /// 項目名の後ろから数値を取り出す。単位を除いてから、数字に似た文字を数字に置き換える。
    static func number(from text: Substring) -> Double? {
        let withoutUnits = String(text)
            .replacingOccurrences(of: #"(?i)kca.|k[gq9]|cm|\(?PT\)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[%才点]"#, with: "", options: .regularExpression)
        let mapped = String(withoutUnits.map { character -> Character in
            switch character {
            case "O", "o", "D", "Q": "0"
            case "l", "I", "|": "1"
            case "Z": "2"
            case "S": "5"
            case "G", "b": "6"
            case "B": "8"
            case ",": "."
            default: character
            }
        })
        let digits = mapped.filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard let range = digits.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(digits[range])
    }

    /// 「2026/09/30(水)21:25」形式の日時を探す。曜日部分は読み間違いがあっても無視する。
    static func parseDate(_ rows: [String], calendar: Calendar) -> Date? {
        let regex = try! NSRegularExpression(pattern: #"(20\d{2})/(\d{1,2})/(\d{1,2}).{0,5}?(\d{1,2}):(\d{2})"#)
        for text in rows + [rows.joined()] {
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let n = (1...5).compactMap { Int(ns.substring(with: match.range(at: $0))) }
            guard n.count == 5, (1...12).contains(n[1]), (1...31).contains(n[2]),
                  (0...23).contains(n[3]), (0...59).contains(n[4]) else { continue }
            let components = DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4])
            if let date = calendar.date(from: components) { return date }
        }
        return nil
    }

    /// 「☆標準☆」のように星印で囲まれた体型判定を取り出す。
    static func parseBodyType(_ rows: [String]) -> String? {
        for row in rows where row.contains("☆") || row.contains("★") {
            let text = row.filter { $0 != "☆" && $0 != "★" }
            if !text.isEmpty { return text }
        }
        return nil
    }
}
