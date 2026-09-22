import AppKit
import QuartzCore
import ChelkaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: ShelfPanel?
    private var view: ShelfView?
    private let store = ShelfStore()
    private let transport = Transport()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpPanel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let peer = transport.peerHost {
            NSLog("Chelka: пир для отправки — \(peer)")
        } else {
            NSLog("Chelka: peerHost не задан, полка работает только локально")
        }
    }

    /// Экран с чёлкой, иначе главный.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func collapsedRect(for s: NSScreen) -> NSRect {
        // отступ полоски от кромки на экранах без чёлки настраивается:
        // defaults write dev.mike.Chelka fallbackTopOffset <pt>
        let offset = UserDefaults.standard.object(forKey: "fallbackTopOffset") == nil
            ? ShelfGeometry.defaultFallbackTopOffset
            : CGFloat(UserDefaults.standard.double(forKey: "fallbackTopOffset"))
        return ShelfGeometry.collapsedRect(screenFrame: s.frame,
                                           notchLeftMaxX: s.auxiliaryTopLeftArea?.maxX,
                                           notchRightMinX: s.auxiliaryTopRightArea?.minX,
                                           safeTop: s.safeAreaInsets.top,
                                           fallbackTopOffset: offset)
    }

    static func expandedRect(for s: NSScreen) -> NSRect {
        ShelfGeometry.expandedRect(screenFrame: s.frame, collapsed: collapsedRect(for: s))
    }

    private func setUpPanel() {
        guard let s = targetScreen else { return }
        let collapsed = Self.collapsedRect(for: s)

        let v = ShelfView(store: store, transport: transport)
        v.topInset = collapsed.height
        v.hasNotch = s.auxiliaryTopLeftArea != nil
        v.onExpandChange = { [weak self] e in self?.applyFrame(expanded: e) }

        let p = ShelfPanel(contentRect: collapsed)
        p.contentView = v
        p.orderFrontRegardless()

        panel = p
        view = v
        store.onChange = { [weak self] in
            ThumbnailCache.shared.prune(keeping: self?.store.files ?? [])
            self?.view?.needsDisplay = true
        }
        transport.onChange = { [weak v] in v?.needsDisplay = true }
    }

    private var animationTarget: NSRect?

    private func applyFrame(expanded: Bool, animated: Bool = true) {
        guard let p = panel, let s = targetScreen else { return }
        let target = expanded ? Self.expandedRect(for: s) : Self.collapsedRect(for: s)
        // p.frame во время анимации — промежуточный, сравниваем с целью:
        // перезапуск той же анимации с середины выглядит как дёрганье
        guard target != animationTarget || !animated else { return }
        animationTarget = target
        guard p.frame != target else { return }
        guard animated else {
            p.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            // выезд из чёлки чуть медленнее и с сильным ease-out, уборка — быстрее
            ctx.duration = expanded ? 0.28 : 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            p.animator().setFrame(target, display: true)
        }
    }

    @objc private func screensChanged() {
        guard let s = targetScreen, let v = view else { return }
        v.topInset = Self.collapsedRect(for: s).height
        v.hasNotch = s.auxiliaryTopLeftArea != nil
        applyFrame(expanded: v.expanded, animated: false)
    }
}
