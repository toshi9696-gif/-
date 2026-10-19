import BodyCompCore
import SwiftData
import SwiftUI

/// 体重と腹囲の手入力（体組成計が使えないときや、普通の体重計・メジャーで測ったとき）。
struct ManualEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let editingRecord: BodyRecord?
    @State private var measuredAt: Date
    @State private var weightText: String
    @State private var waistText: String
    @State private var showOverwrite = false
    @State private var healthKitError: String?

    init(editing record: BodyRecord? = nil) {
        editingRecord = record
        _measuredAt = State(initialValue: record?.measuredAt ?? Date())
        _weightText = State(initialValue: record?.weight.map(ReceiptField.weight.format) ?? "")
        _waistText = State(initialValue: record?.waist.map(ReceiptField.waist.format) ?? "")
    }

    private var weight: Double? { Self.number(weightText) }
    private var waist: Double? { Self.number(waistText) }

    private var problems: [String] {
        var problems: [String] = []
        if weight == nil && waist == nil { problems.append("体重か腹囲のどちらかを入力してください") }
        if let weight, !ReceiptField.weight.validRange.contains(weight) { problems.append("体重の値を確認してください") }
        if let waist, !ReceiptField.waist.validRange.contains(waist) { problems.append("腹囲の値を確認してください") }
        return problems
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日時") {
                    DatePicker("測定日時", selection: $measuredAt)
                }

                Section {
                    row("体重", text: $weightText, unit: "kg")
                    row("腹囲", text: $waistText, unit: "cm")
                } footer: {
                    Text("""
                    腹囲は、おへその高さでメジャーを床と水平にして測ります。朝起きてトイレのあと、軽く息を吐いた状態で、週1回同じ条件で測ってください。男性は 85cm 以上が内臓脂肪の多い目安です。
                    体組成計とは別の体重計で測った体重は、少しずれることがあります。
                    """)
                }

                if !problems.isEmpty && (!weightText.isEmpty || !waistText.isEmpty) {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(editingRecord == nil ? "体重・腹囲を記録" : "記録の編集")
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

    private func row(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
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
            record.isManual = true
            context.insert(record)
        }
        // 手入力の項目だけを書き換え、同じ記録にあるレシートの値は残す。
        record.measuredAt = target
        record.weight = weight
        record.waist = waist
        record.healthKitSynced = false
        record.updatedAt = Date()
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

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}
