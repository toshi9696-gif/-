import BodyCompCore
import SwiftData
import SwiftUI

/// 手入力の記録。体重・腹囲だけ、またはオムロンの体組成計の表示を見て入力する。
struct ManualEntryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case weightWaist, omron

        var id: Self { self }

        var title: String {
            switch self {
            case .weightWaist: "体重・腹囲"
            case .omron: "オムロン"
            }
        }

        var fields: [ReceiptField] {
            switch self {
            case .weightWaist: [.weight, .waist]
            case .omron: [.weight, .fatPercent, .visceralLevel, .skeletalMusclePercent, .bmr, .bmi, .waist]
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editingRecord: BodyRecord?
    @State private var mode: Mode
    @State private var measuredAt: Date
    @State private var texts: [ReceiptField: String]
    @State private var showOverwrite = false
    @State private var healthKitError: String?

    init(editing record: BodyRecord? = nil) {
        editingRecord = record
        _mode = State(initialValue: record?.device == .omron ? .omron : .weightWaist)
        _measuredAt = State(initialValue: record?.measuredAt ?? Date())
        var texts: [ReceiptField: String] = [:]
        for field in Mode.omron.fields {
            texts[field] = record?.value(field).map(field.format) ?? ""
        }
        _texts = State(initialValue: texts)
    }

    private func value(_ field: ReceiptField) -> Double? {
        Double(texts[field, default: ""].replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var problems: [String] {
        let entered = mode.fields.filter { value($0) != nil }
        var problems: [String] = []
        if entered.isEmpty { problems.append("少なくとも1つの項目を入力してください") }
        for field in entered {
            if let v = value(field), !field.validRange.contains(v) {
                problems.append("\(field.displayName)の値を確認してください")
            }
        }
        return problems
    }

    private var hasInput: Bool {
        mode.fields.contains { !texts[$0, default: ""].isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("記録する内容", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("測定日時", selection: $measuredAt)
                } footer: {
                    if mode == .omron {
                        Text("オムロンの体組成計の表示を見て入力してください。タニタとは計算方法が違うため、グラフや傾向はタニタと分けて扱います。")
                    }
                }

                Section {
                    ForEach(mode.fields, id: \.self) { field in
                        HStack {
                            Text(field.displayName)
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
                                .frame(width: 44, alignment: .leading)
                        }
                    }
                } footer: {
                    Text("""
                    腹囲は、おへその高さでメジャーを床と水平にして測ります。朝起きてトイレのあと、軽く息を吐いた状態で、週1回同じ条件で測ってください。男性は 85cm 以上が内臓脂肪の多い目安です。
                    """)
                }

                if hasInput && !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(editingRecord == nil ? "手入力で記録" : "記録の編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(overwrite: false) }
                        .disabled(!problems.isEmpty)
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

    private func save(overwrite: Bool) {
        let target = measuredAt
        let originalDate = editingRecord?.measuredAt
        let existing = try? context.fetch(FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.measuredAt == target }
        )).first

        let record: BodyRecord
        if let existing, existing.persistentModelID != editingRecord?.persistentModelID {
            guard overwrite else {
                showOverwrite = true
                return
            }
            if let editingRecord { context.delete(editingRecord) }
            record = existing
        } else if let editingRecord {
            record = editingRecord
        } else {
            record = BodyRecord(measurement: BodyMeasurement(measuredAt: target))
            context.insert(record)
        }

        // 入力した内容の項目だけを書き換える。
        var m = record.measurement
        m.measuredAt = target
        for field in mode.fields {
            m[field] = value(field)
        }
        record.apply(m)
        record.isManual = true
        record.device = mode == .omron ? .omron : nil
        try? context.save()

        let measurement = record.measurement
        Task {
            do {
                if let originalDate, originalDate != target {
                    try await HealthKitWriter.shared.delete(measuredAt: originalDate)
                }
                try await HealthKitWriter.shared.write(measurement)
                record.healthKitSynced = true
                try? context.save()
                dismiss()
            } catch {
                healthKitError = error.localizedDescription
            }
        }
    }
}
