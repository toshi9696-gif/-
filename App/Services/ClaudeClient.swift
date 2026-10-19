import BodyCompCore
import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case overloaded
    case refused
    case truncated
    case server(status: Int, message: String)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Claude の API キーが設定されていません。設定画面で入力してください。"
        case .invalidAPIKey: "API キーが正しくありません。設定画面で入力し直してください。"
        case .rateLimited: "短時間に使いすぎたため、一時的に制限されています。しばらく待ってからもう一度試してください。"
        case .overloaded: "Claude が混み合っています。しばらく待ってからもう一度試してください。"
        case .refused: "Claude がこの依頼への回答を控えました。もう一度試してください。"
        case .truncated: "回答が長すぎて途中で切れました。もう一度試してください。"
        case let .server(status, message): "エラーが発生しました（\(status)）：\(message)"
        case .unreadableResponse: "Claude の回答を読み取れませんでした。もう一度試してください。"
        }
    }
}

/// Claude（Anthropic の Messages API）に週次レポートを依頼する。Swift には公式 SDK がないため HTTP で直接呼ぶ。
struct ClaudeClient {
    static let model = "claude-opus-5-5"

    let apiKey: String

    func weeklyReport(for input: WeeklyReportInput) async throws -> WeeklyReportContent {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 安全確認で回答を控えられた場合に、Anthropic が推奨する別のモデルで自動的にやり直す。
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = String(data: try encoder.encode(input), encoding: .utf8) ?? "{}"

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema],
            ],
            "system": Self.systemPrompt,
            "messages": [[
                "role": "user",
                "content": "今週の週次レポートを作成してください。集計データ（JSON）は次のとおりです。\n\n\(data)",
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.error(status: status, data: responseData) }

        let message = try JSONDecoder().decode(MessageResponse.self, from: responseData)
        switch message.stopReason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              let content = try? JSONDecoder().decode(WeeklyReportContent.self, from: json) else {
            throw ClaudeError.unreadableResponse
        }
        return content
    }

    private static func error(status: Int, data: Data) -> ClaudeError {
        switch status {
        case 401, 403: return .invalidAPIKey
        case 429: return .rateLimited
        case 529: return .overloaded
        default:
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            return .server(status: status, message: message ?? "不明なエラー")
        }
    }

    // MARK: - プロンプトと出力形式

    private static let systemPrompt = """
    あなたは、59歳の男性が自分専用に使っている健康記録アプリの中で、週に1回の振り返りを書く役割です。
    利用者の目標は、内臓脂肪レベルを期限までに目標値以下に、腹囲を目標値未満に下げつつ、筋肉量を下限以上に保つことです。
    データは TANITA の体組成計（毎晩ほぼ同じ時間に測定）と Apple Watch の週ごとの集計です。

    データを読むときの前提:
    - 内臓脂肪レベルは整数でしか変わらず、日々±1程度ぶれます。1週だけの上下ではなく、週の中央値の数週間の流れで判断してください。
    - 体組成計の値は体内の水分量で日々変わります。週平均どうしを比べてください。
    - Zone2 の時間は、Apple Watch でワークアウトを開始していた間の心拍だけで数えています。エクササイズ時間が多いのに Zone2 が少ない場合は、ワークアウトを開始していないか、運動の強さが Zone2 の範囲に届いていない可能性があります。
    - waistCmAverage は、メジャーで手入力した腹囲の週平均です。腹囲は内臓脂肪の量とよく連動し、日本の健診では男性 85cm 以上が内臓脂肪の多い目安です。体組成計の値（内臓脂肪レベル）がない週は、腹囲と体重で内臓脂肪の傾向を判断してください。
    - 体組成計の値がない週の体重は、別の体重計で測った値のことがあります。体組成計の値との小さな差は、体重計の違いの可能性があります。
    - userNotes は、利用者が伝えておきたい生活の前提です。これと矛盾する提案（たとえば、飲まない人への節酒や、すでに少ない食事量をさらに減らすこと）はしないでください。食事量が少ない人には、筋肉を守るためのたんぱく質の確保を優先してください。
    - muscleCheck.warning が true の週は、筋肉量が開始時から 1kg 以上減っています。その場合は減量を勧めず、筋力トレーニングと食事量の維持を優先してください。
    - データが少ない・欠けている項目は、推測で補わずに「データが少ない」と短く触れる程度にしてください。

    書き方:
    - 医療的な診断や病名には触れず、生活の振り返りと来週の行動に絞ってください。
    - 専門用語は避け、やさしい日本語で書いてください。
    - summary: 今週の評価を3文以内で。
    - notableChanges: 先週や開始時と比べて目立った変化を1〜3個。変化が小さければ、そのことを1個だけ書けば十分です。
    - focus: 来週の重点を1〜2個。それぞれ、title に短い見出し、detail に具体的な数値を含む行動（例：「Zone2 を週60分 → 90分」「平日の就寝を30分早めて睡眠7時間」）を書いてください。
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "notableChanges": ["type": "array", "items": ["type": "string"]],
            "focus": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                    ],
                    "required": ["title", "detail"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["summary", "notableChanges", "focus"],
        "additionalProperties": false,
    ]

    // MARK: - 応答の形

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}
