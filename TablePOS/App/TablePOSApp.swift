import SwiftData
import SwiftUI

@main
struct TablePOSApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            StoreSettings.self,
            DiningTable.self,
            ProductCategory.self,
            Product.self,
            Order.self,
            OrderItem.self,
            Sale.self,
            SaleItem.self,
            CancellationRecord.self
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("SwiftData store could not be created: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
    }
}
