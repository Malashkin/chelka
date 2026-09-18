import Foundation
import CoreServices

/// rsync не ставит com.apple.quarantine — файлы с пира миновали бы Gatekeeper.
/// Приёмник помечает их сам: исполняемое из полки без подтверждения не запустится.
enum Quarantine {
    static func markIfNeeded(_ url: URL) {
        var u = url
        if let rv = try? u.resourceValues(forKeys: [.quarantinePropertiesKey]),
           rv.quarantineProperties != nil {
            return
        }
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Chelka",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        do {
            try u.setResourceValues(values)
        } catch {
            NSLog("Chelka: не удалось поставить quarantine на \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
