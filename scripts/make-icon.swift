// Готовит иконку приложения из арта по сетке macOS: скруглённый квадрат
// 824x824 по центру прозрачного холста 1024x1024 (иначе иконка в Launchpad
// выглядит крупнее остальных и с прямыми углами — система отступы не рисует).
// Кроп берётся изнутри плитки арта, глубже её ободка и углов.
// Запуск: swift scripts/make-icon.swift Resources/icon-art.jpg Resources/AppIcon-1024.png
import AppKit

// Кадр внутри плитки исходника (origin — верхний левый угол):
// с запасом за белый ободок и скруглённые углы, чтобы в кадр не попали
// ни ободок, ни дуги. Подобрано под текущий icon-art.jpg (1024x1024).
let crop = CGRect(x: 193, y: 187, width: 638, height: 638)

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <src> <dst.png>\n".data(using: .utf8)!)
    exit(2)
}

guard let img = NSImage(contentsOfFile: args[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let cropped = cg.cropping(to: crop) else {
    FileHandle.standardError.write("не удалось открыть/кропнуть \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let out = 1024
// Сетка Apple для macOS-иконок: тело 824x824 по центру, радиус углов ~185.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185.4

let ctx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.addPath(CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                   transform: nil))
ctx.clip()
ctx.draw(cropped, in: body)

guard let result = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else {
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: args[2]))
print("OK: \(args[2])")
