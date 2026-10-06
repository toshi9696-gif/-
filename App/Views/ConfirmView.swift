import BodyCompCore
import SwiftData
import SwiftUI

/// 読み取り結果の確認と修正。整合性チェックに失敗した項目は赤で表示する。
struct ConfirmView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.birthdayEnabled) private var birthdayEnabled = false
    @AppStorage(SettingsKey.birthday) private var birthdayInterval: Double = 0

    @State private var measuredAt: Date
    @State private var dateWasRead: Bool
    @State private var texts: [ReceiptField: String]
    @State private var bodyType: String
    @State private var showOverwrite = false
    @State private var isSaving = false
    @State private var healthKitError: String?

    /// OCR で読み取った行のテキスト（読み取り精度の調整用）。
    let rawRows: [String]

    init(parsed: BodyMeasurement, rawRows: [String] = []) {
        self.rawRows = rawRows
        _measuredAt = State(initialValue: parsed.measuredAt ?? Date())
        _dateWasRead = State(initialValue: parsed.measuredAt != nil)
        var texts: [ReceiptField: String] = [:]
        for field in ReceiptField.allCases {
            texts[field] = parsed[field].map(field.format) ?? ""
        }
        _texts = State(initialValue: texts)
        _bodyType = State(initialValue: parsed.bodyType ?? "")
    }

    private var measurement: BodyMeasurement {
        var m = BodyMeasurement(measuredAt: measuredAt, bodyType: bodyType.isEmpty ? nil : bodyType)
        for field in ReceiptField.allCases {
            m[field] = Double(texts[field, default: ""].replacingOccurrences(of: ",", with: "."))
        }
        return m
    }

    private var issues: [ValidationIssue] {
        let birthday = birthdayEnabled ? Date(timeIntervalSince1970: birthdayInterval) : nil
        var issues = ReceiptValidator.validate(measurement, birthday: birthday)
        if !dateWasRead {
            issues.insert(ValidationIssue(fields: [], message: "日時を読み取れませんでした。日時を確認してください"), at: 0)
        }
        return issues
    }

    private var flaggedFields: Set<ReceiptField> {
        issues.reduce(into: []) { $0.formUnion($1.fields) }
    }

    /// 体重と日時があれば保存できる（古いレシートで一部が読めない場合を想定）。
    private var canSave: Bool {
        measurement[.weight] != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if issues.isEmpty {
                        Label("すべてのチェックを通過しました", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(issues.indices, id: \.self) { index in
                            Label(issues[index].message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("チェック結果")
                }

                Section("日時") {
                    DatePicker("測定日時", selection: $measuredAt)
                        .foregroundStyle(dateWasRead ? Color.primary : Color.red)
                        .onChange(of: measuredAt) { dateWasRead = true }
                }

                Section("入力項目") {
                    ForEach(ReceiptField.inputFields, id: \.self, content: fieldRow)
                }

                Section("測定結果") {
                    ForEach(ReceiptField.resultFields, id: \.self, content: fieldRow)
                    HStack {
                        Text("体型判定")
                        Spacer()
                        TextField("—", text: $bodyType)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if !rawRows.isEmpty {
                    Section {
                        DisclosureGroup("読み取った文字（確認用）") {
                            Text(rawRows.joined(separator: "\n"))
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    } footer: {
                        Text("読み取りがうまくいかないときは、ここを開いた画面のスクリーンショットを送ってください。")
                    }
                }
            }
            .navigationTitle("読み取り結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(overwrite: false) }
                        .fontWeight(issues.isEmpty ? .bold : .regular)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("同じ日時の記録があります", isPresented: $showOverwrite, titleVisibility: .visible) {
                Button("上書きする", role: .destructive) { save(overwrite: true) }
            }
            .alert("ヘルスケアに書き込めませんでした", isPresented: Binding(
                get: { healthKitError != nil },
                set: { if !$0 { healthKitError = nil; dismiss() } }
            )) {
                Button("OK") {}
            } message: {
                Text("記録はアプリ内に保存されています。\n\(healthKitError ?? "")")
            }
        }
    }

    private func fieldRow(_ field: ReceiptField) -> some View {
        HStack {
            Text(field.displayName)
                .foregroundStyle(flaggedFields.contains(field) ? Color.red : Color.primary)
            Spacer()
            TextField("—", text: Binding(
                get: { texts[field, default: ""] },
                set: { texts[field] = $0 }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 100)
            Text(field.unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func save(overwrite: Bool) {
        let m = measurement
        let target = measuredAt
        let existing = try? context.fetch(FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.measuredAt == target }
        )).first

        let record: BodyRecord
        if let existing {
            guard overwrite else {
                showOverwrite = true
                return
            }
            existing.apply(m)
            record = existing
        } else {
            record = BodyRecord(measurement: m)
            context.insert(record)
        }
        try? context.save()

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await HealthKitWriter.shared.write(m)
                record.healthKitSynced = true
                try? context.save()
                dismiss()
            } catch {
                healthKitError = error.localizedDescription
            }
        }
    }
}
