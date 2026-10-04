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
}
