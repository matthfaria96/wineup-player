import AppKit
import ImageIO

/// Capa decodificada fora da thread principal: imagem reduzida para a tela e o tamanho original em pixels.
struct DecodedCover {
    let image: NSImage
    /// Largura × altura do arquivo, lidos do cabeçalho (sem decodificar a imagem inteira).
    let pixelSize: (width: Int, height: Int)?

    var sizeText: String? { pixelSize.map { "\($0.width)×\($0.height)" } }
}

enum CoverDecode {
    /// Reduz para `maxPixels` no maior lado (2× o tamanho na tela) numa tarefa separada.
    static func decode(_ data: Data, maxPixels: Int) async -> DecodedCover? {
        await Task.detached(priority: .userInitiated) {
            guard let image = ThumbnailCache.downsample(data, to: maxPixels) else { return nil }
            return DecodedCover(image: image, pixelSize: pixelSize(of: data))
        }.value
    }

    /// Tamanho em pixels pelas propriedades do CGImageSource.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}
