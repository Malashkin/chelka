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

    init() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        reload()
        watch()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
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
