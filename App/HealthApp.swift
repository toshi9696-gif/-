import SwiftData
import SwiftUI

@main
struct HealthApp: App {
    @State private var activity = ActivityModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(activity)
        }
        .modelContainer(for: [BodyRecord.self, WeeklyReport.self])
    }
}

enum SettingsKey {
    static let birthdayEnabled = "birthdayEnabled"
    static let birthday = "birthday"
    static let heightWrittenToHealth = "heightWrittenToHealth"
    static let goalVisceral = "goalVisceral"
    static let goalMuscleFloor = "goalMuscleFloor"
    static let goalDeadline = "goalDeadline"
    static let zone2Manual = "zone2Manual"
    static let zone2Low = "zone2Low"
    static let zone2High = "zone2High"
    static let reportReminder = "reportReminder"
    static let reportNotes = "reportNotes"
    static let goalWaist = "goalWaist"
}

/// 仕様書の目標（6か月で内臓脂肪レベル 9 以下、筋肉量 50.5kg 以上を維持）。設定画面で変更できる。
enum GoalDefaults {
    static let visceral = 9.0
    static let muscleFloor = 50.5
    /// 腹囲の目標（この値未満）。日本の健診で男性の内臓脂肪の多い目安とされる 85cm。
    static let waist = 85.0
    static let reportNotes = "お酒は一滴も飲まない。食事量は少なめで、ご飯はお茶碗に軽く1杯程度。"
    static let deadline = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 31))!
        .timeIntervalSince1970
}
