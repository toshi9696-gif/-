import BodyCompCore
import PhotosUI
import SwiftUI
import SwiftData
import VisionKit

struct RootView: View {
    @Environment(ActivityModel.self) private var activity
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BodyRecord.measuredAt, order: .reverse) private var records: [BodyRecord]
    @AppStorage(SettingsKey.zone2Manual) private var zone2Manual = false
    @AppStorage(SettingsKey.zone2Low) private var zone2Low = 120.0
    @AppStorage(SettingsKey.zone2High) private var zone2High = 130.0

    @State private var showScanner = false
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var draft: ReceiptDraft?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .navigationTitle("ホーム")
                    .toolbar { mainToolbar }
            }
            .tabItem { Label("ホーム", systemImage: "house") }

            NavigationStack {
                ChartsView()
                    .navigationTitle("グラフ")
                    .toolbar { mainToolbar }
            }
            .tabItem { Label("グラフ", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                RecordListView()
                    .navigationTitle("記録")
                    .toolbar { mainToolbar }
            }
            .tabItem { Label("記録", systemImage: "list.bullet") }

            NavigationStack {
                ReportsView()
                    .navigationTitle("レポート")
                    .toolbar { mainToolbar }
            }
            .tabItem { Label("レポート", systemImage: "sparkles") }
        }
        .overlay {
            if isProcessing {
                ProgressView("読み取り中…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { images in
                showScanner = false
                // 1回の撮影で読み取るのは1枚目のレシートだけ。
                if let first = images.first { process(first) }
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $draft) { draft in
            ConfirmView(parsed: draft.measurement, rawRows: draft.rawRows)
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await reloadActivity() } }) {
            SettingsView()
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                Task { await reloadActivity() }
            }
        }
        .onChange(of: photoItem) {
            Task { await loadPhoto() }
        }
        .alert("読み取りに失敗しました", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// どのタブからでも撮影・写真の取り込み・設定ができるようにする。
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
            }
            Button { showScanner = true } label: { Image(systemName: "camera") }
                .disabled(!VNDocumentCameraViewController.isSupported)
        }
    }

    /// Apple Watch のデータを読み直す。アプリを開いたときと、設定を閉じたときに行う。
    private func reloadActivity() async {
        let age = records.lazy.compactMap(\.age).first.map { Int($0) }
        let manual = zone2Manual && zone2Low < zone2High ? zone2Low...zone2High : nil
        await activity.load(age: age, manualZone2: manual)
    }

    private func loadPhoto() async {
        guard let item = photoItem else { return }
        photoItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "写真を読み込めませんでした"
            return
        }
        process(image)
    }

    private func process(_ image: UIImage) {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let rows = try await ReceiptOCR.recognizeRows(in: image)
                draft = ReceiptDraft(measurement: ReceiptParser.parse(rows: rows), rawRows: rows)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ReceiptDraft: Identifiable {
    let id = UUID()
    let measurement: BodyMeasurement
    let rawRows: [String]
}
