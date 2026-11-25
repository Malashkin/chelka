import Foundation

/// Сводка полки для нижней строки: "12 files · 340 MB".
/// Папка, брошенная на полку, — один элемент; её размер считается целиком.
public enum ShelfSummary {
    /// "file" / "files".
    public static func filesWord(_ n: Int) -> String {
        abs(n) == 1 ? "file" : "files"
    }

    /// Размер как в Finder (десятичные единицы): "512 bytes", "1.5 MB", "340 MB".
    /// Меньше 10 единиц — с одним знаком после точки, иначе целое.
    public static func formatBytes(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        guard bytes >= 1000 else {
            let b = max(0, bytes)
            return b == 1 ? "1 byte" : "\(b) bytes"
        }
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // 999.6 KB при округлении дало бы «1000 КБ» — переходим к следующей единице
        if value.rounded() >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if value < 10 {
            let tenths = (value * 10).rounded()
            if tenths < 100 {
                let whole = Int(tenths) / 10, frac = Int(tenths) % 10
                return frac == 0 ? "\(whole) \(units[unit])" : "\(whole).\(frac) \(units[unit])"
            }
        }
        return "\(Int(value.rounded())) \(units[unit])"
    }

    /// Текст строки. `bytes == nil` — размер ещё считается.
    public static func text(count: Int, bytes: Int64?) -> String {
        guard count > 0 else { return "Shelf is empty" }
        let head = "\(count) \(filesWord(count))"
        guard let bytes else { return head + " · calculating…" }
        return head + " · " + formatBytes(bytes)
    }

    /// Суммарный размер элементов полки: файлы — их размер, папки и пакеты
    /// (.app и т.п.) — рекурсивно, включая скрытое внутри. Симлинки не
    /// разыменовываются. Нечитаемое пропускается.
    public static func totalBytes(of urls: [URL], fileManager fm: FileManager = .default) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        var total: Int64 = 0
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isDirectory == true, rv.isSymbolicLink != true {
                guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                             options: [], errorHandler: { _, _ in true }) else { continue }
                for case let inner as URL in en {
                    if let v = try? inner.resourceValues(forKeys: Set(keys)),
                       v.isDirectory != true {
                        total += Int64(v.fileSize ?? 0)
                    }
                }
            } else {
                total += Int64(rv.fileSize ?? 0)
            }
        }
        return total
    }
}
