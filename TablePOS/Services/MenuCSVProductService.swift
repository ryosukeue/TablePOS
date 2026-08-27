import Foundation
import SwiftData

struct MenuCSVImportSummary: Sendable {
    let created: Int
    let updated: Int
    let skipped: Int
    let categoriesCreated: Int
}

enum MenuCSVProductService {
    private static let categoryColors = [
        "7C3AED", "0891B2", "DB2777", "65A30D",
        "D97706", "4F46E5", "0F766E", "B91C1C"
    ]

    @MainActor
    static func apply(
        rows: [MenuCSVRow],
        duplicatePolicy: MenuCSVDuplicatePolicy,
        searchIndexes: [Int: ProductSearch.SearchIndex],
        in context: ModelContext
    ) throws -> MenuCSVImportSummary {
        let existingProducts = try context.fetch(FetchDescriptor<Product>())
        let existingCategories = try context.fetch(FetchDescriptor<ProductCategory>())

        var productsByName: [String: Product] = [:]
        for product in existingProducts where productsByName[matchingKey(product.name)] == nil {
            productsByName[matchingKey(product.name)] = product
        }

        var categoriesByName: [String: ProductCategory] = [:]
        for category in existingCategories {
            categoriesByName[matchingKey(category.name)] = category
        }

        var nextCategoryOrder = (existingCategories.map(\.sortOrder).max() ?? -1) + 1
        var created = 0
        var updated = 0
        var skipped = 0
        var categoriesCreated = 0

        for row in rows {
            let productKey = matchingKey(row.name)
            if productsByName[productKey] != nil, duplicatePolicy == .skip {
                skipped += 1
                continue
            }

            let categoryID: UUID?
            if row.categoryName.isEmpty {
                categoryID = nil
            } else {
                let categoryKey = matchingKey(row.categoryName)
                if let category = categoriesByName[categoryKey] {
                    categoryID = category.id
                } else {
                    let color = categoryColors[categoriesCreated % categoryColors.count]
                    let category = ProductCategory(
                        name: row.categoryName,
                        colorHex: color,
                        sortOrder: nextCategoryOrder
                    )
                    nextCategoryOrder += 1
                    categoriesCreated += 1
                    categoriesByName[categoryKey] = category
                    context.insert(category)
                    categoryID = category.id
                }
            }

            let product: Product
            if let existing = productsByName[productKey] {
                existing.name = row.name
                existing.price = row.price
                existing.taxRate = row.taxRate
                existing.taxType = row.taxType
                existing.menuType = row.menuType
                existing.categoryID = categoryID
                existing.isFrequent = row.isFrequent
                existing.isEnabled = row.isEnabled
                existing.updatedAt = .now
                product = existing
                updated += 1
            } else {
                let newProduct = Product(
                    name: row.name,
                    price: row.price,
                    taxRate: row.taxRate,
                    taxType: row.taxType,
                    menuType: row.menuType,
                    categoryID: categoryID,
                    isFrequent: row.isFrequent,
                    isEnabled: row.isEnabled
                )
                context.insert(newProduct)
                productsByName[productKey] = newProduct
                product = newProduct
                created += 1
            }

            if let index = searchIndexes[row.lineNumber] {
                ProductSearch.updateIndex(for: product, using: index)
            } else {
                ProductSearch.updateIndex(for: product)
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return MenuCSVImportSummary(
            created: created,
            updated: updated,
            skipped: skipped,
            categoriesCreated: categoriesCreated
        )
    }

    private static func matchingKey(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
