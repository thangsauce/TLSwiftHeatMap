import MapKit
import UIKit

/// Renders a pre-computed `CGImage` onto the map tile context.
final class HeatOverlayRenderer: MKOverlayRenderer {
    /// Set before the overlay is added to the map to avoid a blank-flash on first draw.
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

    /// Converts a raw RGBA byte array into a `CGImage`.
    ///
    /// Creates a `CGContext` with its own backing store (`data: nil`), copies the pixel
    /// bytes into it via `withUnsafeBytes`, then snapshots the context.
    static func makeImage(rowData: [UInt8], size: BitmapSize) -> CGImage? {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil,
                width:            size.width,
                height:           size.height,
                bitsPerComponent: 8,
                bytesPerRow:      size.bytesPerRow,
                space:            colorSpace,
                bitmapInfo:       CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let dst = ctx.data  // non-nil guaranteed when data: nil is passed
        else { return nil }

        rowData.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            dst.copyMemory(from: base, byteCount: rowData.count)
        }

        return ctx.makeImage()
    }
}
