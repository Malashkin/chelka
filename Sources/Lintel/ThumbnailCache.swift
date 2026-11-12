import AppKit
import QuickLookThumbnailing

/// Миниатюры файлов для полки: у картинок (а также PDF, видео) — превью
/// содержимого через QuickLook, у остальных остаётся иконка типа файла.
/// Генерация асинхронная; пока превью не готово, рисуется иконка.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Дёргается на главном потоке, когда готово новое превью — перерисовать полку.
    var onThumbnail: (() -> Void)?

    private var thumbs: [String: NSImage] = [:]
    private var pending: Set<String> = []
    /// Файлы, для которых превью не генерится (архивы и т.п.) — не дёргать
    /// QuickLook заново на каждой перерисовке.
    private var failed: Set<String> = []
    private let side: CGFloat = 48

    /// Превью, если уже готово; nil — ещё генерируется или не поддерживается.
    func thumbnail(for url: URL) -> NSImage? {
        if let t = thumbs[url.path] { return t }
        request(url)
        return nil
    }

    func prune(keeping urls: [URL]) {
        let keep = Set(urls.map(\.path))
        thumbs = thumbs.filter { keep.contains($0.key) }
        failed.formIntersection(keep)
    }

    private func request(_ url: URL) {
        let key = url.path
        guard !pending.contains(key), !failed.contains(key) else { return }
        pending.insert(key)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url,
                                               size: CGSize(width: side, height: side),
                                               scale: scale,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(key)
                if let cg = rep?.cgImage {
                    self.thumbs[key] = NSImage(cgImage: cg, size: .zero)
                    self.onThumbnail?()
                } else {
                    self.failed.insert(key) // типы без превью — останется иконка
                }
            }
        }
    }
}
