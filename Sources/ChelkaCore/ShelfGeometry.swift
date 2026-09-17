import Foundation
import CoreGraphics

/// Чистая геометрия полки — без AppKit, чтобы её можно было тестировать.
/// Координаты — в системе экрана macOS (origin слева внизу).
public enum ShelfGeometry {
    /// Высота контентной части полки под чёлкой (иконки + подписи + отступы).
    public static let contentHeight: CGFloat = 92
    /// На сколько hit-зона шире чёлки с каждой стороны (чтобы попадать курсором).
    public static let hitSlop: CGFloat = 20
    /// Полоска-fallback для экранов без чёлки.
    public static let fallbackSize = CGSize(width: 240, height: 18)
    /// Минимальная ширина раскрытой полки.
    public static let minExpandedWidth: CGFloat = 480

    /// Свернутое состояние. `notchLeftMaxX`/`notchRightMinX` — края выреза
    /// (NSScreen.auxiliaryTopLeftArea.maxX / auxiliaryTopRightArea.minX),
    /// `safeTop` — высота чёлки (safeAreaInsets.top). Любой из них nil/0 —
    /// экран без чёлки, полоска по центру верхней кромки.
    public static func collapsedRect(screenFrame: CGRect,
                                     notchLeftMaxX: CGFloat?,
                                     notchRightMinX: CGFloat?,
                                     safeTop: CGFloat) -> CGRect {
        if let l = notchLeftMaxX, let r = notchRightMinX, safeTop > 0 {
            return CGRect(x: l - hitSlop,
                          y: screenFrame.maxY - safeTop,
                          width: (r - l) + hitSlop * 2,
                          height: safeTop)
        }
        return CGRect(x: (screenFrame.midX - fallbackSize.width / 2).rounded(),
                      y: screenFrame.maxY - fallbackSize.height,
                      width: fallbackSize.width,
                      height: fallbackSize.height)
    }

    /// Раскрытое состояние: шире свернутого, контент — под чёлкой.
    public static func expandedRect(screenFrame: CGRect, collapsed: CGRect) -> CGRect {
        let w = max(collapsed.width + 180, minExpandedWidth)
        let h = collapsed.height + contentHeight
        return CGRect(x: (screenFrame.midX - w / 2).rounded(),
                      y: screenFrame.maxY - h,
                      width: w,
                      height: h)
    }

    /// Прогресс раскрытия по фактической высоте окна: 0 — свернуто, 1 — раскрыто.
    /// Во время анимации кадра даёт плавное проявление контента.
    public static func expandProgress(height: CGFloat, topInset: CGFloat) -> CGFloat {
        min(max((height - topInset) / contentHeight, 0), 1)
    }

    /// Прозрачность контента: проявляется во второй половине анимации.
    public static func contentAlpha(progress: CGFloat) -> CGFloat {
        min(max((progress - 0.4) / 0.6, 0), 1)
    }

    /// Вписывает содержимое размера `content` в `box` с сохранением пропорций,
    /// по центру. Возвращает nil для вырожденных размеров.
    public static func aspectFitRect(content: CGSize, in box: CGRect) -> CGRect? {
        guard content.width > 0, content.height > 0,
              box.width > 0, box.height > 0 else { return nil }
        let k = min(box.width / content.width, box.height / content.height)
        let w = content.width * k
        let h = content.height * k
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
