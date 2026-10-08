import SwiftData
import SwiftUI

@main
struct HealthApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: BodyRecord.self)
    }
}

enum SettingsKey {
    static let birthdayEnabled = "birthdayEnabled"
    static let birthday = "birthday"
    static let heightWrittenToHealth = "heightWrittenToHealth"
    static let goalVisceral = "goalVisceral"
    static let goalMuscleFloor = "goalMuscleFloor"
    static let goalDeadline = "goalDeadline"
}

/// 仕様書の目標（6か月で内臓脂肪レベル 9 以下、筋肉量 50.5kg 以上を維持）。設定画面で変更できる。
enum GoalDefaults {
    static let visceral = 9.0
    static let muscleFloor = 50.5
    static let deadline = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 31))!
        .timeIntervalSince1970
}
