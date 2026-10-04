import BodyCompCore
import UIKit
import Vision

enum ReceiptOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? { "画像を読み込めませんでした" }
}

/// iPhone 内の Vision でレシートの文字を読み取り、行ごとのテキストを返す。
enum ReceiptOCR {
    static func recognizeRows(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ReceiptOCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            // 数値の読み取りが主なので、辞書による補正は使わない。
            request.usesLanguageCorrection = false

            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])

            let boxes = (request.results ?? []).compactMap { observation -> TextBox? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return TextBox(text: text, minX: box.minX, midY: box.midY, height: box.height)
            }
            return ReceiptParser.rows(from: boxes)
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
