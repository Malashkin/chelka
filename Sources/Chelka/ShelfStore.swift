import AppKit
import ChelkaCore

/// Модель полки: папка ~/Shelf. Полка отображает её содержимое,
/// watcher ловит файлы, прилетевшие извне (rsync с другой машины).
final class ShelfStore {
    static let dir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Shelf", isDirectory: true)

    private(set) var files: [URL] = []
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var reloadScheduled = false
    /// Имена, добавленные локальным дропом (их quarantine не трогаем).
    private var locallyAdded: Set<String> = []
    /// Имена, виденные на полке (устаревший ключ — мигрирует в seenDates).
    private static let knownNamesKey = "knownShelfNames"
    /// Дата появления каждого файла на полке (имя -> epoch). Переживает
    /// перезапуск: и карантин, и автоочистка работают по этой памяти.
    private static let seenDatesKey = "shelfSeenDates"
    /// Автоочистка: файлы старше N суток на полке уезжают в Корзину.
    /// defaults write dev.mike.Chelka retentionDays N (0 — выключить).
    private static var retentionDays: Int {
        UserDefaults.standard.object(forKey: "retentionDays") == nil
            ? 7 : UserDefaults.standard.integer(forKey: "retentionDays")
    }

    init() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        reload()
        watch()
        // watcher молчит без событий — автоочистке нужен и таймер
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        var urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        let defaults = UserDefaults.standard
        let now = Date()
        let current = Set(urls.map { $0.lastPathComponent })

        // память о виденном: миграция со старого ключа при необходимости
        var seenRaw = (defaults.dictionary(forKey: Self.seenDatesKey) as? [String: Double]) ?? [:]
        let legacy = defaults.stringArray(forKey: Self.knownNamesKey)
        if seenRaw.isEmpty, let legacy {
            for name in legacy { seenRaw[name] = now.timeIntervalSince1970 }
        }
        let hadState = !seenRaw.isEmpty || legacy != nil

        // файлы, появившиеся не через локальный дроп, пришли извне (rsync
        // с пира) — ставим им quarantine, rsync этого не делает
        let known: Set<String>? = hadState ? Set(seenRaw.keys) : nil
        for url in urls where Sync.newcomers(current: current, known: known,
                                             locallyAdded: locallyAdded).contains(url.lastPathComponent) {
            Quarantine.markIfNeeded(url)
        }

        var seen = Sync.updatedSeen(current: current,
                                    seen: seenRaw.mapValues { Date(timeIntervalSince1970: $0) },
                                    now: now)

        // автоочистка: пролежавшее на полке дольше retentionDays — в Корзину
        let expired = Sync.expired(seen: seen, now: now, retentionDays: Self.retentionDays)
        if !expired.isEmpty {
            for name in expired {
                try? FileManager.default.trashItem(at: Self.dir.appendingPathComponent(name),
                                                   resultingItemURL: nil)
                seen.removeValue(forKey: name)
            }
            NSLog("Chelka: автоочистка — \(expired.count) файл(ов) старше \(Self.retentionDays) дн. убраны в Корзину")
            urls.removeAll { expired.contains($0.lastPathComponent) }
        }

        defaults.set(seen.mapValues { $0.timeIntervalSince1970 }, forKey: Self.seenDatesKey)
        defaults.removeObject(forKey: Self.knownNamesKey)
        locallyAdded.formIntersection(current)

        files = urls.sorted { mtime($0) > mtime($1) }
        onChange?()
    }

    private func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Копирует задропленные файлы в папку полки; возвращает URL созданных копий.
    func add(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var added: [URL] = []
        for src in urls {
            // drag файла с самой полки на полку — не дублируем
            if src.deletingLastPathComponent().standardizedFileURL.path == Self.dir.standardizedFileURL.path { continue }
            let name = Naming.uniqueName(src.lastPathComponent, existing: currentNames())
            let dst = Self.dir.appendingPathComponent(name)
            locallyAdded.insert(name)
            do {
                try fm.copyItem(at: src, to: dst)
                added.append(dst)
            } catch {
                NSLog("Chelka: не удалось скопировать \(src.path): \(error.localizedDescription)")
            }
        }
        reload()
        return added
    }

    func remove(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        reload()
    }

    /// Очистить полку: все файлы — в Корзину (восстановимо).
    func clear() {
        for url in files {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        reload()
    }

    private func currentNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: Self.dir.path)) ?? [])
    }

    private func watch() {
        let fd = open(Self.dir.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Chelka: не удалось открыть \(Self.dir.path) для наблюдения")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    // rsync генерирует серию событий на один файл — дебаунс
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }
}
