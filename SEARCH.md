# Japanese Product Search

## Why Sudachi

Foundation's generic `toLatin` transform is transliteration, not a Japanese morphological analyzer. Its kanji reading and word-boundary behavior is not reliable enough for a restaurant product master. TablePOS therefore uses Sudachi.rs with the official SudachiDict core for Japanese normalized forms, readings, and tokenization. There is no manually maintained synonym dictionary.

## Index generation

Every product name goes through these stages when saved:

1. Unicode compatibility composition (NFKC-equivalent behavior).
2. Case, width, and diacritic folding with the Japanese locale.
3. Hiragana-to-katakana conversion.
4. Whitespace and punctuation removal, retaining letters and numbers.
5. Sudachi mode C tokenization for the concatenated normalized form and reading.
6. Sudachi modes A, B, and C for unique surface, normalized, and reading token variants.

For example, the native tests verify these dictionary results:

```text
塩むすび -> reading: シオムスビ; variant token: 塩結び
生ビール -> reading: ナマビール
呑み     -> normalized: 飲む
```

The product record stores the normalized key, reading key, and token variants. The original name remains the source of truth, so indexes can be regenerated after future algorithm or dictionary updates.

## Ranking

The ranking tiers are deliberately separated so a semantic guess cannot outrank a reliable lexical result:

1. Surface exact, prefix, and substring match.
2. Sudachi normalized-form exact, prefix, and substring match.
3. Sudachi reading exact, prefix, and substring match.
4. Sudachi token exact, prefix, and substring match.
5. Character-level Levenshtein similarity across surface, normalized, reading, and token keys (minimum similarity 0.62).
6. Japanese `NLEmbedding` sentence distance (maximum distance below 0.9).

This catches kana/width variants, many conjugation and spelling variants, and small typing differences before meaning similarity is considered. Store-specific nicknames still cannot be guaranteed without learned selection history or a user dictionary; that remains future scope.

## Fallback

`SudachiAnalyzer` loads lazily and serializes native calls with a lock. If its library, configuration, or dictionary is unavailable, index generation falls back to deterministic Unicode/kana normalization. If `NLEmbedding` is unavailable, lexical and edit-similarity ranking still work. Search never requires a runtime network connection.

## Build and versions

- Sudachi.rs is pinned in `SudachiBridge/Cargo.lock` from commit `f4dd8f20a774bd71d34a7d4ffa00d987b8946f9e`.
- SudachiDict core is pinned to release `20260723`.
- The downloaded wheel SHA-256 is `b3869ce6b12b4bfa09575dc19030703bb669ab41bac12a74cafcbb28c6be2498`.
- The extracted `system.dic` SHA-256 is `53fa281d11eef3769712fe1c3c892117338f9892bee6daf4dad51daa5281bb6f`.

The prebuilt `TablePOSSudachi.xcframework` is committed so an ordinary app build does not require a Rust toolchain. `Scripts/build_sudachi_xcframework.sh` regenerates it when the bridge or Sudachi version changes. `Scripts/fetch_sudachi_dictionary.sh` downloads and verifies the official dictionary on the first clean app build.

The raw core dictionary is about 207 MB and is intentionally not committed. This favors Japanese search coverage and zero runtime network dependency over app size for the MVP. Third-party notices are stored under `ThirdPartyLicenses`.
