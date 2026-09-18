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
}
