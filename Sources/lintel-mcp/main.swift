// MCP-сервер Lintel: полка (~/Shelf) как инструменты для ИИ-агентов
// (Claude Code, Codex и любой другой MCP-клиент). JSON-RPC 2.0 поверх stdio,
// сообщения разделены переводом строки; внешних зависимостей нет.
//
// Инструменты:
//   shelf_list    — файлы на полке
//   shelf_grab    — забрать файл с полки в каталог (по умолчанию текущий)
//   shelf_put     — положить файл на полку; send=true — и отправить на пира
//   shelf_remove  — убрать файл с полки (в Корзину)
import Foundation
import LintelCore

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
        "description": "List files on the Lintel shelf (~/Shelf): name, size, modification date.",
        "inputSchema": ["type": "object", "properties": [String: Any](), "required": [String]()],
    ],
    [
        "name": "shelf_grab",
        "description": "Take a file from the Lintel shelf: copies ~/Shelf/<name> into the dest directory (current directory by default). keep=false moves the file from the shelf to the Trash after copying.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "File name on the shelf (from shelf_list)"],
                "dest": ["type": "string", "description": "Destination directory; current directory by default"],
                "keep": ["type": "boolean", "description": "Keep the file on the shelf (default true)"],
            ],
            "required": ["name"],
        ],
    ],
    [
        "name": "shelf_put",
        "description": "Put a file on this Mac's Lintel shelf. send=true also sends it to the other Mac (peerHost from Lintel settings), the same way the app does.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Path to the file (absolute or relative to the current directory)"],
                "send": ["type": "boolean", "description": "Send to the peer (default false)"],
            ],
            "required": ["path"],
        ],
    ],
    [
        "name": "shelf_remove",
        "description": "Move a file from the Lintel shelf to the Trash.",
        "inputSchema": [
            "type": "object",
            "properties": ["name": ["type": "string", "description": "File name on the shelf"]],
            "required": ["name"],
        ],
    ],
    [
        "name": "shelf_clear",
        "description": "Clear the whole Lintel shelf: every file goes to the Trash (recoverable), both locally and on the other Mac if peerHost is set.",
        "inputSchema": ["type": "object", "properties": [String: Any](), "required": [String]()],
    ],
]

func listShelf() -> String {
    let fm = FileManager.default
    let urls = (try? fm.contentsOfDirectory(
        at: shelfDir,
        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    if urls.isEmpty { return "The shelf is empty." }
    let df = ISO8601DateFormatter()
    let lines = urls
        .sorted { (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast) }
        .map { url -> String in
            let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let size = rv?.isDirectory == true ? "folder" : "\(rv?.fileSize ?? 0) bytes"
            let date = rv?.contentModificationDate.map(df.string(from:)) ?? "?"
            return "\(url.lastPathComponent)\t\(size)\t\(date)"
        }
    return "Files on the shelf (\(lines.count)):\n" + lines.joined(separator: "\n")
}

func mtime(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func grab(_ args: [String: Any]) -> (String, Bool) {
    guard let name = args["name"] as? String, ShelfName.isSafe(name) else {
        return ("Invalid file name.", true)
    }
    let src = shelfDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("No file \"\(name)\" on the shelf. See shelf_list.", true)
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
        return ("File copied: \(dst.path)", false)
    } catch {
        return ("Failed to take \"\(name)\": \(error.localizedDescription)", true)
    }
}

func put(_ args: [String: Any]) -> (String, Bool) {
    guard let rawPath = args["path"] as? String, !rawPath.isEmpty else {
        return ("The path parameter is required.", true)
    }
    let src = URL(fileURLWithPath: rawPath, relativeTo:
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("No such file: \(src.path)", true)
    }
    do {
        try FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: shelfDir.path)) ?? [])
        let name = Naming.uniqueName(src.lastPathComponent, existing: existing)
        let dst = shelfDir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dst)

        guard (args["send"] as? Bool) == true else {
            return ("File is on this Mac's shelf: \(name). Not sent to the peer (send=false).", false)
        }
        guard let peerRaw = Settings.string("peerHost"),
              case let peer = peerRaw.trimmingCharacters(in: .whitespaces),
              !peer.isEmpty else {
            return ("File is on the shelf (\(name)), but peerHost is not set, so there is nowhere to send it.", true)
        }
        guard PeerHost.isValid(peer) else {
            return ("File is on the shelf (\(name)), but peerHost \"\(peer)\" failed validation.", true)
        }
        guard runProcess(PushPlan.sshExecutable, PushPlan.mkdirArgs(peer: peer)) == nil else {
            return ("File is on the shelf (\(name)), but the peer is unreachable over ssh.", true)
        }
        if let err = runProcess(PushPlan.rsyncExecutable, PushPlan.rsyncArgs(filePath: dst.path, peer: peer)) {
            return ("File is on the shelf (\(name)), but sending to \(peer) failed: \(err)", true)
        }
        return ("File is on the shelf and sent to \(peer): \(name)", false)
    } catch {
        return ("Failed to put the file on the shelf: \(error.localizedDescription)", true)
    }
}

func remove(_ args: [String: Any]) -> (String, Bool) {
    guard let name = args["name"] as? String, ShelfName.isSafe(name) else {
        return ("Invalid file name.", true)
    }
    let src = shelfDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: src.path) else {
        return ("No file \"\(name)\" on the shelf.", true)
    }
    do {
        try FileManager.default.trashItem(at: src, resultingItemURL: nil)
        return ("\"\(name)\" moved from the shelf to the Trash.", false)
    } catch {
        return ("Failed to remove \"\(name)\": \(error.localizedDescription)", true)
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
    var report = urls.isEmpty ? "The local shelf is already empty."
        : "Local shelf: \(trashed) item(s) moved to the Trash."
    var isError = false
    if !failed.isEmpty {
        report += " Failed: \(failed.joined(separator: ", "))."
        isError = true
    }

    // пира чистим всегда, если он настроен — кнопка одна и чистит всё
    if let peerRaw = Settings.string("peerHost"),
       case let peer = peerRaw.trimmingCharacters(in: .whitespaces),
       !peer.isEmpty {
        guard PeerHost.isValid(peer) else {
            return (report + " Peer shelf left untouched: peerHost failed validation.", true)
        }
        if let err = runProcess(PushPlan.sshExecutable, PushPlan.clearArgs(peer: peer)) {
            return (report + " Clearing on \(peer) failed: \(err) (old wrapper on the peer?)", true)
        }
        report += " Shelf on \(peer) cleared (into its Trash)."
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
    return (msg?.isEmpty == false ? msg! : "exit code \(p.terminationStatus)")
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
            "serverInfo": ["name": "lintel", "version": "0.3.0"],
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
            replyError(id, code: -32602, message: "Unknown tool")
        }
    default:
        if let id { replyError(id, code: -32601, message: "Method not supported: \(method)") }
    }
}
