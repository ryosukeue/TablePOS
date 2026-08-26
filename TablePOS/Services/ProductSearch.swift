import Foundation
import NaturalLanguage

enum ProductSearch {
    static func ranked(_ products: [Product], query: String) -> [Product] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return products.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        let queryNormalized = normalize(trimmed)
        let queryReading = readingKey(trimmed)
        let embedding = NLEmbedding.sentenceEmbedding(for: .japanese)

        return products.compactMap { product -> (Product, Double)? in
            let normalized = normalize(product.name)
            let reading = readingKey(product.name)
            let score: Double

            if normalized == queryNormalized {
                score = 1_000
            } else if normalized.hasPrefix(queryNormalized) {
                score = 800
            } else if normalized.contains(queryNormalized) {
                score = 650
            } else if !queryReading.isEmpty && reading == queryReading {
                score = 600
            } else if !queryReading.isEmpty && reading.contains(queryReading) {
                score = 500
            } else if let embedding {
                let distance = embedding.distance(between: trimmed, and: product.name)
                guard distance.isFinite, distance < 0.9 else { return nil }
                score = 300 - (distance * 100)
            } else {
                return nil
            }
            return (product, score)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .map(\.0)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .applyingTransform(.hiraganaToKatakana, reverse: false)?
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased() ?? ""
    }

    static func readingKey(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
