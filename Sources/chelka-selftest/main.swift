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

// MARK: - Карантин: помечать только прилетевшее извне, не локальные дропы

expect(Sync.newcomers(current: ["a", "b"], known: ["a"], locallyAdded: []), ["b"],
       "sync: новый файл извне — новичок")
expect(Sync.newcomers(current: ["a", "b"], known: ["a"], locallyAdded: ["b"]), [],
       "sync: локальный дроп — не новичок")
expect(Sync.newcomers(current: ["a"], known: nil, locallyAdded: []), [],
       "sync: первый скан без состояния — никого не метим")
expect(Sync.newcomers(current: ["a"], known: ["a", "b"], locallyAdded: []), [],
       "sync: удаление файла новичков не создаёт")

// MARK: - Обёртка chelka-receive.sh: транспортный ключ не должен уметь ничего,
// кроме приёма файлов в ~/Shelf

func receive(_ sshCommand: String?) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [FileManager.default.currentDirectoryPath + "/scripts/chelka-receive.sh"]
    var env = ProcessInfo.processInfo.environment
    env["CHELKA_RECEIVE_TEST"] = "1"
    env["SSH_ORIGINAL_COMMAND"] = sshCommand
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try! p.run()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    return (p.terminationStatus, out)
}

let serverCmd = "rsync --server -logDtpre.iLsfxCIvu --ignore-existing . Shelf/"
expect(receive(serverCmd).code, 0, "receive: приём rsync в Shelf/ разрешён")
expect(receive(serverCmd).out.hasPrefix("WOULD-RUN: rsync --server"), true,
       "receive: исполняется именно rsync --server")
expect(receive("mkdir -p Shelf").code, 0, "receive: mkdir Shelf разрешён")

expect(receive(nil).code, 1, "receive: интерактивный shell отклонён")
expect(receive("id").code, 1, "receive: произвольная команда отклонена")
expect(receive("rsync --server --sender -logDtpre. . Shelf/").code, 1,
       "receive: чтение файлов (--sender) отклонено")
expect(receive("rsync --server -logDtpre. . Documents/").code, 1,
       "receive: запись мимо Shelf/ отклонена")
expect(receive("rsync --server -logDtpre. . Shelf/; id").code, 1,
       "receive: точка с запятой отклонена")
expect(receive("rsync --server -logDtpre. . Shelf/ && id").code, 1,
       "receive: && отклонено")
expect(receive("bash -c 'rsync --server . Shelf/'").code, 1,
       "receive: обёртка в bash отклонена")
expect(receive("chelka-clear").code, 0, "receive: команда очистки разрешена")
expect(receive("chelka-clear").out.hasPrefix("WOULD-CLEAR"), true,
       "receive: очистка — именно ветка clear")
expect(receive("chelka-clear; id").code, 1, "receive: clear с метасимволом отклонён")
expect(receive("chelka-clear-all").code, 1, "receive: похожая команда отклонена")

// clear в боевом режиме — на подставном HOME: файлы уезжают в Корзину
do {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("chelka-clear-test-\(ProcessInfo.processInfo.processIdentifier)")
    let shelf = tmp.appendingPathComponent("Shelf")
    try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
    try "a".write(to: shelf.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "b".write(to: shelf.appendingPathComponent("файл b.txt"), atomically: true, encoding: .utf8)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [FileManager.default.currentDirectoryPath + "/scripts/chelka-receive.sh"]
    var env = ProcessInfo.processInfo.environment
    env["SSH_ORIGINAL_COMMAND"] = "chelka-clear"
    env["HOME"] = tmp.path
    env.removeValue(forKey: "CHELKA_RECEIVE_TEST")
    p.environment = env
    try p.run()
    p.waitUntilExit()

    let shelfLeft = (try? FileManager.default.contentsOfDirectory(atPath: shelf.path))?.count ?? -1
    let inTrash = (try? FileManager.default.contentsOfDirectory(atPath: tmp.appendingPathComponent(".Trash").path))?.count ?? -1
    expect(p.terminationStatus, 0, "clear: боевой запуск успешен")
    expect(shelfLeft, 0, "clear: полка пуста")
    expect(inTrash, 2, "clear: оба файла в Корзине (включая имя с пробелом)")
    try? FileManager.default.removeItem(at: tmp)
} catch {
    print("FAIL clear: \(error)")
    failures += 1
}

// MARK: - Автоочистка: возраст считается от появления на полке, не от mtime

let t0 = Date(timeIntervalSince1970: 1_000_000)
let day: Double = 86400

let seen0 = Sync.updatedSeen(current: ["a", "b"], seen: ["a": t0], now: t0.addingTimeInterval(day))
expect(seen0["a"], t0, "seen: у старого файла дата сохраняется")
expect(seen0["b"], t0.addingTimeInterval(day), "seen: новый получает текущую дату")
expect(Sync.updatedSeen(current: ["a"], seen: ["a": t0, "gone": t0], now: t0)["gone"], nil,
       "seen: записи об удалённых выбрасываются")

let week = ["old": t0, "fresh": t0.addingTimeInterval(6 * day)]
expect(Sync.expired(seen: week, now: t0.addingTimeInterval(7.5 * day), retentionDays: 7), ["old"],
       "expire: старше недели — просрочен, свежий — нет")
expect(Sync.expired(seen: week, now: t0.addingTimeInterval(7 * day), retentionDays: 7), [],
       "expire: ровно 7 дней — ещё не просрочен")
expect(Sync.expired(seen: week, now: t0.addingTimeInterval(100 * day), retentionDays: 0), [],
       "expire: retentionDays 0 — автоочистка выключена")

// MARK: - PushPlan.clearArgs

let cl = PushPlan.clearArgs(peer: "peer-host")
expect(cl.contains("--"), true, "clear-args: '--' отделяет опции от хоста")
expect(cl.last, "chelka-clear", "clear-args: единственная команда — chelka-clear")

// MARK: - PushPlan: инварианты транспорта зашиты в аргументы (общие для app и MCP)

let mk = PushPlan.mkdirArgs(peer: "peer-host")
expect(mk.contains("--"), true, "push: '--' отделяет опции от хоста")
expect(mk.last, "mkdir -p Shelf", "push: единственная команда — mkdir Shelf")
expect(mk.joined(separator: " ").contains("StrictHostKeyChecking=yes"), true, "push: строгая проверка host key (ssh)")

let rs = PushPlan.rsyncArgs(filePath: "/tmp/a.txt", peer: "peer-host")
expect(rs.contains("--ignore-existing"), true, "push: приёмник не перезаписывается")
expect(rs.last, "peer-host:Shelf/", "push: назначение — только Shelf/")
expect(rs.joined(separator: " ").contains("BatchMode=yes"), true, "push: BatchMode (без интерактива)")

// MARK: - ShelfName: операции по имени не должны выходить за пределы полки

expect(ShelfName.isSafe("отчёт.pdf"), true, "name: обычное имя допустимо")
expect(ShelfName.isSafe("a/b.txt"), false, "name: разделитель пути отклонён")
expect(ShelfName.isSafe("../secret"), false, "name: path traversal отклонён")
expect(ShelfName.isSafe(".ssh"), false, "name: скрытые файлы отклонены")
expect(ShelfName.isSafe(""), false, "name: пустое отклонено")

// MARK: - итог

if failures > 0 {
    print("\(failures) проверок упало")
    exit(1)
}
print("Все проверки прошли")
