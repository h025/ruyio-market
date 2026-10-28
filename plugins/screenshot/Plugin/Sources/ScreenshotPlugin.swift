import Foundation
import RuyioPluginSDK
import Synchronization

/// Captures part of the screen through the host, keeps a short history in this plugin's store and pins
/// captures above other windows. The plugin never reads the screen itself: the host runs the system
/// selection, and only the image the user selected comes back (permission `screen.capture`).
final class ScreenshotPlugin: RuyioPlugin {
    static let collection = "captures"
    static let historyLimit = 50
    static let originToken = "io.github.h025.screenshot"

    struct Capture: Codable, Sendable {
        var blobID: String
        var pixelWidth: Int
        var pixelHeight: Int
        var scale: Double
        var createdAt: Date
    }

    struct ViewState: Sendable {
        var revision = 0
        var search = ""
        var selection: String?
    }

    let context: PluginContext
    private let view = Mutex(ViewState())

    init(context: PluginContext) {
        self.context = context
    }

    func t(_ zh: String, _ en: String) -> String { context.isChinese ? zh : en }

    // MARK: Actions

    func perform(_ invocation: ActionInvocation, execution: ExecutionID, operation: OperationID?) async throws -> ActionResult {
        do {
            switch invocation.actionID.rawValue {
            case "capture-pin":
                let capture = try await captureAndKeep(execution)
                try await context.capabilities.pinImage(blobID: capture.blobID, scale: capture.scale)
                return .succeeded()
            case "capture":
                let capture = try await captureAndKeep(execution)
                try await copy(capture)
                return .succeeded(.notice(t("截图已复制", "Screenshot copied")))
            case "show-history":
                return .succeeded(.openView("history"))
            default:
                throw RuyioError(.actionNotFound, objectID: invocation.actionID.rawValue)
            }
        } catch let error as RuyioError where error.code == .cancelled {
            // Escape during the selection is not a failure.
            return ActionResult(state: .cancelled)
        }
    }

    private func captureAndKeep(_ execution: ExecutionID) async throws -> Capture {
        let reply = try await context.capabilities.captureScreen(execution: execution)
        let capture = Capture(blobID: reply.blobID, pixelWidth: reply.pixelWidth, pixelHeight: reply.pixelHeight,
                              scale: reply.scale, createdAt: Date())
        try await context.storage.put(try document(for: capture, id: UUID().uuidString.lowercased()))
        try await prune()
        return capture
    }

    private func document(for capture: Capture, id: String) throws -> StoredDocument {
        StoredDocument(collection: Self.collection, id: id, body: try JSONCoding.value(capture),
                       searchText: Self.searchText(capture.createdAt), sortKey: capture.createdAt.timeIntervalSince1970,
                       blobIDs: [capture.blobID])
    }

    /// Oldest captures beyond the limit go; their images are collected once no document references them.
    private func prune() async throws {
        let page = try await context.storage.query(StorageQuery(collection: Self.collection, limit: Self.historyLimit + 20))
        let excess = page.documents.dropFirst(Self.historyLimit)
        guard !excess.isEmpty else { return }
        try await context.storage.batch(excess.map { .delete(StorageKey(collection: $0.collection, id: $0.id)) })
    }

    private func copy(_ capture: Capture) async throws {
        let item = PasteboardItemPayload(representations: [PasteboardRepresentation(type: "public.png", blobID: capture.blobID)])
        try await context.capabilities.writeClipboard(ClipboardWriteRequest(items: [item], originToken: Self.originToken))
    }

    // MARK: History view

    func openView(_ request: ViewOpenRequest) async throws -> ViewDocument {
        guard request.viewID == "history" else { throw RuyioError(.invalidRequest, diagnostic: "unknown view \(request.viewID)") }
        view.withLock { $0 = ViewState() }
        return try await historyDocument()
    }

    func handleViewEvent(_ request: ViewEventRequest) async throws -> ViewEventReply {
        switch request.event {
        case .searchChanged(let text):
            view.withLock {
                $0.search = text
                $0.selection = nil
            }
        case .selectionChanged(let id):
            view.withLock { $0.selection = id }
        case .invoke(let actionID, let itemID):
            return try await invoke(actionID, itemID: itemID ?? view.withLock { $0.selection })
        case .cancel:
            return ViewEventReply(document: nil, effect: .close)
        default:
            break
        }
        return ViewEventReply(document: try await historyDocument())
    }

    private func invoke(_ actionID: String, itemID: String?) async throws -> ViewEventReply {
        switch actionID {
        case "clear":
            return ViewEventReply(document: nil, effect: .confirm(ConfirmSpec(
                title: t("清空截图历史？", "Clear Screenshot History?"),
                message: t("所有截图都会从历史中删除，已钉在屏幕上的图片不受影响。", "All screenshots are removed from the history. Pinned images stay on screen."),
                confirmTitle: t("清空", "Clear"), confirmActionID: "confirm-clear", isDestructive: true)))
        case "confirm-clear":
            while true {
                let page = try await context.storage.query(StorageQuery(collection: Self.collection, limit: 200))
                guard !page.documents.isEmpty else { break }
                try await context.storage.batch(page.documents.map { .delete(StorageKey(collection: $0.collection, id: $0.id)) })
            }
            view.withLock { $0.selection = nil }
            return ViewEventReply(document: try await historyDocument())
        default:
            break
        }
        guard let itemID, let stored = try await context.storage.get(collection: Self.collection, id: itemID),
              let capture = try? JSONCoding.decode(Capture.self, from: stored.body) else {
            return ViewEventReply(document: try await historyDocument())
        }
        switch actionID {
        case "pin":
            try await context.capabilities.pinImage(blobID: capture.blobID, scale: capture.scale)
            return ViewEventReply(document: nil, effect: .close)
        case "copy":
            try await copy(capture)
            return ViewEventReply(document: nil, effect: .close)
        case "delete":
            let ids = try await visibleIDs()
            if let index = ids.firstIndex(of: itemID) {
                let next = ids.indices.contains(index + 1) ? ids[index + 1] : (index > 0 ? ids[index - 1] : nil)
                view.withLock { $0.selection = next }
            }
            try await context.storage.delete(collection: Self.collection, id: itemID)
            return ViewEventReply(document: try await historyDocument())
        default:
            return ViewEventReply(document: try await historyDocument())
        }
    }

    private func visibleCaptures() async throws -> [(id: String, capture: Capture)] {
        let search = view.withLock { $0.search }.trimmingCharacters(in: .whitespacesAndNewlines)
        // Full-text search needs three characters; shorter input filters the (small) history directly.
        let page = try await context.storage.query(StorageQuery(collection: Self.collection, search: search.count >= 3 ? search : nil,
                                                                limit: Self.historyLimit))
        return page.documents
            .filter { search.isEmpty || search.count >= 3 || ($0.searchText ?? "").contains(search) }
            .compactMap { doc in (try? JSONCoding.decode(Capture.self, from: doc.body)).map { (doc.id, $0) } }
    }

    private func visibleIDs() async throws -> [String] { try await visibleCaptures().map(\.id) }

    private func historyDocument() async throws -> ViewDocument {
        let captures = try await visibleCaptures()
        let (state, selected) = view.withLock { state -> (ViewState, String?) in
            let selected = captures.first { $0.id == state.selection }?.id ?? captures.first?.id
            state.selection = selected
            state.revision += 1
            return (state, selected)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: context.locale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let actions = [
            ItemAction(id: "pin", title: t("钉在屏幕上", "Pin to Screen"), shortcut: "return", symbol: "pin", isDefault: true),
            ItemAction(id: "copy", title: t("复制", "Copy"), shortcut: "command+c", symbol: "doc.on.doc"),
            ItemAction(id: "delete", title: t("删除", "Delete"), shortcut: "command+delete", symbol: "trash", isDestructive: true),
        ]
        let items = captures.map { entry in
            ListItem(id: entry.id, title: "\(entry.capture.pixelWidth) × \(entry.capture.pixelHeight)",
                     subtitle: formatter.string(from: entry.capture.createdAt), symbol: "photo", thumbnailBlobID: entry.capture.blobID,
                     accessibilityLabel: t("截图，", "Screenshot, ") + formatter.string(from: entry.capture.createdAt), actions: actions)
        }
        let preview = captures.first { $0.id == selected }.map { entry in
            UINode.image(ImageSpec(blobID: entry.capture.blobID, pixelWidth: entry.capture.pixelWidth, pixelHeight: entry.capture.pixelHeight,
                                   accessibilityLabel: t("截图预览", "Screenshot preview")))
        }
        let empty = state.search.isEmpty
            ? EmptySpec(title: t("还没有截图", "No Screenshots Yet"),
                        message: t("用“截图并钉住”或“截图到剪贴板”截一张，它会出现在这里。", "Use “Capture and Pin” or “Capture to Clipboard”; screenshots appear here."))
            : EmptySpec(title: t("没有匹配的截图", "No Matching Screenshots"))
        let collection = CollectionSpec(
            searchText: state.search, searchPlaceholder: t("按日期搜索，如 10-28", "Search by date, e.g. 10-28"),
            list: ListSpec(items: items, selection: selected, total: items.count, empty: empty),
            preview: preview,
            footerActions: items.isEmpty ? [] : [ItemAction(id: "clear", title: t("清空历史…", "Clear History…"), isDestructive: true)])
        return ViewDocument(viewID: "history", revision: state.revision, title: t("截图历史", "Screenshot History"), root: .collection(collection))
    }

    static func searchText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
