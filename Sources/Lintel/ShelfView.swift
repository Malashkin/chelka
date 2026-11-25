import AppKit
import ServiceManagement
import LintelCore

/// Полка: одновременно drop-target (приём файлов) и drag-source (отдача).
final class ShelfView: NSView, NSDraggingSource {
    private let store: ShelfStore
    private let transport: Transport

    /// Высота зоны чёлки сверху; контент рисуется ниже неё.
    var topInset: CGFloat = 32
    /// На экране без чёлки рисуем едва заметный pill, чтобы полку было видно.
    var hasNotch = true
    var onExpandChange: ((Bool) -> Void)?
    /// Раскладка поменялась без сворачивания (Show All / Show Less) — окну нужен новый размер.
    var onLayoutChange: (() -> Void)?

    private(set) var expanded = false
    private var itemRects: [(url: URL, rect: NSRect)] = []
    /// Прокрутка сетки вниз (pt), если файлов больше, чем помещается строк.
    private var scrollOffset: CGFloat = 0
    /// Показаны все файлы (иначе — только `ShelfLayout.recentLimit` свежих).
    /// Сбрасывается при сворачивании: по умолчанию полка компактная.
    private(set) var showAll = false
    private enum FooterButton { case openFolder, toggle }
    /// Зажатая кнопка нижней строки (рисуется темнее до отпускания).
    private var pressedButton: FooterButton?
    var layout: ShelfLayout { .shelf(total: store.files.count, showAll: showAll) }
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

    private func setExpanded(_ e: Bool, reason: StaticString = #function) {
        guard expanded != e else { return }
        expanded = e
        if !e {   // следующее раскрытие — компактное и с самых свежих
            scrollOffset = 0
            showAll = false
        }
        NSLog("Lintel: shelf -> \(e ? "expanded" : "collapsed") (\(reason))")
        onExpandChange?(e)
        needsDisplay = true
    }

    private func mouseInsideWindow() -> Bool {
        guard let w = window else { return false }
        // Допуск 4pt: у верхней кромки экрана (куда курсор упирается, целясь
        // в чёлку) NSEvent.mouseLocation.y == maxY, а NSRect.contains верхнюю
        // границу не включает — без допуска полка мигает (expand/collapse цикл).
        return w.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
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

    /// Файл под точкой — только в видимой части сетки: прокрученная
    /// наполовину ячейка не должна ловить клик под чёлкой.
    private func hitItem(at p: NSPoint) -> (url: URL, rect: NSRect)? {
        guard layout.viewport(width: bounds.width, top: topInset).contains(p) else { return nil }
        return itemRects.first { $0.rect.contains(p) }
    }

    // MARK: прокрутка (трекпад / колесо), когда файлов больше видимых строк

    override func scrollWheel(with event: NSEvent) {
        let l = layout
        guard expanded, l.maxScroll > 0 else { return }
        // у колеса мыши дельты в «строках», у трекпада — в точках
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        let next = l.clampScroll(scrollOffset - dy)
        guard next != scrollOffset else { return }
        scrollOffset = next
        needsDisplay = true
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
        if expanded, let b = footerButton(at: p) {
            pressedButton = b
            needsDisplay = true
            return
        }
        pressed = hitItem(at: p).map { ($0.url, p) }
    }

    private func footerButton(at p: NSPoint) -> FooterButton? {
        let l = layout
        if l.openButtonRect(width: bounds.width, top: topInset).contains(p) { return .openFolder }
        if l.toggleButtonRect(width: bounds.width, top: topInset)?.contains(p) == true { return .toggle }
        return nil
    }

    // кнопка срабатывает по отпусканию над ней — как обычная кнопка macOS
    override func mouseUp(with event: NSEvent) {
        guard let b = pressedButton else { return }
        pressedButton = nil
        needsDisplay = true
        let p = convert(event.locationInWindow, from: nil)
        guard footerButton(at: p) == b else { return }
        switch b {
        case .openFolder: openShelfFolder()
        case .toggle: toggleShowAll()
        }
    }

    @objc private func toggleShowAll() {
        showAll.toggle()
        scrollOffset = 0
        NSLog("Lintel: shelf -> \(showAll ? "all files" : "recent only")")
        onLayoutChange?()
        needsDisplay = true
    }

    @objc private func openShelfFolder() {
        NSWorkspace.shared.open(ShelfStore.dir)
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
        if let hit = hitItem(at: p) {
            menu.addItem(makeItem("Remove from Shelf", #selector(removeItem(_:)), hit.url))
            menu.addItem(makeItem("Show in Finder", #selector(revealItem(_:)), hit.url))
            // отправка доступна для любого файла: дропнутые до настройки
            // peerHost иначе никак не дослать
            if transport.peerHost != nil, transport.status(for: hit.url) != .uploading {
                let title = transport.status(for: hit.url) == .failed
                    ? "Send Again" : "Send to Other Mac"
                menu.addItem(makeItem(title, #selector(retryItem(_:)), hit.url))
            }
            menu.addItem(.separator())
        }
        if !store.files.isEmpty || transport.peerHost != nil {
            let open = NSMenuItem(title: "Open Shelf Folder", action: #selector(openShelfFolder), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let clear = NSMenuItem(title: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Lintel", action: #selector(quitApp), keyEquivalent: "")
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
            NSLog("Lintel: failed to change Open at Login: \(error.localizedDescription)")
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

    // одна кнопка чистит всё: локально и, если настроен пир, на второй машине
    @objc private func clearShelf() {
        store.clear()
        transport.clearPeer()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: отрисовка

    /// 0 — свернуто, 1 — полностью раскрыто. Во время анимации кадра окно
    /// перерисовывается на каждом шаге, так что контент плавно проявляется
    /// и растёт вместе с окном.
    private var expandProgress: CGFloat {
        // эталон — высота одной строки, а не текущей сетки: иначе при
        // Show All окно растёт с 1 до 3 строк и контент на миг гаснет
        ShelfGeometry.expandProgress(height: bounds.height, topInset: topInset,
                                     contentHeight: ShelfGeometry.contentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutItems()
        let progress = expandProgress
        guard progress > 0.02 else {
            if !hasNotch {
                let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 60, dy: 5), xRadius: 9, yRadius: 9)
                NSColor.black.withAlphaComponent(0.35).setFill()
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

        drawFooter(alpha: contentAlpha)

        if store.files.isEmpty {
            let text = "Drop files here"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55 * contentAlpha),
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                  y: layout.viewport(width: bounds.width, top: topInset).midY - size.height / 2),
                      withAttributes: attrs)
            return
        }

        // прокрученные ячейки не должны залезать под чёлку и за низ полки
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: layout.viewport(width: bounds.width, top: topInset)).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if let ind = layout.scrollIndicator(scroll: scrollOffset) {
            let track = layout.viewport(width: bounds.width, top: topInset).insetBy(dx: 0, dy: 4)
            let h = max(16, track.height * ind.fraction)
            let bar = NSRect(x: bounds.width - 8, y: track.minY + (track.height - h) * ind.position,
                             width: 3, height: h)
            NSColor.white.withAlphaComponent(0.35 * contentAlpha).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
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

    /// Нижняя строка: «N files · size» слева, справа «Show All» / «Show Less» и «Open Folder».
    private func drawFooter(alpha: CGFloat) {
        let footer = layout.footerRect(width: bounds.width, top: topInset)

        // тонкий разделитель между сеткой и строкой
        NSColor.white.withAlphaComponent(0.08 * alpha).setFill()
        NSRect(x: footer.minX, y: footer.minY, width: footer.width, height: 1).fill()

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55 * alpha),
        ]
        let summary = ShelfSummary.text(count: store.files.count, bytes: store.totalBytes)
        let ts = summary.size(withAttributes: textAttrs)
        summary.draw(at: NSPoint(x: footer.minX + 2, y: footer.midY - ts.height / 2),
                     withAttributes: textAttrs)

        let l = layout
        drawPill(l.openButtonRect(width: bounds.width, top: topInset), label: "Open Folder",
                 symbol: "folder", pressed: pressedButton == .openFolder, alpha: alpha)
        if let t = l.toggleButtonRect(width: bounds.width, top: topInset) {
            let label = showAll ? "Show Less" : "Show All (\(l.total))"
            drawPill(t, label: label, symbol: showAll ? "chevron.up" : "chevron.down",
                     pressed: pressedButton == .toggle, alpha: alpha)
        }
    }

    /// Кнопка-«таблетка»: SF Symbol + подпись по центру.
    private func drawPill(_ button: NSRect, label: String, symbol: String, pressed: Bool, alpha: CGFloat) {
        NSColor.white.withAlphaComponent((pressed ? 0.24 : 0.12) * alpha).setFill()
        NSBezierPath(roundedRect: button, xRadius: button.height / 2, yRadius: button.height / 2).fill()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85 * alpha),
        ]
        let ls = label.size(withAttributes: labelAttrs)
        let iconSide: CGFloat = 13, gap: CGFloat = 5
        let startX = button.midX - (iconSide + gap + ls.width) / 2
        if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) {
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                NSColor.white.withAlphaComponent(0.85 * alpha).set()
                r.fill(using: .sourceAtop)
                return true
            }
            let fit = ShelfGeometry.aspectFitRect(content: tinted.size,
                                                  in: NSRect(x: startX, y: button.midY - iconSide / 2,
                                                             width: iconSide, height: iconSide))
            if let fit { tinted.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        }
        label.draw(at: NSPoint(x: startX + iconSide + gap, y: button.midY - ls.height / 2),
                   withAttributes: labelAttrs)
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
        let l = layout
        let files = store.files
        scrollOffset = l.clampScroll(scrollOffset)   // файлов могло стать меньше
        for i in l.visibleIndices(width: bounds.width, top: topInset, scroll: scrollOffset) {
            itemRects.append((files[i], l.itemRect(index: i, width: bounds.width,
                                                   top: topInset, scroll: scrollOffset)))
        }
    }
}
