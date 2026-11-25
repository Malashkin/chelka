import Foundation
import CoreGraphics

/// Раскладка файлов на раскрытой полке — сетка, растущая вширь до
/// `maxColumns`, затем вниз до `maxVisibleRows`; дальше — вертикальный скролл.
/// Координаты — во flipped-системе вида полки (y растёт вниз), `top` — низ
/// зоны чёлки (topInset).
public struct ShelfLayout: Equatable {
    public static let cell = CGSize(width: 76, height: 74)
    /// Отступ сетки от боковых краёв полки.
    public static let sidePadding: CGFloat = 14
    public static let topPadding: CGFloat = 8
    public static let bottomPadding: CGFloat = 10
    /// Нижняя строка: сводка «N файлов · размер» и кнопка «Открыть папку».
    public static let footerHeight: CGFloat = 24
    public static let openButtonSize = CGSize(width: 128, height: 20)
    public static let defaultMaxColumns = 8
    public static let defaultMaxVisibleRows = 3
    /// Свёрнутый вид полки: показываются только самые свежие файлы.
    public static let recentLimit = 5
    /// Кнопка «Show All (N)» / «Show Less» — слева от «Open Folder».
    public static let toggleButtonSize = CGSize(width: 104, height: 20)
    public static let buttonGap: CGFloat = 6

    /// Сколько ячеек раскладывается (видимые файлы).
    public let count: Int
    /// Сколько файлов на полке всего (count может быть меньше — компактный вид).
    public let total: Int
    public let columns: Int
    public let rows: Int
    public let visibleRows: Int

    public init(count: Int,
                total: Int? = nil,
                maxColumns: Int = defaultMaxColumns,
                maxVisibleRows: Int = defaultMaxVisibleRows) {
        let n = max(0, count)
        let maxCols = max(1, maxColumns)
        self.count = n
        self.total = max(n, total ?? n)
        columns = max(1, min(n, maxCols))
        rows = (n + columns - 1) / columns
        visibleRows = max(1, min(rows, max(1, maxVisibleRows)))
    }

    /// Раскладка полки с `total` файлами: компактно — только `recentLimit`
    /// самых свежих, `showAll` — все (сетка со скроллом).
    public static func shelf(total: Int, showAll: Bool) -> ShelfLayout {
        let t = max(0, total)
        return ShelfLayout(count: showAll ? t : min(t, recentLimit), total: t)
    }

    /// Файлов на полке, которые сейчас не показаны.
    public var hiddenCount: Int { total - count }

    /// Переключатель «все / последние 5» нужен, только если файлов больше лимита.
    public var canToggle: Bool { total > Self.recentLimit }

    /// Ширина, нужная сетке (с боковыми отступами). Окно может быть шире —
    /// тогда сетка центрируется.
    public var contentWidth: CGFloat {
        Self.sidePadding * 2 + CGFloat(columns) * Self.cell.width
    }

    /// Высота контентной части полки под чёлкой: сетка + нижняя строка.
    /// Для одной строки файлов — ShelfGeometry.contentHeight.
    public var contentHeight: CGFloat {
        Self.topPadding + CGFloat(visibleRows) * Self.cell.height
            + Self.footerHeight + Self.bottomPadding
    }

    /// Нижняя строка — сразу под видимой частью сетки, вне зоны прокрутки.
    public func footerRect(width: CGFloat, top: CGFloat) -> CGRect {
        CGRect(x: Self.sidePadding, y: viewport(width: width, top: top).maxY,
               width: max(0, width - Self.sidePadding * 2), height: Self.footerHeight)
    }

    /// Кнопка «Открыть папку» — справа в нижней строке, по центру по высоте.
    public func openButtonRect(width: CGFloat, top: CGFloat) -> CGRect {
        let f = footerRect(width: width, top: top)
        let s = Self.openButtonSize
        return CGRect(x: f.maxX - s.width, y: f.midY - s.height / 2,
                      width: s.width, height: s.height)
    }

    /// Кнопка «Show All» / «Show Less» — слева от «Open Folder»; nil, если не нужна.
    public func toggleButtonRect(width: CGFloat, top: CGFloat) -> CGRect? {
        guard canToggle else { return nil }
        let open = openButtonRect(width: width, top: top)
        let s = Self.toggleButtonSize
        return CGRect(x: open.minX - Self.buttonGap - s.width, y: open.minY,
                      width: s.width, height: s.height)
    }

    /// На сколько можно прокрутить вниз; 0 — всё помещается.
    public var maxScroll: CGFloat {
        CGFloat(rows - visibleRows) * Self.cell.height
    }

    public func clampScroll(_ offset: CGFloat) -> CGFloat {
        min(max(offset, 0), maxScroll)
    }

    /// Окно, в котором видны ячейки: от верха сетки на высоту видимых строк.
    public func viewport(width: CGFloat, top: CGFloat) -> CGRect {
        CGRect(x: 0, y: top + Self.topPadding,
               width: width, height: CGFloat(visibleRows) * Self.cell.height)
    }

    /// Ячейка файла с индексом `index` (0 — самый свежий, слева сверху).
    public func itemRect(index: Int, width: CGFloat, top: CGFloat, scroll: CGFloat) -> CGRect {
        let col = index % columns
        let row = index / columns
        let gridWidth = CGFloat(columns) * Self.cell.width
        let originX = max(Self.sidePadding, ((width - gridWidth) / 2).rounded())
        return CGRect(x: originX + CGFloat(col) * Self.cell.width,
                      y: top + Self.topPadding + CGFloat(row) * Self.cell.height - clampScroll(scroll),
                      width: Self.cell.width, height: Self.cell.height)
    }

    /// Индексы ячеек, хотя бы частично попадающих в видимое окно.
    public func visibleIndices(width: CGFloat, top: CGFloat, scroll: CGFloat) -> [Int] {
        let vp = viewport(width: width, top: top)
        return (0..<count).filter {
            itemRect(index: $0, width: width, top: top, scroll: scroll).intersects(vp)
        }
    }

    /// Ползунок скролла: доля видимого и положение (0…1), nil — скролл не нужен.
    public func scrollIndicator(scroll: CGFloat) -> (fraction: CGFloat, position: CGFloat)? {
        guard maxScroll > 0 else { return nil }
        let fraction = CGFloat(visibleRows) / CGFloat(rows)
        return (fraction, clampScroll(scroll) / maxScroll)
    }
}
