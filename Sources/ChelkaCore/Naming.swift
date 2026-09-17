import Foundation

public enum Naming {
    /// "a.pdf" при занятом имени -> "a-1.pdf", "a-2.pdf", ...
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var i = 1
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
    }
}
