import BodyCompCore
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum ReceiptOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? { "画像を読み込めませんでした" }
}

/// iPhone 内の Vision でレシートの文字を読み取り、行ごとのテキストを返す。
enum ReceiptOCR {
    /// 元の画像と、白黒にしてコントラストを強めた画像の両方を読み取る。
    /// 感熱紙の薄い印字は、コントラストを強めたほうが読めることが多い。どちらを使うかは ReceiptParser.bestParse が決める。
    static func recognizeRowCandidates(in image: UIImage) async throws -> [[String]] {
        guard let cgImage = image.cgImage else { throw ReceiptOCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            var candidates = [try ReceiptOCR.recognizeRows(in: cgImage, orientation: orientation)]
            if let enhanced = ReceiptOCR.enhanced(cgImage) {
                candidates.append(try ReceiptOCR.recognizeRows(in: enhanced, orientation: orientation))
            }
            return candidates
        }.value
    }

    private static func recognizeRows(in cgImage: CGImage, orientation: CGImagePropertyOrientation) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        // 数値の読み取りが主なので、辞書による補正は使わない。
        request.usesLanguageCorrection = false
        // 初期値（画像の高さの約 1/32）より小さい文字は無視される。細長いレシートでは1行が画像の高さの 1/50 ほどしかなく、
        // 1文字ずつ空けて印字された数字が捨てられてしまうため、小さな文字も読むようにする。
        request.minimumTextHeight = 0.005

        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])

        let boxes = (request.results ?? []).compactMap { observation -> TextBox? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return TextBox(text: text, minX: box.minX, midY: box.midY, height: box.height)
        }
        return ReceiptParser.rows(from: boxes)
    }

    /// 白黒にしてコントラストと輪郭を強めた画像。
    private static func enhanced(_ cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.saturation = 0
        controls.contrast = 1.8
        controls.brightness = 0.1
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = controls.outputImage
        sharpen.sharpness = 0.8
        guard let output = sharpen.outputImage ?? controls.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
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
