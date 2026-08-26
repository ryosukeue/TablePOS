import Foundation
import NaturalLanguage

enum ProductSearch {
    struct SearchIndex: Sendable {
        let surface: String
        let normalized: String
        let reading: String
        let tokens: [String]
    }

    private static let tokenSeparator = "\u{1F}"
    private static let japaneseLocale = Locale(identifier: "ja_JP")

    static func ranked(_ products: [Product], query: String) -> [Product] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return products.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        let queryIndex = makeIndex(for: trimmed)
        let embedding = NLEmbedding.sentenceEmbedding(for: .japanese)

        return products.compactMap { product -> (Product, Double)? in
            let productIndex = storedIndex(for: product) ?? makeIndex(for: product.name)
            let score: Double

            if let lexicalScore = lexicalScore(query: queryIndex, candidate: productIndex) {
                score = lexicalScore
            } else if let fuzzyScore = fuzzyScore(query: queryIndex, candidate: productIndex) {
                score = fuzzyScore
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

    static func makeIndex(for text: String) -> SearchIndex {
        let surface = basicNormalize(text)
        guard let analysis = SudachiAnalyzer.shared.analyze(text) else {
            return SearchIndex(surface: surface, normalized: surface, reading: surface, tokens: [])
        }

        let normalized = basicNormalize(analysis.normalized)
        let reading = basicNormalize(analysis.reading)
        let tokens = unique(
            analysis.tokens
                .map(basicNormalize)
                .filter { !$0.isEmpty && $0 != surface && $0 != normalized && $0 != reading }
        )
        return SearchIndex(
            surface: surface,
            normalized: normalized.isEmpty ? surface : normalized,
            reading: reading.isEmpty ? surface : reading,
            tokens: tokens
        )
    }

    static func updateIndex(for product: Product) {
        let index = makeIndex(for: product.name)
        product.searchNormalizedKey = index.normalized
        product.searchReadingKey = index.reading
        product.searchTokenKeysRaw = index.tokens.joined(separator: tokenSeparator)
    }

    static func basicNormalize(_ text: String) -> String {
        let compatibilityNormalized = text.precomposedStringWithCompatibilityMapping
        let folded = compatibilityNormalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: japaneseLocale
        )
        let katakana = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        return katakana
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased(with: japaneseLocale)
    }

    private static func storedIndex(for product: Product) -> SearchIndex? {
        guard
            let normalized = product.searchNormalizedKey,
            let reading = product.searchReadingKey
        else { return nil }
        let tokens = product.searchTokenKeysRaw?
            .components(separatedBy: tokenSeparator)
            .filter { !$0.isEmpty } ?? []
        return SearchIndex(
            surface: basicNormalize(product.name),
            normalized: normalized,
            reading: reading,
            tokens: tokens
        )
    }

    private static func lexicalScore(query: SearchIndex, candidate: SearchIndex) -> Double? {
        let queryKeys = unique([query.surface, query.normalized, query.reading]).filter { !$0.isEmpty }
        let tokenKeys = unique(candidate.tokens + [candidate.normalized, candidate.reading])

        if candidate.surface == query.surface { return 1_000 }
        if candidate.surface.hasPrefix(query.surface) { return 900 }
        if candidate.surface.contains(query.surface) { return 800 }
        if queryKeys.contains(candidate.normalized) { return 760 }
        if queryKeys.contains(candidate.reading) { return 740 }
        if queryKeys.contains(where: { candidate.normalized.hasPrefix($0) }) { return 700 }
        if queryKeys.contains(where: { candidate.reading.hasPrefix($0) }) { return 680 }
        if queryKeys.contains(where: { candidate.normalized.contains($0) }) { return 640 }
        if queryKeys.contains(where: { candidate.reading.contains($0) }) { return 620 }
        if queryKeys.contains(where: { queryKey in tokenKeys.contains(queryKey) }) { return 580 }
        if queryKeys.contains(where: { queryKey in tokenKeys.contains { $0.hasPrefix(queryKey) } }) { return 540 }
        if queryKeys.contains(where: { queryKey in tokenKeys.contains { $0.contains(queryKey) } }) { return 500 }
        return nil
    }

    private static func fuzzyScore(query: SearchIndex, candidate: SearchIndex) -> Double? {
        let queryKeys = unique([query.reading, query.normalized, query.surface]).filter { $0.count >= 2 }
        let candidateKeys = unique([candidate.reading, candidate.normalized, candidate.surface] + candidate.tokens)
            .filter { $0.count >= 2 }
        let similarity = queryKeys.flatMap { queryKey in
            candidateKeys.map { normalizedEditSimilarity(queryKey, $0) }
        }.max() ?? 0
        guard similarity >= 0.62 else { return nil }
        return 360 + (similarity * 100)
    }

    /// Character-level Levenshtein similarity works on kana/kanji without romanization.
    private static func normalizedEditSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }
            previous = current
        }
        let maximumLength = Double(max(left.count, right.count))
        return 1 - (Double(previous[right.count]) / maximumLength)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
