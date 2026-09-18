import Foundation

/// Аргументы транспортных команд — единый источник для приложения и MCP-сервера.
/// Инварианты безопасности (см. docs/security): BatchMode, строгая проверка
/// host key, "--" перед хостом, --ignore-existing на приёмнике.
public enum PushPlan {
    public static let sshExecutable = "/usr/bin/ssh"
    public static let rsyncExecutable = "/usr/bin/rsync"

    public static let sshOptions = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                                    "-o", "StrictHostKeyChecking=yes"]

    /// ssh <opts> -- <peer> "mkdir -p Shelf"
    public static func mkdirArgs(peer: String) -> [String] {
        sshOptions + ["--", peer, "mkdir -p Shelf"]
    }

    /// ssh <opts> -- <peer> "chelka-clear" — очистка полки пира (только в
    /// Корзину; на приёмнике команду исполняет обёртка chelka-receive.sh)
    public static func clearArgs(peer: String) -> [String] {
        sshOptions + ["--", peer, "chelka-clear"]
    }

    /// rsync -a --ignore-existing -e "ssh <opts>" <file> <peer>:Shelf/
    public static func rsyncArgs(filePath: String, peer: String) -> [String] {
        ["-a", "--ignore-existing",
         "-e", sshExecutable + " " + sshOptions.joined(separator: " "),
         filePath, "\(peer):Shelf/"]
    }
}

/// Имя файла на полке, безопасное для операций по имени (grab/remove):
/// только простое имя без разделителей, скрытых файлов и path traversal.
public enum ShelfName {
    public static func isSafe(_ name: String) -> Bool {
        !name.isEmpty
            && name.count <= 255
            && !name.contains("/")
            && !name.contains("\0")
            && !name.hasPrefix(".")
    }
}
