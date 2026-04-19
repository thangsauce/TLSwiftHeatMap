import MapKit
import UIKit

/// Renders a pre-computed `CGImage` onto the map tile context.
final class HeatOverlayRenderer: MKOverlayRenderer {
    /// Set by `HeatMapComputeEngine` after bitmap computation finishes.
    var renderedImage: CGImage?

    init(overlay: HeatOverlay) {
        super.init(overlay: overlay)
        self.alpha = 0.6
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard
            let heatOverlay = overlay as? HeatOverlay,
            let image = renderedImage
        else { return }

        let drawRect = rect(for: heatOverlay.boundingMapRect)
        context.draw(image, in: drawRect)
    }

    // MARK: - Pixel data → CGImage

    /// Converts raw RGBA byte array into a `CGImage`.
    static func makeImage(rowData: [UInt8], size: BitmapSize) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size.width, height: size.height)
        )
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let bitmapContext = CGContext(
                data: nil,
                width:            size.width,
                height:           size.height,
                bitsPerComponent: 8,
                bytesPerRow:      size.bytesPerRow,
                space:            colorSpace,
                bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        rowData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            bitmapContext.data?.copyMemory(from: base, byteCount: rowData.count)
        }

        _ = renderer // silence unused warning — UIGraphicsImageRenderer used for sRGB context only
        return bitmapContext.makeImage()
    }
}
