import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.birthdayEnabled) private var birthdayEnabled = false
    @AppStorage(SettingsKey.birthday) private var birthdayInterval: Double = 0
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("ヘルスケアへの書き込みを許可") {
                        Task {
                            do {
                                try await HealthKitWriter.shared.requestAuthorization()
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
