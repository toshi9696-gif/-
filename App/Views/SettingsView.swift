import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.birthdayEnabled) private var birthdayEnabled = false
    @AppStorage(SettingsKey.birthday) private var birthdayInterval: Double = 0
    @AppStorage(SettingsKey.goalVisceral) private var goalVisceral = GoalDefaults.visceral
    @AppStorage(SettingsKey.goalMuscleFloor) private var goalMuscleFloor = GoalDefaults.muscleFloor
    @AppStorage(SettingsKey.goalDeadline) private var goalDeadline = GoalDefaults.deadline
    @AppStorage(SettingsKey.zone2Manual) private var zone2Manual = false
    @AppStorage(SettingsKey.zone2Low) private var zone2Low = 120.0
    @AppStorage(SettingsKey.zone2High) private var zone2High = 130.0
    @Environment(ActivityModel.self) private var activity
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goalVisceral, in: 1...30, step: 1) {
                        LabeledContent("内臓脂肪レベル", value: "\(Int(goalVisceral)) 以下")
                    }
                    Stepper(value: $goalMuscleFloor, in: 30...80, step: 0.5) {
                        LabeledContent("筋肉量の下限", value: String(format: "%.1f kg", goalMuscleFloor))
                    }
                    DatePicker("期限", selection: Binding(
                        get: { Date(timeIntervalSince1970: goalDeadline) },
                        set: { goalDeadline = $0.timeIntervalSince1970 }
                    ), displayedComponents: .date)
                } header: {
                    Text("目標")
                } footer: {
                    Text("内臓脂肪レベルは、週ごとの中央値が2週連続で目標以下になったら達成とみなします。")
                }

                Section {
                    if let range = activity.zone2Range, !zone2Manual {
                        LabeledContent("現在の範囲", value: "\(Int(range.lowerBound.rounded()))〜\(Int(range.upperBound.rounded())) bpm")
                    }
                    Toggle("手動で設定する", isOn: $zone2Manual)
                    if zone2Manual {
                        Stepper(value: $zone2Low, in: 80...180, step: 1) {
                            LabeledContent("下限", value: "\(Int(zone2Low)) bpm")
                        }
                        Stepper(value: $zone2High, in: 80...190, step: 1) {
                            LabeledContent("上限", value: "\(Int(zone2High)) bpm")
                        }
                    }
                } header: {
                    Text("Zone2 の心拍範囲")
                } footer: {
                    Text("自動では、最新の記録の年齢と直近30日の安静時心拍から計算します（安静時心拍 +（220 − 年齢 − 安静時心拍）× 60〜70%）。Zone2 はワークアウト中の心拍から数えます。")
                }

                Section {
                    Toggle("誕生日を使う", isOn: $birthdayEnabled)
                    if birthdayEnabled {
                        DatePicker("誕生日", selection: Binding(
                            get: { Date(timeIntervalSince1970: birthdayInterval) },
                            set: { birthdayInterval = $0.timeIntervalSince1970 }
                        ), displayedComponents: .date)
                    }
                } footer: {
                    Text("レシートに印字された年齢と照合し、合わない場合は確認画面で警告します。")
                }

                Section {
                    Button("ヘルスケアへのアクセスを許可") {
                        Task {
                            do {
                                try await HealthKitWriter.shared.requestAuthorization()
                                try await HealthKitReader.shared.requestAuthorization()
                                healthMessage = "設定しました。変更はヘルスケアアプリの「共有」から行えます。"
                            } catch {
                                healthMessage = error.localizedDescription
                            }
                        }
                    }
                    if let healthMessage {
                        Text(healthMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("ヘルスケア")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
