import Combine
import Foundation
import StarIO10

struct StarPrinterCandidate: Identifiable {
    let id: String
    let settings: StarConnectionSettings
    let modelName: String

    var interfaceLabel: String {
        switch settings.interfaceType {
        case .lan: "LAN"
        case .bluetooth: "Bluetooth"
        case .bluetoothLE: "Bluetooth LE"
        case .usb: "USB"
        default: "その他"
        }
    }

    var displayName: String { "\(modelName)（\(interfaceLabel)）" }
}

enum StarPrinterServiceError: LocalizedError {
    case noPrinterSelected
    case unsupportedInterface

    var errorDescription: String? {
        switch self {
        case .noPrinterSelected: "使用するプリンタが選択されていません。設定からプリンタを検索してください。"
        case .unsupportedInterface: "保存されたプリンタの接続方式を読み込めませんでした。もう一度検索してください。"
        }
    }
}

@MainActor
final class StarPrinterService: NSObject, ObservableObject, StarDeviceDiscoveryManagerDelegate {
    static let shared = StarPrinterService()

    @Published private(set) var discoveredPrinters: [StarPrinterCandidate] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var isOperating = false
    @Published var operationMessage: String?

    private var discoveryManager: (any StarDeviceDiscoveryManager)?
    private let defaults = UserDefaults.standard
    private let interfaceKey = "TablePOS.starPrinter.interface"
    private let identifierKey = "TablePOS.starPrinter.identifier"
    private let modelKey = "TablePOS.starPrinter.model"

    var selectedPrinterLabel: String? {
        guard let model = defaults.string(forKey: modelKey),
              let interface = defaults.string(forKey: interfaceKey) else { return nil }
        return "\(model)（\(interfaceLabel(for: interface))）"
    }

    func discover() {
        discoveredPrinters = []
        operationMessage = nil
        do {
            discoveryManager?.stopDiscovery()
            discoveryManager = try StarDeviceDiscoveryManagerFactory.create(
                interfaceTypes: [.lan, .bluetooth, .bluetoothLE, .usb]
            )
            discoveryManager?.discoveryTime = 10_000
            discoveryManager?.delegate = self
            isDiscovering = true
            try discoveryManager?.startDiscovery()
        } catch {
            isDiscovering = false
            operationMessage = error.localizedDescription
        }
    }

    func stopDiscovery() {
        discoveryManager?.stopDiscovery()
        isDiscovering = false
    }

    func select(_ candidate: StarPrinterCandidate) {
        guard let key = storageKey(for: candidate.settings.interfaceType) else {
            operationMessage = StarPrinterServiceError.unsupportedInterface.localizedDescription
            return
        }
        defaults.set(key, forKey: interfaceKey)
        defaults.set(candidate.settings.identifier, forKey: identifierKey)
        defaults.set(candidate.modelName, forKey: modelKey)
        objectWillChange.send()
        operationMessage = "\(candidate.displayName)を使用するプリンタに設定しました。"
    }

    func printReceipt(sale: Sale, items: [SaleItem], openDrawer: Bool) async throws {
        let settings = try selectedSettings()
        isOperating = true
        defer { isOperating = false }
        let printer = StarPrinter(settings)
        try await printer.open()
        defer { Task { await printer.close() } }

        if openDrawer {
            try await printer.print(command: drawerCommand())
        }
        try await printer.print(command: receiptCommand(sale: sale, items: items))
    }

    func openDrawer() async throws {
        let settings = try selectedSettings()
        isOperating = true
        defer { isOperating = false }
        let printer = StarPrinter(settings)
        try await printer.open()
        defer { Task { await printer.close() } }
        try await printer.print(command: drawerCommand())
    }

    nonisolated func manager(_ manager: any StarDeviceDiscoveryManager, didFind printer: StarPrinter) {
        let settings = printer.connectionSettings
        let modelName = printer.information.map { String(describing: $0.model) } ?? "Starプリンタ"
        Task { @MainActor in
            guard let key = storageKey(for: settings.interfaceType) else { return }
            let id = "\(key):\(settings.identifier)"
            guard !discoveredPrinters.contains(where: { $0.id == id }) else { return }
            discoveredPrinters.append(StarPrinterCandidate(
                id: id,
                settings: settings,
                modelName: modelName
            ))
        }
    }

    nonisolated func managerDidFinishDiscovery(_ manager: any StarDeviceDiscoveryManager) {
        Task { @MainActor in
            isDiscovering = false
            if discoveredPrinters.isEmpty {
                operationMessage = "プリンタが見つかりませんでした。mPOPの電源と接続を確認してください。"
            }
        }
    }

    private func selectedSettings() throws -> StarConnectionSettings {
        guard let interfaceValue = defaults.string(forKey: interfaceKey),
              let identifier = defaults.string(forKey: identifierKey) else {
            throw StarPrinterServiceError.noPrinterSelected
        }
        guard let interface = interfaceType(for: interfaceValue) else {
            throw StarPrinterServiceError.unsupportedInterface
        }
        return StarConnectionSettings(interfaceType: interface, identifier: identifier)
    }

    private func receiptCommand(sale: Sale, items: [SaleItem]) -> String {
        let sortedItems = items.sorted { $0.sortOrder < $1.sortOrder }
        let printer = StarXpandCommand.PrinterBuilder()
            .styleCJKCharacterPriority([.japanese])
            .styleInternationalCharacter(.japan)
            .styleAlignment(.center)
            .styleBold(true)
            .actionPrintText("TablePOS レシート\n")
            .styleBold(false)
            .actionPrintText("\(sale.completedAt.formatted(date: .numeric, time: .shortened))\n")
            .actionPrintText("\(sale.sourceTableName)  \(sale.paymentMethod.label)\n")
            .actionPrintText("--------------------------------\n")
            .styleAlignment(.left)

        for item in sortedItems {
            _ = printer.actionPrintText("\(item.name.nonEmptyOrPlaceholder)\n")
            _ = printer.actionPrintText("  \(item.unitPrice.yenText) x \(item.quantity)    \(item.lineAmount.yenText)\n")
        }

        _ = printer
            .actionPrintText("--------------------------------\n")
            .styleAlignment(.right)
            .actionPrintText("小計  \(sale.subtotal.yenText)\n")
        if sale.externalTax8 != 0 { _ = printer.actionPrintText("外税8%  \(sale.externalTax8.yenText)\n") }
        if sale.externalTax10 != 0 { _ = printer.actionPrintText("外税10%  \(sale.externalTax10.yenText)\n") }
        if sale.roundingAdjustment != 0 { _ = printer.actionPrintText("丸め調整  \(sale.roundingAdjustment.yenText)\n") }
        _ = printer
            .styleBold(true)
            .styleMagnification(StarXpandCommand.MagnificationParameter(width: 2, height: 2))
            .actionPrintText("合計 \(sale.total.yenText)\n")
            .styleMagnification(StarXpandCommand.MagnificationParameter(width: 1, height: 1))
            .styleBold(false)
        if let received = sale.receivedAmount { _ = printer.actionPrintText("お預かり  \(received.yenText)\n") }
        if let change = sale.changeAmount { _ = printer.actionPrintText("お釣り  \(change.yenText)\n") }
        _ = printer
            .styleAlignment(.center)
            .actionPrintText("\nありがとうございました\n")
            .actionPrintText("会計ID \(sale.id.uuidString.prefix(8))\n")
            .actionFeedLine(2)
            .actionCut(.partial)

        return StarXpandCommand.StarXpandCommandBuilder()
            .addDocument(StarXpandCommand.DocumentBuilder().addPrinter(printer))
            .getCommands()
    }

    private func drawerCommand() -> String {
        StarXpandCommand.StarXpandCommandBuilder()
            .addDocument(
                StarXpandCommand.DocumentBuilder()
                    .addDrawer(
                        StarXpandCommand.DrawerBuilder()
                            .actionOpen(StarXpandCommand.Drawer.OpenParameter())
                    )
            )
            .getCommands()
    }

    private func storageKey(for interface: InterfaceType) -> String? {
        switch interface {
        case .lan: "lan"
        case .bluetooth: "bluetooth"
        case .bluetoothLE: "bluetoothLE"
        case .usb: "usb"
        default: nil
        }
    }

    private func interfaceType(for key: String) -> InterfaceType? {
        switch key {
        case "lan": .lan
        case "bluetooth": .bluetooth
        case "bluetoothLE": .bluetoothLE
        case "usb": .usb
        default: nil
        }
    }

    private func interfaceLabel(for key: String) -> String {
        switch key {
        case "lan": "LAN"
        case "bluetooth": "Bluetooth"
        case "bluetoothLE": "Bluetooth LE"
        case "usb": "USB"
        default: key
        }
    }
}
