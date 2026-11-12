// Рисует иконку Lintel целиком в коде (без растрового арта) по сетке macOS:
// скруглённый квадрат 824x824 по центру прозрачного холста 1024x1024 (иначе
// иконка в Launchpad выглядит крупнее остальных и с прямыми углами).
//
// Сюжет: lintel — перемычка над проёмом. Сверху вырез экрана (чёлка),
// под ним тёмная полка с тремя файлами; зелёная точка — «доставлено на пира»,
// как статус в самом приложении.
//
// Запуск: swift scripts/make-icon.swift Resources/AppIcon-1024.png
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <dst.png>\n".data(using: .utf8)!)
    exit(2)
}

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Рисуем в координатах «от верхнего левого угла» — так проще читать раскладку.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}

// MARK: тело иконки: сетка Apple — 824x824 по центру, радиус ~185

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.addPath(rounded(body, 185.4))
ctx.clip()

// фон: ночное индиго сверху → фиолетовый снизу, тёплое свечение в углу
ctx.drawLinearGradient(gradient([rgb(0x141B3D), rgb(0x2B2F7A), rgb(0x6A3BC0)], [0, 0.45, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
ctx.drawRadialGradient(gradient([rgb(0xFF7A45, 0.75), rgb(0xFF7A45, 0)], [0, 1]),
                       startCenter: CGPoint(x: 160, y: 960), startRadius: 0,
                       endCenter: CGPoint(x: 160, y: 960), endRadius: 560, options: [])

// чёлка: чёрный вырез, приросший к верхнему краю, нижние углы скруглены
let notch = CGRect(x: 512 - 190, y: 60, width: 380, height: 150)
ctx.setFillColor(rgb(0x000000))
ctx.addPath(rounded(notch, 52))
ctx.fillPath()

// MARK: полка под чёлкой

let shelf = CGRect(x: 512 - 330, y: 290, width: 660, height: 330)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: rgb(0x000000, 0.45))
ctx.setFillColor(rgb(0x0B0C14, 0.82))
ctx.addPath(rounded(shelf, 64))
ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
ctx.setLineWidth(3)
ctx.addPath(rounded(shelf.insetBy(dx: 1.5, dy: 1.5), 62.5))
ctx.strokePath()

// три плитки-файла
let tile: CGFloat = 164
let gap: CGFloat = 34
let tilesY = shelf.midY - tile / 2
let firstX = shelf.midX - (tile * 3 + gap * 2) / 2
let tiles = (0..<3).map { CGRect(x: firstX + CGFloat($0) * (tile + gap), y: tilesY, width: tile, height: tile) }

// 1. документ с загнутым углом и строками текста
do {
    let r = tiles[0].insetBy(dx: 22, dy: 6)
    let fold: CGFloat = 40
    let page = CGMutablePath()
    page.move(to: CGPoint(x: r.minX + 12, y: r.minY))
    page.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
    page.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
    page.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 12))
    page.addQuadCurve(to: CGPoint(x: r.maxX - 12, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
    page.addLine(to: CGPoint(x: r.minX + 12, y: r.maxY))
    page.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 12), control: CGPoint(x: r.minX, y: r.maxY))
    page.addLine(to: CGPoint(x: r.minX, y: r.minY + 12))
    page.addQuadCurve(to: CGPoint(x: r.minX + 12, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
    page.closeSubpath()
    ctx.setFillColor(rgb(0xF4F5FA))
    ctx.addPath(page)
    ctx.fillPath()

    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
    corner.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold - 8))
    corner.addQuadCurve(to: CGPoint(x: r.maxX - fold + 8, y: r.minY + fold),
                        control: CGPoint(x: r.maxX - fold, y: r.minY + fold))
    corner.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
    corner.closeSubpath()
    ctx.setFillColor(rgb(0xC9CCDA))
    ctx.addPath(corner)
    ctx.fillPath()

    ctx.setFillColor(rgb(0x9EA3B8))
    for (i, w) in [0.62, 0.74, 0.74, 0.5].enumerated() {
        let line = CGRect(x: r.minX + 18, y: r.minY + 66 + CGFloat(i) * 20,
                          width: (r.width - 36) * CGFloat(w), height: 9)
        ctx.addPath(rounded(line, 4.5))
        ctx.fillPath()
    }
}

// 2. картинка: закат над холмами
do {
    let r = tiles[1].insetBy(dx: 6, dy: 14)
    ctx.saveGState()
    ctx.addPath(rounded(r, 22))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFB45C), rgb(0xFF6B6B), rgb(0x8E5BE8)], [0, 0.5, 1]),
                           start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
    ctx.setFillColor(rgb(0xFFF1C9))
    ctx.fillEllipse(in: CGRect(x: r.minX + 30, y: r.minY + 22, width: 40, height: 40))
    let hills = CGMutablePath()
    hills.move(to: CGPoint(x: r.minX, y: r.maxY))
    hills.addLine(to: CGPoint(x: r.minX, y: r.maxY - 40))
    hills.addQuadCurve(to: CGPoint(x: r.midX + 6, y: r.maxY - 44), control: CGPoint(x: r.minX + 50, y: r.maxY - 100))
    hills.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - 64), control: CGPoint(x: r.maxX - 34, y: r.maxY - 114))
    hills.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    hills.closeSubpath()
    ctx.setFillColor(rgb(0x2A1B5C))
    ctx.addPath(hills)
    ctx.fillPath()
    ctx.restoreGState()
}

// 3. папка
do {
    let r = tiles[2].insetBy(dx: 4, dy: 22)
    let tab = CGRect(x: r.minX, y: r.minY, width: r.width * 0.46, height: 40)
    ctx.setFillColor(rgb(0x3A8DFF))
    ctx.addPath(rounded(tab, 14))
    ctx.fillPath()
    let back = CGRect(x: r.minX, y: r.minY + 18, width: r.width, height: r.height - 18)
    ctx.addPath(rounded(back, 18))
    ctx.fillPath()
    let front = CGRect(x: r.minX, y: r.minY + 40, width: r.width, height: r.height - 40)
    ctx.saveGState()
    ctx.addPath(rounded(front, 18))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x7CC0FF), rgb(0x4C9BFF)], [0, 1]),
                           start: CGPoint(x: r.midX, y: front.minY), end: CGPoint(x: r.midX, y: front.maxY), options: [])
    ctx.restoreGState()
}

// зелёная точка «доставлено» — на картинке, как в приложении
do {
    let c = CGPoint(x: tiles[1].maxX - 4, y: tiles[1].minY + 14)
    ctx.setFillColor(rgb(0x0B0C14))
    ctx.fillEllipse(in: CGRect(x: c.x - 25, y: c.y - 25, width: 50, height: 50))
    ctx.setFillColor(rgb(0x34D399))
    ctx.fillEllipse(in: CGRect(x: c.x - 17, y: c.y - 17, width: 34, height: 34))
}

ctx.restoreGState()

guard let img = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: args[1]))
print("OK: \(args[1])")
