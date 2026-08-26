import Foundation
import Vision

struct OCRCandidate: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var price: Int
    var isSelected = true
}

enum OCRService {
    static func recognize(cgImage: CGImage) throws -> [OCRCandidate] {
        var recognizedLines: [String] = []
        var capturedError: Error?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                capturedError = error
                return
            }
            recognizedLines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        if let capturedError { throw capturedError }
        return parse(lines: recognizedLines)
    }

    static func parse(lines: [String]) -> [OCRCandidate] {
        let pattern = #"(?:[¥￥]\s*)?([0-9０-９][0-9０-９,，]*)\s*(?:円)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var candidates: [OCRCandidate] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let priceRange = Range(match.range(at: 1), in: line) else { continue }
            let rawPrice = String(line[priceRange])
                .folding(options: .widthInsensitive, locale: .current)
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "，", with: "")
            guard let price = Int(rawPrice), price >= 0 else { continue }
            let matchRange = Range(match.range(at: 0), in: line)
            let name = matchRange.map { String(line[..<$0.lowerBound]) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            candidates.append(OCRCandidate(name: name, price: price))
        }
        return candidates
    }
}
