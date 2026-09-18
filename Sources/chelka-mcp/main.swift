// MCP-сервер Chelka: полка (~/Shelf) как инструменты для ИИ-агентов
// (Claude Code, Codex и любой другой MCP-клиент). JSON-RPC 2.0 поверх stdio,
// сообщения разделены переводом строки; внешних зависимостей нет.
//
// Инструменты:
//   shelf_list    — файлы на полке
//   shelf_grab    — забрать файл с полки в каталог (по умолчанию текущий)
//   shelf_put     — положить файл на полку; send=true — и отправить на пира
//   shelf_remove  — убрать файл с полки (в Корзину)
import Foundation
import ChelkaCore

let shelfDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Shelf", isDirectory: true)

// MARK: - JSON-RPC

func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
}

func reply(_ id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func replyError(_ id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func replyText(_ id: Any, _ text: String, isError: Bool = false) {
    reply(id, result: ["content": [["type": "text", "text": text]], "isError": isError])
}

// MARK: - инструменты

let toolDefinitions: [[String: Any]] = [
    [
        "name": "shelf_list",
        "description": "Список файлов на полке Chelka (~/Shelf): имя, размер, дата изменения.",
        "inputSchema": ["type": "object", "properties": [String: Any](), "required": [String]()],
    ],
    [
        "name": "shelf_grab",
        "description": "Забрать файл с полки Chelka: копирует ~/Shelf/<name> в каталог dest (по умолчанию текущий каталог). keep=false — после копирования убрать файл с полки в Корзину.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Имя файла на полке (из shelf_list)"],
                "dest": ["type": "string", "description": "Каталог назначения; по умолчанию текущий"],
                "keep": ["type": "boolean", "description": "Оставить файл на полке (по умолчанию true)"],
            ],
            "required": ["name"],
        ],
    ],
    [
        "name": "shelf_put",
        "description": "Положить файл на полку Chelka этой машины. send=true — дополнительно отправить на вторую машину (peerHost из настроек Chelka), как это делает само приложение.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Путь к файлу (абсолютный или от текущего каталога)"],
                "send": ["type": "boolean", "description": "Отправить на пира (по умолчанию false)"],
            ],
            "required": ["path"],
        ],
    ],
    [
        "name": "shelf_remove",
        "description": "Убрать файл с полки Chelka в Корзину.",
        "inputSchema": [
            "type": "object",
            "properties": ["name": ["type": "string", "description": "Имя файла на полке"]],
            "required": ["name"],
        ],
    ],
    [
        "name": "shelf_clear",
        "description": "Очистить полку Chelka целиком: все файлы в Корзину (восстановимо) — и локально, и на второй машине, если настроен peerHost.",
        "inputSchema": ["type": "object", "properties": [String: Any](), "required": [String]()],
    ],
]

func listShelf() -> String {
    let fm = FileManager.default
    let urls = (try? fm.contentsOfDirectory(
        at: shelfDir,
        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    if urls.isEmpty { return "Полка пуста." }
    let df = ISO8601DateFormatter()
    let lines = urls
        .sorted { (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast) }
        .map { url -> String in
            let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let size = rv?.isDirectory == true ? "папка" : "\(rv?.fileSize ?? 0) байт"
            let date = rv?.contentModificationDate.map(df.string(from:)) ?? "?"
            return "\(url.lastPathComponent)\t\(size)\t\(date)"
        }
    return "Файлы на полке (\(lines.count)):\n" + lines.joined(separator: "\n")
}

func mtime(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func grab(_ args: [String: Any]) -> (String, Bool) {
    guard let name = args["name"] as? String, ShelfName.isSafe(name) else {
        return ("Недопустимое имя файла.", true)
    }
    let src = shelfDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("На полке нет файла «\(name)». Список — shelf_list.", true)
    }
    let destDir = URL(fileURLWithPath: (args["dest"] as? String) ?? FileManager.default.currentDirectoryPath,
                      isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: destDir.path)) ?? [])
        let dst = destDir.appendingPathComponent(Naming.uniqueName(name, existing: existing))
        try FileManager.default.copyItem(at: src, to: dst)
        if (args["keep"] as? Bool) == false {
            try? FileManager.default.trashItem(at: src, resultingItemURL: nil)
        }
        return ("Файл скопирован: \(dst.path)", false)
    } catch {
        return ("Не удалось забрать «\(name)»: \(error.localizedDescription)", true)
    }
}

func put(_ args: [String: Any]) -> (String, Bool) {
    guard let rawPath = args["path"] as? String, !rawPath.isEmpty else {
        return ("Нужен параметр path.", true)
    }
    let src = URL(fileURLWithPath: rawPath, relativeTo:
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("Файла нет: \(src.path)", true)
    }
    do {
        try FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: shelfDir.path)) ?? [])
        let name = Naming.uniqueName(src.lastPathComponent, existing: existing)
        let dst = shelfDir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dst)

        guard (args["send"] as? Bool) == true else {
            return ("Файл на полке этой машины: \(name). На пира не отправлялся (send=false).", false)
        }
        guard let peerRaw = UserDefaults(suiteName: "dev.mike.Chelka")?.string(forKey: "peerHost"),
              case let peer = peerRaw.trimmingCharacters(in: .whitespaces),
              !peer.isEmpty else {
            return ("Файл на полке (\(name)), но peerHost не настроен — отправить некуда.", true)
        }
        guard PeerHost.isValid(peer) else {
            return ("Файл на полке (\(name)), но peerHost «\(peer)» не прошёл валидацию.", true)
        }
        guard runProcess(PushPlan.sshExecutable, PushPlan.mkdirArgs(peer: peer)) == nil else {
            return ("Файл на полке (\(name)), но пир недоступен по ssh.", true)
        }
        if let err = runProcess(PushPlan.rsyncExecutable, PushPlan.rsyncArgs(filePath: dst.path, peer: peer)) {
            return ("Файл на полке (\(name)), но отправка на \(peer) не удалась: \(err)", true)
        }
        return ("Файл на полке и отправлен на \(peer): \(name)", false)
    } catch {
        return ("Не удалось положить на полку: \(error.localizedDescription)", true)
    }
}

func remove(_ args: [String: Any]) -> (String, Bool) {
    guard let name = args["name"] as? String, ShelfName.isSafe(name) else {
        return ("Недопустимое имя файла.", true)
    }
    let src = shelfDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("На полке нет файла «\(name)».", true)
    }
    do {
        try FileManager.default.trashItem(at: src, resultingItemURL: nil)
        return ("«\(name)» убран с полки в Корзину.", false)
    } catch {
        return ("Не удалось убрать «\(name)»: \(error.localizedDescription)", true)
    }
}

func clearShelf(_ args: [String: Any]) -> (String, Bool) {
    let urls = (try? FileManager.default.contentsOfDirectory(
        at: shelfDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    var trashed = 0
    var failed: [String] = []
    for url in urls {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            trashed += 1
        } catch {
            failed.append(url.lastPathComponent)
        }
    }
    var report = urls.isEmpty ? "Локальная полка уже пуста."
        : "Локальная полка: \(trashed) файл(ов) в Корзине."
    var isError = false
    if !failed.isEmpty {
        report += " Не удалось: \(failed.joined(separator: ", "))."
        isError = true
    }

    // пира чистим всегда, если он настроен — кнопка одна и чистит всё
    if let peerRaw = UserDefaults(suiteName: "dev.mike.Chelka")?.string(forKey: "peerHost"),
       case let peer = peerRaw.trimmingCharacters(in: .whitespaces),
       !peer.isEmpty {
        guard PeerHost.isValid(peer) else {
            return (report + " Полка пира не тронута: peerHost не прошёл валидацию.", true)
        }
        if let err = runProcess(PushPlan.sshExecutable, PushPlan.clearArgs(peer: peer)) {
            return (report + " Очистка на \(peer) не удалась: \(err) (старая обёртка на пире?)", true)
        }
        report += " Полка на \(peer) очищена (в её Корзину)."
    }
    return (report, isError)
}

/// nil — успех; иначе текст ошибки (stderr или код).
func runProcess(_ tool: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let errPipe = Pipe()
    p.standardOutput = FileHandle.nullDevice
    p.standardError = errPipe
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return error.localizedDescription }
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    if p.terminationStatus == 0 { return nil }
    let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (msg?.isEmpty == false ? msg! : "код \(p.terminationStatus)")
}

// MARK: - главный цикл

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let method = msg["method"] as? String else { continue }
    let id = msg["id"]

    switch method {
    case "initialize":
        let params = msg["params"] as? [String: Any]
        let version = (params?["protocolVersion"] as? String) ?? "2024-11-05"
        reply(id ?? NSNull(), result: [
            "protocolVersion": version,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "chelka", "version": "0.2.0"],
        ])
    case "notifications/initialized", "notifications/cancelled":
        continue // уведомления без ответа
    case "ping":
        reply(id ?? NSNull(), result: [String: Any]())
    case "tools/list":
        reply(id ?? NSNull(), result: ["tools": toolDefinitions])
    case "tools/call":
        guard let id else { continue }
        let params = msg["params"] as? [String: Any]
        let args = (params?["arguments"] as? [String: Any]) ?? [:]
        switch params?["name"] as? String {
        case "shelf_list":
            replyText(id, listShelf())
        case "shelf_grab":
            let (text, isError) = grab(args)
            replyText(id, text, isError: isError)
        case "shelf_put":
            let (text, isError) = put(args)
            replyText(id, text, isError: isError)
        case "shelf_remove":
            let (text, isError) = remove(args)
            replyText(id, text, isError: isError)
        case "shelf_clear":
            let (text, isError) = clearShelf(args)
            replyText(id, text, isError: isError)
        default:
            replyError(id, code: -32602, message: "Неизвестный инструмент")
        }
    default:
        if let id { replyError(id, code: -32601, message: "Метод не поддерживается: \(method)") }
    }
}
