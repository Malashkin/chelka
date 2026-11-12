import Foundation

/// Валидация peerHost: значение из настроек попадает в аргументы ssh/rsync,
/// поэтому не должно быть способно превратиться в опцию (`-oProxyCommand=...`)
/// или сломать вызов. Допускаем только hostname / FQDN / IPv4, опционально
/// с префиксом `user@`.
public enum PeerHost {
    public static func isValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 253 + 64 else { return false }

        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        let host: Substring
        switch parts.count {
        case 1:
            host = parts[0]
        case 2:
            guard isValidUser(parts[0]) else { return false }
            host = parts[1]
        default:
            return false
        }

        guard !host.isEmpty, host.count <= 253,
              host.first != "-", host.first != ".",
              !host.contains("..") else { return false }
        let hostChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return host.unicodeScalars.allSatisfy { hostChars.contains($0) }
    }

    private static func isValidUser(_ user: Substring) -> Bool {
        guard !user.isEmpty, user.count <= 64, user.first != "-" else { return false }
        let userChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return user.unicodeScalars.allSatisfy { userChars.contains($0) }
    }
}
