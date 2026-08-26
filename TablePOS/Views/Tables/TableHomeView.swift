import SwiftData
import SwiftUI

struct TableHomeView: View {
    @Query(sort: \DiningTable.sortOrder) private var tables: [DiningTable]
    @Query private var orders: [Order]
    @Query private var items: [OrderItem]

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(tables) { table in
                    NavigationLink {
                        OrderView(table: table)
                    } label: {
                        TableTile(
                            table: table,
                            order: orders.first { $0.tableID == table.id },
                            items: orderItems(for: table)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("テーブル")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("使用中 \(orders.count) / \(tables.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func orderItems(for table: DiningTable) -> [OrderItem] {
        guard let orderID = orders.first(where: { $0.tableID == table.id })?.id else { return [] }
        return items.filter { $0.orderID == orderID }
    }
}

private struct TableTile: View {
    let table: DiningTable
    let order: Order?
    let items: [OrderItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(table.name)
                    .font(.title3.bold())
                Spacer()
                Circle()
                    .fill(order == nil ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
            }
            Spacer(minLength: 12)
            if let order {
                Text(items.reduce(0) { $0 + $1.lineAmount }.yenText)
                    .font(.title.bold())
                HStack {
                    Label("\(items.reduce(0) { $0 + $1.quantity })点", systemImage: "cart")
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(order.openedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else {
                Text("空席")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
                Text("タップして注文を開始")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(order == nil ? Color.clear : Color.orange.opacity(0.45), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}
