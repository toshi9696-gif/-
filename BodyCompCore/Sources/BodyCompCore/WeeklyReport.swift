import Foundation

/// 週次レポートのために Claude へ送るデータ。日ごとの値や個人を特定できる情報は含めず、週ごとの集計だけにする。
public struct WeeklyReportInput: Codable, Equatable, Sendable {
    public struct Goals: Codable, Equatable, Sendable {
        public var visceralLevelAtMost: Double
        public var muscleMassKgAtLeast: Double
        public var waistCmBelow: Double?
        public var deadline: String
        public var daysLeft: Int
    }

    public struct BodyWeek: Codable, Equatable, Sendable {
        public var weekStart: String
        public var measurementDays: Int
        public var visceralLevelMedian: Double?
        public var weightKgAverage: Double?
        public var fatPercentAverage: Double?
        public var muscleMassKgAverage: Double?
        public var fatMassKgAverage: Double?
        /// 腹囲（メジャーで手入力）。体組成計が使えない期間の内臓脂肪の目安にもなる。
        public var waistCmAverage: Double?
        /// 骨格筋率（オムロンで測った週だけ）。
        public var skeletalMusclePercentAverage: Double?
    }

    public struct ActivityWeek: Codable, Equatable, Sendable {
        public var weekStart: String
        public var daysWithData: Int
        public var stepsPerDay: Double?
        public var zone2MinutesTotal: Double?
        public var exerciseMinutesTotal: Double?
        public var sleepHoursPerNight: Double?
        public var restingHeartRate: Double?
        public var hrvMs: Double?
    }

    /// 筋肉の見張り。タニタは筋肉量（kg）、オムロンは骨格筋率（%）で判定する。
    public struct MuscleCheck: Codable, Equatable, Sendable {
        public var measure: String
        public var unit: String
        public var baseline: Double
        public var current: Double
        public var warning: Bool
    }

    /// レポートの対象週（月曜始まり）の初日。
    public var reportWeekStart: String
    public var age: Int?
    public var goals: Goals
    /// 記録を始めた週。
    public var baselineWeek: BodyWeek?
    /// 直近4週の体組成（古い順、記録のある週だけ）。
    public var bodyWeeks: [BodyWeek]
    /// 直近4週の Apple Watch の活動（古い順、データのある週だけ）。
    public var activityWeeks: [ActivityWeek]
    public var muscleCheck: MuscleCheck?
    /// Zone2 の心拍範囲 [下限, 上限]。Zone2 はワークアウト中の心拍だけで数えている。
    public var zone2RangeBpm: [Int]?
    public var vo2Max: Double?
    /// 体組成の値（体重・腹囲以外）を測った体組成計（"タニタ" または "オムロン"）。機種が違う値どうしは比べられない。
    public var scaleDevice: String?
    /// 利用者が設定画面で書いた、Claude に伝えておきたい生活の前提（飲酒・食事量など）。
    public var userNotes: String?
}

public enum WeeklyReportBuilder {
    public static func make(
        body: [ReceiptField: [DataPoint]],
        activity: [DailyActivity],
        age: Int?,
        goalVisceral: Double,
        goalMuscle: Double,
        goalWaist: Double? = nil,
        deadline: Date,
        zone2Range: ClosedRange<Double>?,
        vo2Max: Double?,
        userNotes: String? = nil,
        scaleDevice: String? = nil,
        baselineFrom: Date? = nil,
        today: Date,
        calendar: Calendar = .current
    ) -> WeeklyReportInput {
        var calendar = calendar
        calendar.firstWeekday = 2
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let weekStarts = (0..<4).reversed().map { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)! }
        let daily = body.mapValues { Trends.dailyLatest($0, calendar: calendar) }

        func bodyWeek(_ start: Date) -> WeeklyReportInput.BodyWeek {
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            func values(_ field: ReceiptField) -> [Double] {
                (daily[field] ?? []).filter { $0.date >= start && $0.date < end }.map(\.value)
            }
            func average(_ field: ReceiptField) -> Double? {
                let v = values(field)
                return v.isEmpty ? nil : round1(v.reduce(0, +) / Double(v.count))
            }
            let visceral = values(.visceralLevel)
            return WeeklyReportInput.BodyWeek(
                weekStart: formatter.string(from: start),
                measurementDays: ReceiptField.allCases.map { values($0).count }.max() ?? 0,
                visceralLevelMedian: visceral.isEmpty ? nil : round1(Trends.median(visceral)),
                weightKgAverage: average(.weight),
                fatPercentAverage: average(.fatPercent),
                muscleMassKgAverage: average(.muscleMass),
                fatMassKgAverage: average(.fatMass),
                waistCmAverage: average(.waist),
                skeletalMusclePercentAverage: average(.skeletalMusclePercent)
            )
        }

        func activityWeek(_ start: Date) -> WeeklyReportInput.ActivityWeek {
            let s = WeeklyActivitySummary.make(activity, weekContaining: start, calendar: calendar)
            return WeeklyReportInput.ActivityWeek(
                weekStart: formatter.string(from: start),
                daysWithData: s.dayCount,
                stepsPerDay: s.averageSteps.map { $0.rounded() },
                zone2MinutesTotal: s.zone2Minutes.map { $0.rounded() },
                exerciseMinutesTotal: s.exerciseMinutes.map { $0.rounded() },
                sleepHoursPerNight: s.averageSleepHours.map(round1),
                restingHeartRate: s.averageRestingHeartRate.map { $0.rounded() },
                hrvMs: s.averageHRV.map { $0.rounded() }
            )
        }

        // 体組成計を替えた場合は、今の機種を使い始めた週を出発点にする。
        let firstRecord = baselineFrom ?? body.values.flatMap { $0 }.map(\.date).min()
        let baseline = firstRecord.map { bodyWeek(calendar.dateInterval(of: .weekOfYear, for: $0)!.start) }

        let muscleField = [ReceiptField.muscleMass, .skeletalMusclePercent].first { !(body[$0] ?? []).isEmpty }
        let muscle = muscleField.flatMap { field in
            MuscleGuard.evaluate(body[field] ?? [], calendar: calendar).map { (field, $0) }
        }
        let daysLeft = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: deadline)
        ).day ?? 0

        return WeeklyReportInput(
            reportWeekStart: formatter.string(from: thisWeek),
            age: age,
            goals: WeeklyReportInput.Goals(
                visceralLevelAtMost: goalVisceral,
                muscleMassKgAtLeast: goalMuscle,
                waistCmBelow: goalWaist,
                deadline: formatter.string(from: deadline),
                daysLeft: max(0, daysLeft)
            ),
            baselineWeek: baseline,
            bodyWeeks: weekStarts.map(bodyWeek).filter { $0.measurementDays > 0 },
            activityWeeks: weekStarts.map(activityWeek).filter { $0.daysWithData > 0 },
            muscleCheck: muscle.map { field, check in
                WeeklyReportInput.MuscleCheck(
                    measure: field.displayName, unit: field.unit,
                    baseline: round1(check.baseline), current: round1(check.current), warning: check.isWarning
                )
            },
            zone2RangeBpm: zone2Range.map { [Int($0.lowerBound.rounded()), Int($0.upperBound.rounded())] },
            vo2Max: vo2Max.map(round1),
            scaleDevice: scaleDevice,
            userNotes: userNotes.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// Claude が返す週次レポートの中身（構造化出力のスキーマと対応する）。
public struct WeeklyReportContent: Codable, Equatable, Sendable {
    public struct Focus: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public var summary: String
    public var notableChanges: [String]
    public var focus: [Focus]

    public init(summary: String, notableChanges: [String], focus: [Focus]) {
        self.summary = summary
        self.notableChanges = notableChanges
        self.focus = focus
    }
}
