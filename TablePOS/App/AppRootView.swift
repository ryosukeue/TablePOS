import SwiftData
import SwiftUI

struct AppRootView: View {
    @Query private var settings: [StoreSettings]

    var body: some View {
        Group {
            if settings.first?.isSetupComplete == true {
                RootTabView()
            } else {
                InitialSetupView()
            }
        }
    }
}

private struct InitialSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tableCount = 12
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.12), Color.teal.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "ipad.and.iphone")
                    .font(.system(size: 56))
                    .foregroundStyle(.indigo)
                VStack(spacing: 8) {
                    Text("TablePOSへようこそ")
                        .font(.largeTitle.bold())
                    Text("最初にお店のテーブル数を設定します")
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $tableCount, in: 1...100) {
                    HStack {
                        Text("テーブル数")
                        Spacer()
                        Text("\(tableCount)卓")
                            .font(.title2.bold())
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 16))

                Button("この内容で開始") {
                    do {
                        try AppDataService.setupStore(tableCount: tableCount, in: modelContext)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: 520)
            .padding(40)
        }
        .alert("設定できませんでした", isPresented: .constant(errorMessage != nil)) {
            Button("閉じる") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TableHomeView() }
                .tabItem { Label("テーブル", systemImage: "square.grid.2x2") }
            NavigationStack { ProductListView() }
                .tabItem { Label("商品", systemImage: "fork.knife") }
            NavigationStack { SaleHistoryView() }
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
