import Foundation
import TablePOSSudachi

struct SudachiAnalysis: Decodable, Sendable {
    let normalized: String
    let reading: String
    let tokens: [String]
    let error: String?
}

/// Thin, fail-safe wrapper around the bundled Sudachi.rs tokenizer.
///
/// Loading the dictionary is intentionally lazy because SudachiDict core is large.
/// If the native library or its resources cannot be loaded, callers fall back to
/// deterministic Unicode/kana normalization.
final class SudachiAnalyzer: @unchecked Sendable {
    static let shared = SudachiAnalyzer()

    private let lock = NSLock()
    private var analyzer: OpaquePointer?

    private init() {
        guard
            let resourceURL = Bundle.main.url(
                forResource: "SudachiResources",
                withExtension: "bundle"
            )
        else { return }

        let configURL = resourceURL.appendingPathComponent("sudachi.json")
        let dictionaryURL = resourceURL.appendingPathComponent("system.dic")
        guard
            FileManager.default.fileExists(atPath: configURL.path),
            FileManager.default.fileExists(atPath: dictionaryURL.path)
        else { return }

        analyzer = configURL.path.withCString { configPath in
            resourceURL.path.withCString { resourcePath in
                dictionaryURL.path.withCString { dictionaryPath in
                    tablepos_sudachi_create(configPath, resourcePath, dictionaryPath)
                }
            }
        }
    }

    deinit {
        if let analyzer {
            tablepos_sudachi_destroy(analyzer)
        }
    }

    func analyze(_ text: String) -> SudachiAnalysis? {
        guard !text.isEmpty, let analyzer else { return nil }

        lock.lock()
        defer { lock.unlock() }

        return text.withCString { input in
            guard let response = tablepos_sudachi_analyze(analyzer, input) else { return nil }
            defer { tablepos_sudachi_string_free(response) }
            guard
                let data = String(cString: response).data(using: .utf8),
                let result = try? JSONDecoder().decode(SudachiAnalysis.self, from: data),
                result.error == nil
            else { return nil }
            return result
        }
    }
}
