import BodyCompCore
import Foundation
import Observation

/// ヘルスケアから読んだ活動データを画面間で共有する。アプリを開くたびに読み直す（アプリ内には保存しない）。
@MainActor
@Observable
final class ActivityModel {
    /// 読み込む期間。グラフの「全期間」も、活動データはこの日数までになる。
    static let loadedDays = 183

    private(set) var days: [DailyActivity] = []
    private(set) var restingHeartRateMedian: Double?
    private(set) var vo2Max: Double?
    private(set) var zone2Range: ClosedRange<Double>?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// - Parameters:
    ///   - age: 最新の記録の年齢（最大心拍の計算に使う）
    ///   - manualZone2: 設定画面で手動指定した Zone2 の範囲
    func load(age: Int?, manualZone2: ClosedRange<Double>?) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let reader = HealthKitReader.shared
            try await reader.requestAuthorization()
            restingHeartRateMedian = try await reader.restingHeartRateMedian()
            vo2Max = try await reader.latestVO2Max()
            if let manualZone2 {
                zone2Range = manualZone2
            } else if let age, let resting = restingHeartRateMedian {
                zone2Range = Zone2.heartRateRange(age: age, restingHeartRate: resting)
            } else {
                zone2Range = nil
            }
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -(Self.loadedDays - 1), to: end)!
            days = try await reader.dailyActivities(from: start, to: end, zone2Range: zone2Range)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
