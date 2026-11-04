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
    /// 最も一致する項目がすでに埋まっている場合は、次に一致する空いた項目に割り当てる
    /// （「除脂肪量」の「除」が読めず「脂肪量」と区別できないときなど）。
    public static func parse(rows: [String], calendar: Calendar = .current, now: Date = Date()) -> BodyMeasurement {
        let compact = rows.map(normalize)
        var measurement = BodyMeasurement()
        measurement.measuredAt = parseDate(compact, calendar: calendar, now: now)
        for row in compact {
            let (candidates, remainder) = matchLabels(row)
            guard let field = candidates.first(where: { measurement[$0] == nil }),
                  let value = number(from: remainder, field: field) else { continue }
            measurement[field] = value
        }
        measurement.bodyType = parseBodyType(compact)
        return measurement
    }

    /// 複数の読み取り結果（元の画像とコントラストを強めた画像など）と、複数の解釈
    /// （項目名で割り当てる／並び順で割り当てる）を試し、整合性チェックの問題が最も少ないものを返す。
    public static func bestParse(
        _ candidates: [[String]],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> (measurement: BodyMeasurement, rows: [String]) {
        var best: (measurement: BodyMeasurement, rows: [String], score: Int)?
        for rows in candidates {
            for measurement in interpretations(of: rows, calendar: calendar, now: now) {
                let score = problemScore(measurement, calendar: calendar)
                if best == nil || score < best!.score {
                    best = (measurement, rows, score)
                }
            }
        }
        return best.map { ($0.measurement, $0.rows) } ?? (BodyMeasurement(), candidates.first ?? [])
    }

    /// 問題のある項目（読めない・範囲外・計算が合わない）の数。日時が読めなければ1を足す。
    static func problemScore(_ m: BodyMeasurement, calendar: Calendar) -> Int {
        let flagged = ReceiptValidator.validate(m, calendar: calendar).reduce(into: Set<ReceiptField>()) { $0.formUnion($1.fields) }
        return flagged.count + (m.measuredAt == nil ? 1 : 0)
    }

    /// 項目名による読み取り、その空欄を並び順で補ったもの、並び順を優先したものの3通り。
    static func interpretations(of rows: [String], calendar: Calendar, now: Date) -> [BodyMeasurement] {
        let byLabel = parse(rows: rows, calendar: calendar, now: now)
        let byPosition = positionalValues(rows)
        guard !byPosition.isEmpty else { return [byLabel] }
        var filled = byLabel
        var positionFirst = byLabel
        for (field, value) in byPosition {
            if filled[field] == nil { filled[field] = value }
            positionFirst[field] = value
        }
        return [byLabel, filled, positionFirst]
    }

    /// レシートの並び順から値を割り当てる。項目名の漢字が読めなくても、数字の行の順番は保たれることが多い。
    /// 「入力項目」の後の数字の行を年齢・身長・着衣量、「測定結果」の後の数字の行を体重〜BMI の順に割り当てる。
    static func positionalValues(_ rows: [String]) -> [ReceiptField: Double] {
        let compact = rows.map(normalize)
        func isHeader(_ row: String, _ title: String, minimumHits: Int) -> Bool {
            guard !row.contains(where: { $0.isASCII && $0.isNumber }), row.count <= title.count + 3 else { return false }
            return title.filter { row.contains($0) }.count >= minimumHits
        }
        let inputStart = compact.firstIndex { isHeader($0, "入力項目", minimumHits: 3) }
        let resultStart = compact.firstIndex { isHeader($0, "測定結果", minimumHits: 3) }

        func numericRows(from start: Int, until stop: (String) -> Bool) -> [Substring] {
            var result: [Substring] = []
            for row in compact[(start + 1)...] {
                if stop(row) { break }
                let (_, remainder) = splitLabel(row)
                if remainder.contains(where: { $0.isASCII && $0.isNumber }) { result.append(remainder) }
            }
            return result
        }

        var values: [ReceiptField: Double] = [:]
        // 見出しが読めずに後ろの行まで拾った場合に備え、先頭から必要な数だけ使う。
        // ずれて割り当てた場合は、整合性チェックで問題が増えるので bestParse で選ばれない。
        func assign(_ rows: [Substring], to fields: [ReceiptField]) {
            guard rows.count >= fields.count else { return }
            for (row, field) in zip(rows, fields) {
                if let value = number(from: row, field: field) { values[field] = value }
            }
        }
        if let inputStart, let resultStart, inputStart < resultStart {
            assign(numericRows(from: inputStart) { isHeader($0, "測定結果", minimumHits: 3) }, to: ReceiptField.inputFields)
        }
        if let resultStart {
            assign(numericRows(from: resultStart) { isHeader($0, "判定", minimumHits: 2) }, to: ReceiptField.resultFields)
        }
        return values
    }

    /// 全角英数字を半角にし、空白をすべて取り除く（レシートは等幅印字で数字の間に空白が入るため）。
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
    }

    /// 行を「項目名の部分」と「値の部分」に分け、項目名に最もよく一致する項目を選ぶ。
    /// OCR では太字の漢字（「量」「ベ」など）がよく読み違えられるため、完全一致ではなく
    /// 項目名の文字がどれだけ含まれているかで判定する。同点なら長い項目名を優先する（「脂肪量」と「除脂肪量」など）。
    static func matchLabel(_ row: String) -> (field: ReceiptField, remainder: Substring)? {
        let (candidates, remainder) = matchLabels(row)
        return candidates.first.map { ($0, remainder) }
    }

    /// 一致度の高い順に並べた項目の候補と、値の部分を返す。
    static func matchLabels(_ row: String) -> (candidates: [ReceiptField], remainder: Substring) {
        let (prefix, remainder) = splitLabel(row)
        guard !prefix.isEmpty else { return ([], remainder) }
        let characters = Set(prefix)
        var scored: [(field: ReceiptField, score: Double, length: Int)] = []
        for field in ReceiptField.allCases {
            for label in field.receiptLabels {
                let hits = label.filter { characters.contains($0) }.count
                let score = Double(hits) / Double(label.count)
                guard hits > 0, score >= 0.5 else { continue }
                scored.append((field, score, label.count))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.length > $1.length }
        var seen = Set<ReceiptField>()
        let candidates = scored.map(\.field).filter { seen.insert($0).inserted }
        return (candidates, remainder)
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
    /// 小数点が読めずに想定範囲を外れた場合は、レシートの桁数に合わせて小数点を補う（「113」→「11.3」）。
    static func number(from text: Substring, field: ReceiptField? = nil) -> Double? {
        let withoutUnits = String(text)
            .replacingOccurrences(of: #"(?i)kca.|k[gq9]|cm|c[il1|]{1,2}$|\(?PT\)?"#, with: "", options: .regularExpression)
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
        guard let range = digits.range(of: #"\d+(\.\d+)?"#, options: .regularExpression),
              let value = Double(digits[range]) else { return nil }
        let token = digits[range]
        if let field, field.fractionDigits > 0, !token.contains("."), token.count >= 2,
           !field.validRange.contains(value) || token.hasPrefix("0") {
            let divisor = pow(10, Double(field.fractionDigits))
            return value / divisor
        }
        return value
    }

    /// 「2026/09/30(水)21:25」形式の日時を探す。曜日部分は読み間違いがあっても無視する。
    /// 年が読み違えられた場合（「2936」など）は、測った直後に撮影する前提で、今年（年をまたいだ直後なら去年）に直す。
    static func parseDate(_ rows: [String], calendar: Calendar, now: Date = Date()) -> Date? {
        let regex = try! NSRegularExpression(pattern: #"(\d{4})/(\d{1,2})/(\d{1,2}).{0,5}?(\d{1,2}):(\d{2})"#)
        for text in rows + [rows.joined()] {
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let n = (1...5).compactMap { Int(ns.substring(with: match.range(at: $0))) }
            guard n.count == 5, (1...12).contains(n[1]), (1...31).contains(n[2]),
                  (0...23).contains(n[3]), (0...59).contains(n[4]) else { continue }
            let thisYear = calendar.component(.year, from: now)
            var year = n[0]
            if !((thisYear - 1)...thisYear).contains(year) { year = thisYear }
            var components = DateComponents(year: year, month: n[1], day: n[2], hour: n[3], minute: n[4])
            if year == thisYear, n[0] != thisYear, let date = calendar.date(from: components),
               date > now.addingTimeInterval(86_400) {
                components.year = thisYear - 1
            }
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
