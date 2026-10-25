// Gera Resources/WineUp.icns a partir da arte quadrada (Resources/wineup_player.png):
// a arte é recortada no formato de ícone do macOS (superelipse n = 5, cantos contínuos)
// com corpo de 824 px centralizado na tela de 1024 px (80,5 %), em todos os tamanhos do iconset.
// Uso: swift scripts/make-icon.swift <arte.png> <saida.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("uso: make-icon.swift <arte.png> <saida.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Superelipse |x|^n + |y|^n = 1 dentro de `rect` (forma de ícone da Apple com n ≈ 5).
func superellipse(in rect: CGRect, exponent n: Double = 5, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func render(pixels: Int) throws -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let source = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    ctx.interpolationQuality = .high
    let scale = CGFloat(pixels) / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    ctx.addPath(superellipse(in: body))
    ctx.clip()
    ctx.draw(source, in: body)
    guard let image = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]
for (pixels, name) in sizes {
    try render(pixels: pixels).write(to: output.appendingPathComponent("icon_\(name).png"))
}
