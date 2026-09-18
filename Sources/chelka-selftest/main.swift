import Foundation
import ChelkaCore

// Тестовые фреймворки недоступны без полного Xcode (на машинах только CLT),
// поэтому проверки — обычные assert'ы с exit-кодом. Запуск: make test.

var failures = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected {
        print("ok  \(label)")
    } else {
        print("FAIL \(label): получили \(actual), ожидали \(expected)")
        failures += 1
    }
}

func expectNear(_ actual: CGFloat, _ expected: CGFloat, _ label: String) {
    if abs(actual - expected) < 0.001 {
        print("ok  \(label)")
    } else {
        print("FAIL \(label): получили \(actual), ожидали \(expected)")
        failures += 1
    }
}

// MARK: - Naming: коллизия имён при дропе не должна терять/перезаписывать файлы

expect(Naming.uniqueName("a.pdf", existing: []), "a.pdf", "naming: без коллизии имя не меняется")
expect(Naming.uniqueName("a.pdf", existing: ["a.pdf"]), "a-1.pdf", "naming: суффикс перед расширением")
expect(Naming.uniqueName("a.pdf", existing: ["a.pdf", "a-1.pdf", "a-2.pdf"]), "a-3.pdf", "naming: цепочка коллизий")
expect(Naming.uniqueName("Makefile", existing: ["Makefile"]), "Makefile-1", "naming: имя без расширения")
expect(Naming.uniqueName("archive.tar.gz", existing: ["archive.tar.gz"]), "archive.tar-1.gz", "naming: несколько точек")
expect(Naming.uniqueName("отчёт за март.pdf", existing: ["отчёт за март.pdf"]), "отчёт за март-1.pdf", "naming: пробелы и кириллица")

// MARK: - Геометрия: панель обязана накрывать чёлку с запасом, fallback — по центру

// Экран как у MacBook Pro 14": чёлка между x=624 и x=816, высота 32.
let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
let notch = ShelfGeometry.collapsedRect(screenFrame: screen,
                                        notchLeftMaxX: 624, notchRightMinX: 816, safeTop: 32)
expectNear(notch.minX, 624 - ShelfGeometry.hitSlop, "geometry: hit-зона шире чёлки слева")
expectNear(notch.width, (816 - 624) + ShelfGeometry.hitSlop * 2, "geometry: hit-зона шире чёлки на 2 slop")
expectNear(notch.height, 32, "geometry: высота = высоте чёлки")
expectNear(notch.maxY, screen.maxY, "geometry: панель прижата к верхней кромке")

// Экран без чёлки (Mac mini): полоска fallback по центру.
let plain = ShelfGeometry.collapsedRect(screenFrame: screen,
                                        notchLeftMaxX: nil, notchRightMinX: nil, safeTop: 0)
expectNear(plain.width, ShelfGeometry.fallbackSize.width, "geometry: fallback-ширина")
expectNear(plain.midX, screen.midX, "geometry: fallback по центру")
expectNear(plain.maxY, screen.maxY, "geometry: fallback у верхней кромки")

// safeTop == 0 при наличии краёв выреза — тоже fallback (внешний монитор).
let weird = ShelfGeometry.collapsedRect(screenFrame: screen,
                                        notchLeftMaxX: 624, notchRightMinX: 816, safeTop: 0)
expectNear(weird.height, ShelfGeometry.fallbackSize.height, "geometry: нулевой safeTop -> fallback")

// Раскрытая полка: не уже минимума, контент целиком под чёлкой.
let expanded = ShelfGeometry.expandedRect(screenFrame: screen, collapsed: notch)
expect(expanded.width >= ShelfGeometry.minExpandedWidth, true, "geometry: раскрытая не уже минимума")
expectNear(expanded.height, notch.height + ShelfGeometry.contentHeight, "geometry: высота = чёлка + контент")
expectNear(expanded.maxY, screen.maxY, "geometry: раскрытая прижата к кромке")
expectNear(expanded.midX, screen.midX.rounded(), "geometry: раскрытая по центру экрана")

// MARK: - Прогресс раскрытия: клампится и растёт с высотой окна

expectNear(ShelfGeometry.expandProgress(height: 32, topInset: 32), 0, "progress: свернуто = 0")
expectNear(ShelfGeometry.expandProgress(height: 32 + ShelfGeometry.contentHeight, topInset: 32), 1, "progress: раскрыто = 1")
expectNear(ShelfGeometry.expandProgress(height: 32 + ShelfGeometry.contentHeight / 2, topInset: 32), 0.5, "progress: середина = 0.5")
expectNear(ShelfGeometry.expandProgress(height: 20, topInset: 32), 0, "progress: не уходит ниже 0")
expectNear(ShelfGeometry.expandProgress(height: 1000, topInset: 32), 1, "progress: не уходит выше 1")

// Контент проявляется во второй половине анимации.
expectNear(ShelfGeometry.contentAlpha(progress: 0), 0, "alpha: в начале невидим")
expectNear(ShelfGeometry.contentAlpha(progress: 0.4), 0, "alpha: до 0.4 невидим")
expectNear(ShelfGeometry.contentAlpha(progress: 0.7), 0.5, "alpha: на 0.7 — половина")
expectNear(ShelfGeometry.contentAlpha(progress: 1), 1, "alpha: в конце полностью виден")

// MARK: - Превью: вписывание с сохранением пропорций (искажение = уродливые миниатюры)

let box = CGRect(x: 0, y: 0, width: 48, height: 48)
if let wide = ShelfGeometry.aspectFitRect(content: CGSize(width: 100, height: 50), in: box) {
    expectNear(wide.width, 48, "fit: широкая картинка — во всю ширину")
    expectNear(wide.height, 24, "fit: широкая картинка — пропорциональная высота")
    expectNear(wide.midY, box.midY, "fit: широкая — по центру вертикали")
} else { print("FAIL fit: широкая вернула nil"); failures += 1 }

if let tall = ShelfGeometry.aspectFitRect(content: CGSize(width: 50, height: 100), in: box) {
    expectNear(tall.height, 48, "fit: высокая картинка — во всю высоту")
    expectNear(tall.width, 24, "fit: высокая картинка — пропорциональная ширина")
    expectNear(tall.midX, box.midX, "fit: высокая — по центру горизонтали")
} else { print("FAIL fit: высокая вернула nil"); failures += 1 }

if let square = ShelfGeometry.aspectFitRect(content: CGSize(width: 200, height: 200), in: box) {
    expectNear(square.width, 48, "fit: квадрат заполняет бокс")
} else { print("FAIL fit: квадрат вернул nil"); failures += 1 }

expect(ShelfGeometry.aspectFitRect(content: .zero, in: box) == nil, true, "fit: нулевой размер -> nil")

// MARK: - Безопасность: peerHost попадает в аргументы ssh/rsync — значение,
// похожее на опцию или shell-конструкцию, обязано отклоняться

expect(PeerHost.isValid("my-mac-mini"), true, "peer: простое имя")
expect(PeerHost.isValid("my-mac-mini.tailf00d.ts.net"), true, "peer: FQDN")
expect(PeerHost.isValid("100.108.22.20"), true, "peer: IPv4")
expect(PeerHost.isValid("alice@my-mac-mini"), true, "peer: user@host")
expect(PeerHost.isValid("a_user.name@host-1.example.com"), true, "peer: user с ._-")

expect(PeerHost.isValid(""), false, "peer: пустое отклонено")
expect(PeerHost.isValid("-oProxyCommand=evil"), false, "peer: опция ssh отклонена")
expect(PeerHost.isValid("host -oProxyCommand=evil"), false, "peer: пробел + опция отклонены")
expect(PeerHost.isValid("host;rm -rf ~"), false, "peer: точка с запятой отклонена")
expect(PeerHost.isValid("host`id`"), false, "peer: backticks отклонены")
expect(PeerHost.isValid("host$(id)"), false, "peer: $() отклонено")
expect(PeerHost.isValid("host\nevil"), false, "peer: перевод строки отклонён")
expect(PeerHost.isValid("a@b@c"), false, "peer: двойной @ отклонён")
expect(PeerHost.isValid("-user@host"), false, "peer: user с дефиса отклонён")
expect(PeerHost.isValid(".host"), false, "peer: host с точки отклонён")
expect(PeerHost.isValid("host..name"), false, "peer: двойная точка отклонена")
expect(PeerHost.isValid(String(repeating: "a", count: 400)), false, "peer: сверхдлинное отклонено")

// MARK: - итог

if failures > 0 {
    print("\(failures) проверок упало")
    exit(1)
}
print("Все проверки прошли")
