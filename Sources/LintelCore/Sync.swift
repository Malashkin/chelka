import Foundation

public enum Sync {
    /// Какие файлы полки — «новоприбывшие» (появились не через локальный дроп):
    /// их приёмник помечает quarantine. `known` == nil — первый скан после
    /// запуска без сохранённого состояния, новичков не выделяем.
    public static func newcomers(current: Set<String>,
                                 known: Set<String>?,
                                 locallyAdded: Set<String>) -> Set<String> {
        guard let known else { return [] }
        return current.subtracting(known).subtracting(locallyAdded)
    }

    /// Обновить даты появления на полке: новым — `now`, у оставшихся дата
    /// сохраняется, записи об исчезнувших файлах выбрасываются.
    public static func updatedSeen(current: Set<String>,
                                   seen: [String: Date],
                                   now: Date) -> [String: Date] {
        var out: [String: Date] = [:]
        for name in current {
            out[name] = seen[name] ?? now
        }
        return out
    }

    /// Кто просрочен: на полке дольше `retentionDays` суток (по дате появления
    /// на полке, не по mtime файла — rsync/copy сохраняют исходные даты).
    /// retentionDays <= 0 — автоочистка выключена.
    public static func expired(seen: [String: Date],
                               now: Date,
                               retentionDays: Int) -> Set<String> {
        guard retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        return Set(seen.filter { $0.value < cutoff }.keys)
    }
}
