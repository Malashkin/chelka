import AppKit

/// Push файла на удалённую машину: rsync поверх ssh по Tailscale MagicDNS.
/// Пир задаётся `defaults write dev.mike.Chelka peerHost <host>`; пусто — полка локальная.
/// Push-only: отправляем только то, что задропили на этой машине (см. ADR-0001).
final class Transport {
    enum Status { case uploading, sent, failed }

    private(set) var statuses: [String: Status] = [:]
    var onChange: (() -> Void)?

    private let workQueue = DispatchQueue(label: "chelka.transport")
    private static let maxAttempts = 5
    private static let retryDelay: TimeInterval = 15

    var peerHost: String? {
        guard let v = UserDefaults.standard.string(forKey: "peerHost"),
              !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v.trimmingCharacters(in: .whitespaces)
    }

    func status(for url: URL) -> Status? { statuses[url.lastPathComponent] }

    func push(_ file: URL, attempt: Int = 1) {
        guard let peer = peerHost else { return }
        set(file, .uploading)
        workQueue.async { [self] in
            let ok = runPush(file: file, peer: peer)
            DispatchQueue.main.async { [self] in
                if ok {
                    set(file, .sent)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                        if statuses[file.lastPathComponent] == .sent { clear(file) }
                    }
                } else if attempt < Self.maxAttempts {
                    NSLog("Chelka: отправка не удалась (попытка \(attempt)), повтор через \(Int(Self.retryDelay)) с: \(file.lastPathComponent)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [self] in
                        push(file, attempt: attempt + 1)
                    }
                } else {
                    set(file, .failed)
                }
            }
        }
    }

    private func set(_ file: URL, _ s: Status) {
        statuses[file.lastPathComponent] = s
        onChange?()
    }

    private func clear(_ file: URL) {
        statuses.removeValue(forKey: file.lastPathComponent)
        onChange?()
    }

    // ssh mkdir -p + rsync -a. rsync пишет во временный дот-файл и атомарно
    // переименовывает в конце — watcher на приёмнике не увидит недокачанное
    // (скрытые файлы полка не показывает).
    private func runPush(file: URL, peer: String) -> Bool {
        // accept-new: первый коннект на новое имя не должен падать на вопросе
        // про host key — BatchMode спросить не может
        let sshOptsList = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                           "-o", "StrictHostKeyChecking=accept-new"]
        let sshOptsLine = "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
        guard run("/usr/bin/ssh", sshOptsList + [peer, "mkdir -p Shelf"]) else { return false }
        return run("/usr/bin/rsync", ["-a", "-e", sshOptsLine, file.path, "\(peer):Shelf/"])
    }

    private func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch {
            NSLog("Chelka: не удалось запустить \(tool): \(error.localizedDescription)")
            return false
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            NSLog("Chelka: \(tool) завершился с кодом \(p.terminationStatus): \(msg)")
            return false
        }
        return true
    }
}
