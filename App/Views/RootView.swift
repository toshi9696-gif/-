import BodyCompCore
import PhotosUI
import SwiftUI
import VisionKit

struct RootView: View {
    @State private var showScanner = false
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var draft: ReceiptDraft?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            RecordListView()
                .navigationTitle("体組成ログ")
                .toolbar {
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
                .overlay {
                    if isProcessing {
                        ProgressView("読み取り中…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { images in
                showScanner = false
                // M1 では1枚目だけを処理する。複数枚の連続取り込みは M2 で対応する。
                if let first = images.first { process(first) }
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $draft) { draft in
            ConfirmView(parsed: draft.measurement)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
                draft = ReceiptDraft(measurement: ReceiptParser.parse(rows: rows))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ReceiptDraft: Identifiable {
    let id = UUID()
    let measurement: BodyMeasurement
}
