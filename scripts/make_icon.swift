import AppKit

// 生成 VolumeGuard 应用图标：macOS squircle + 硬盘 + 绿色对勾徽章
// 用法: swift scripts/make_icon.swift <输出目录>
// 产出: <输出目录>/VolumeGuard.iconset/*.png → 用 iconutil 转 icns

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/VolumeGuard.iconset"

func drawIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 1024, height: 1024))
    img.lockFocusFlipped(false)

    let bounds = NSRect(x: 100, y: 100, width: 824, height: 824)

    // squircle 裁剪
    let squircle = NSBezierPath(roundedRect: bounds, xRadius: 184, yRadius: 184)
    squircle.addClip()

    // 背景：上亮下暗的蓝紫渐变
    let gradient = NSGradient(colors: [
        NSColor(red: 0.13, green: 0.24, blue: 0.46, alpha: 1),
        NSColor(red: 0.27, green: 0.48, blue: 0.80, alpha: 1),
    ])!
    gradient.draw(in: bounds, angle: 90)

    // 微妙高光
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 620, width: 824, height: 304),
                 xRadius: 152, yRadius: 152).fill()

    // 硬盘外壳
    let disk = NSRect(x: 296, y: 380, width: 432, height: 292)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: disk, xRadius: 40, yRadius: 40).fill()

    // 硬盘顶部分隔线
    NSColor(white: 0.80, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: disk.minX, y: disk.maxY - 64, width: disk.width, height: 6)).fill()

    // 指示灯
    NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: disk.maxX - 66, y: disk.minY + 30, width: 28, height: 28)).fill()

    // 盘面横纹（数据线条）
    NSColor(white: 0.86, alpha: 1).setFill()
    for i in 0..<3 {
        let y = disk.maxY - 130 - CGFloat(i) * 44
        NSBezierPath(rect: NSRect(x: disk.minX + 48, y: y, width: 220 - CGFloat(i) * 40, height: 16)).fill()
    }

    // 绿色对勾徽章（右下角，压住硬盘）
    let badgeRect = NSRect(x: 540, y: 250, width: 260, height: 260)
    NSColor(red: 0.16, green: 0.72, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(ovalIn: badgeRect).fill()
    NSColor.white.withAlphaComponent(0.25).setStroke()
    let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 10, dy: 10))
    ring.lineWidth = 8
    ring.stroke()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: 608, y: 380))
    check.line(to: NSPoint(x: 656, y: 328))
    check.line(to: NSPoint(x: 738, y: 428))
    check.lineWidth = 34
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    img.unlockFocus()
    return img
}

func writePNG(_ img: NSImage, pixels: Int, name: String) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let icon = drawIcon()
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in sizes {
    try writePNG(icon, pixels: px, name: name)
}
print("iconset 生成完成: \(outDir)")
