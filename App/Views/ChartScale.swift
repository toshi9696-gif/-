import BodyCompCore
import Charts
import SwiftUI

/// グラフの縦軸・横軸をそろえるための共通設定。
enum ChartScale {
    /// 値の最小〜最大に余白を足した縦軸の範囲。値が1つしかない、または全部同じときも潰れないよう、最低限の幅を取る。
    static func yDomain(_ values: [Double], minimumSpan: Double) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, minimumSpan / 2)
        return (low - padding)...(high + padding)
    }

    /// 今日を含む直近 `days` 日間の横軸。
    static func recentDays(_ days: Int) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        return calendar.date(byAdding: .day, value: -days, to: tomorrow)!...tomorrow
    }
}

extension ReceiptField {
    /// 縦軸に最低限取る幅。小さな変化が大きく見えすぎないようにする。
    var chartMinimumSpan: Double {
        switch self {
        case .bmr: 60
        case .legScore: 10
        case .visceralLevel, .weight, .muscleMass, .fatMass, .leanMass, .fatPercent: 2
        default: 1
        }
    }
}

extension ChartScale {
    /// 横軸の目盛りを「10/5」のような月/日で表示する。
    static var dateAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        }
    }
}
