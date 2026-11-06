// Draws Resources/AppIcon.icns: a blue folder half-covered by a warm photo tile.
import AppKit

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    c.scaleBy(x: s, y: s)
    func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
    func gradient(_ path: CGPath, _ top: (CGFloat, CGFloat, CGFloat), _ bottom: (CGFloat, CGFloat, CGFloat), _ y0: CGFloat, _ y1: CGFloat) {
        let g = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1),
                                                    CGColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray, locations: [0, 1])!
        c.saveGState(); c.addPath(path); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: y1), end: CGPoint(x: 0, y: y0), options: [])
        c.restoreGState()
    }
    gradient(rr(CGRect(x: 100, y: 100, width: 824, height: 824), 185), (0.13, 0.15, 0.22), (0.06, 0.07, 0.11), 100, 924)
    gradient(rr(CGRect(x: 190, y: 560, width: 300, height: 170), 40), (0.35, 0.72, 0.92), (0.24, 0.62, 0.86), 560, 730)
    gradient(rr(CGRect(x: 190, y: 270, width: 644, height: 400), 44), (0.47, 0.81, 0.98), (0.27, 0.67, 0.89), 270, 670)
    let photo = rr(CGRect(x: 420, y: 230, width: 360, height: 300), 36)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4))
    c.setFillColor(.white); c.addPath(rr(CGRect(x: 404, y: 214, width: 392, height: 332), 48)); c.fillPath()
    c.restoreGState()
    gradient(photo, (1.0, 0.72, 0.36), (0.93, 0.33, 0.40), 230, 530)
    c.saveGState(); c.addPath(photo); c.clip()
    c.setFillColor(CGColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 1)); c.fillEllipse(in: CGRect(x: 640, y: 410, width: 80, height: 80))
    c.setFillColor(CGColor(srgbRed: 0.45, green: 0.14, blue: 0.32, alpha: 1))
    c.move(to: CGPoint(x: 400, y: 230)); c.addLine(to: CGPoint(x: 540, y: 400)); c.addLine(to: CGPoint(x: 640, y: 300))
    c.addLine(to: CGPoint(x: 700, y: 350)); c.addLine(to: CGPoint(x: 800, y: 230)); c.closePath(); c.fillPath()
    c.restoreGState()
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
