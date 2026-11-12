import Foundation

/// Домены настроек и перенос со старого имени продукта.
/// До переименования приложение называлось Chelka и хранило настройки
/// (peerHost, retentionDays, fallbackTopOffset, deployPeer, история полки)
/// в домене dev.mike.Chelka. Новый bundle ID — dev.mike.Lintel.
public enum Settings {
    public static let domain = "dev.mike.Lintel"
    public static let legacyDomain = "dev.mike.Chelka"
    /// Метка в новом домене: перенос уже был, повторно не копировать
    /// (иначе удалённый пользователем ключ вернулся бы из старого домена).
    public static let migratedKey = "migratedFromChelka"

    /// Копирует ключи старого домена в новый — только отсутствующие,
    /// существующие значения нового домена не перезаписываются. Однократно.
    /// Старый домен не удаляется: откат на старую сборку остаётся рабочим.
    /// Возвращает число перенесённых ключей.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults = .standard,
                               from old: String = legacyDomain,
                               to new: String = domain) -> Int {
        var current = defaults.persistentDomain(forName: new) ?? [:]
        guard current[migratedKey] == nil else { return 0 }
        let legacy = defaults.persistentDomain(forName: old) ?? [:]
        var copied = 0
        for (key, value) in legacy where current[key] == nil {
            current[key] = value
            copied += 1
        }
        current[migratedKey] = true
        defaults.setPersistentDomain(current, forName: new)
        return copied
    }

    /// Строковое значение из нового домена, иначе из старого (для процессов
    /// вне бандла — MCP-сервер может запуститься раньше, чем приложение
    /// успело перенести настройки).
    public static func string(_ key: String, _ defaults: UserDefaults = .standard,
                              domains: [String] = [domain, legacyDomain]) -> String? {
        for d in domains {
            if let v = defaults.persistentDomain(forName: d)?[key] as? String { return v }
        }
        return nil
    }
}
