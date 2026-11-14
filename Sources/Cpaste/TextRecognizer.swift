import CpasteCore
import Foundation
import Vision

/// Reads the text in image clips on this Mac, so search can find a screenshot by the words in it.
enum TextRecognizer {
    static func text(inImageAt url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(url: url).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Reads every image clip that has not been read yet. Call it on a background queue.
    static func readPendingImages(in store: ClipStore) {
        do {
            while true {
                let pending = try store.imagesAwaitingText(limit: 20)
                if pending.isEmpty { return }
                for image in pending {
                    let text: String
                    do {
                        text = try Self.text(inImageAt: store.imageFiles.imageURL(sha256: image.sha256))
                    } catch {
                        log.error("no text read from image clip \(image.clipID): \(String(describing: error), privacy: .public)")
                        // Recorded as read, or the same broken image would be retried forever.
                        text = ""
                    }
                    try store.setImageText(clipID: image.clipID, to: text)
                }
            }
        } catch {
            log.error("reading text in images stopped: \(String(describing: error), privacy: .public)")
        }
    }
}
