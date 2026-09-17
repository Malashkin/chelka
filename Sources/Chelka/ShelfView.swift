import AppKit
import ServiceManagement
import ChelkaCore

/// Полка: одновременно drop-target (приём файлов) и drag-source (отдача).
final class ShelfView: NSView, NSDraggingSource {
    private let store: ShelfStore
    private let transport: Transport

    /// Высота зоны чёлки сверху; контент рисуется ниже неё.
    var topInset: CGFloat = 32
    /// На экране без чёлки рисуем едва заметный pill, чтобы полку было видно.
    var hasNotch = true
    var onExpandChange: ((Bool) -> Void)?

    private(set) var expanded = false
    private var itemRects: [(url: URL, rect: NSRect)] = []
    private var pressed: (url: URL, point: NSPoint)?

    override var isFlipped: Bool { true }

    init(store: ShelfStore, transport: Transport) {
        self.store = store
        self.transport = transport
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        ThumbnailCache.shared.onThumbnail = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        super.updateTrackingAreas()
    }

    private func setExpanded(_ e: Bool) {
        guard expanded != e else { return }
        expanded = e
        onExpandChange?(e)
        needsDisplay = true
    }

    private func mouseInsideWindow() -> Bool {
        guard let w = window else { return false }
        return w.frame.contains(NSEvent.mouseLocation)
    }

    // MARK: наведение мыши (чтобы вытащить файл, наводимся на чёлку)

    override func mouseEntered(with event: NSEvent) {
        collapseWork?.cancel()
        setExpanded(true)
    }

    // Во время анимации кадра AppKit пересоздаёт tracking-зоны и шлёт ложные
    // enter/exit — без гистерезиса полка мигает (expand/collapse по кругу).
    // Сворачиваемся с задержкой и только если курсор реально вне окна.
    override func mouseExited(with event: NSEvent) { requestCollapse() }

    private var collapseWork: DispatchWorkItem?

    private func requestCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.mouseInsideWindow() else { return }
            self.setExpanded(false)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: приём drag'а

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        collapseWork?.cancel()
        setExpanded(true)
        return .copy
    }

    override func draggingExited(_ info: NSDraggingInfo?) { requestCollapse() }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        let added = store.add(urls)
        added.forEach { transport.push($0) }
        return !added.isEmpty
    }

    // MARK: отдача drag'а (в Telegram, Finder и т.д.)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressed = itemRects.first { $0.rect.contains(p) }.map { ($0.url, p) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pr = pressed else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - pr.point.x, p.y - pr.point.y) > 4 else { return }
        pressed = nil
        let item = NSDraggingItem(pasteboardWriter: pr.url as NSURL)
        let dragImage = ThumbnailCache.shared.thumbnail(for: pr.url)
            ?? NSWorkspace.shared.icon(forFile: pr.url.path)
        item.setDraggingFrame(NSRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48),
                              contents: dragImage)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        requestCollapse()
    }

    // MARK: контекстное меню

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if let hit = itemRects.first(where: { $0.rect.contains(p) }) {
            menu.addItem(makeItem("Убрать с полки", #selector(removeItem(_:)), hit.url))
            menu.addItem(makeItem("Показать в Finder", #selector(revealItem(_:)), hit.url))
            if transport.status(for: hit.url) == .failed {
                menu.addItem(makeItem("Отправить ещё раз", #selector(retryItem(_:)), hit.url))
            }
            menu.addItem(.separator())
        }
        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Завершить Chelka", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Chelka: не удалось изменить автозапуск: \(error.localizedDescription)")
        }
    }

    private func makeItem(_ title: String, _ action: Selector, _ url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }

    @objc private func removeItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        store.remove(url)
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func retryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        transport.push(url)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: отрисовка

    /// 0 — свернуто, 1 — полностью раскрыто. Во время анимации кадра окно
    /// перерисовывается на каждом шаге, так что контент плавно проявляется
    /// и растёт вместе с окном.
    private var expandProgress: CGFloat {
        ShelfGeometry.expandProgress(height: bounds.height, topInset: topInset)
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutItems()
        let progress = expandProgress
        guard progress > 0.02 else {
            if !hasNotch {
                let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 60, dy: 4), xRadius: 6, yRadius: 6)
                NSColor.black.withAlphaComponent(0.25).setFill()
                pill.fill()
            }
            return
        }

        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        NSColor.black.withAlphaComponent(0.85 * progress).setFill()
        bg.fill()

        // контент проявляется во второй половине анимации
        let contentAlpha = ShelfGeometry.contentAlpha(progress: progress)
        guard contentAlpha > 0 else { return }

        if store.files.isEmpty {
            let text = "Бросьте файлы сюда"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55 * contentAlpha),
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                  y: topInset + (bounds.height - topInset - size.height) / 2),
                      withAttributes: attrs)
            return
        }

        for (url, rect) in itemRects {
            let iconRect = NSRect(x: rect.midX - 24, y: rect.minY + 4, width: 48, height: 48)
            if let thumb = ThumbnailCache.shared.thumbnail(for: url),
               let fit = ShelfGeometry.aspectFitRect(content: thumb.size, in: iconRect) {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: fit, xRadius: 5, yRadius: 5).addClip()
                thumb.draw(in: fit, from: .zero, operation: .sourceOver, fraction: contentAlpha)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: contentAlpha)
            }

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85 * contentAlpha),
            ]
            let name = truncated(url.lastPathComponent, attrs: labelAttrs, width: rect.width - 8)
            let size = name.size(withAttributes: labelAttrs)
            name.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + 58),
                      withAttributes: labelAttrs)

            if let dot = statusColor(for: url) {
                let dotRect = NSRect(x: iconRect.maxX - 8, y: iconRect.minY, width: 9, height: 9)
                dot.withAlphaComponent(contentAlpha).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    private func statusColor(for url: URL) -> NSColor? {
        switch transport.status(for: url) {
        case .uploading: return .systemOrange
        case .sent: return .systemGreen
        case .failed: return .systemRed
        case nil: return nil
        }
    }

    private func truncated(_ s: String, attrs: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard s.size(withAttributes: attrs).width > width else { return s }
        var t = s
        while t.count > 3, ("…" + t).size(withAttributes: attrs).width > width {
            t = String(t.dropFirst())
        }
        return "…" + t
    }

    private func layoutItems() {
        itemRects = []
        guard expandProgress > 0.02 else { return }
        let cellW: CGFloat = 76
        let cellH: CGFloat = 74
        var x: CGFloat = 14
        let y = topInset + 8
        for url in store.files {
            if x + cellW > bounds.width - 14 { break } // MVP: без скролла
            itemRects.append((url, NSRect(x: x, y: y, width: cellW, height: cellH)))
            x += cellW
        }
    }
}
