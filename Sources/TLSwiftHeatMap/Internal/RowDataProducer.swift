import CoreGraphics

struct PixelPoint {
    var heatLevel: Float
    var localPoint: CGPoint
    var radius: CGFloat
}

struct BitmapSize {
    var width: Int
    var height: Int
    var bytesPerRow: Int { width * 4 }
    var totalBytes: Int { width * height * 4 }
}

/// Maximum output bitmap dimension (width or height). Prevents O(w*h*points) freeze on device.
private let maxBitmapDimension: CGFloat = 512

// MARK: - Base producer

class RowDataProducer {
    let pixelPoints: [PixelPoint]
    let bitmapSize: BitmapSize
    var rowData: [UInt8]

    /// - Parameters:
    ///   - cgSize: The overlay's size in screen points (UIView coordinates).
    ///             Already in the same space as `pixelPoints.localPoint` and `radius`.
    ///   - pixelPoints: Heat point positions and radii in screen-point space.
    init(cgSize: CGSize, pixelPoints: [PixelPoint]) {
        // Cap the bitmap to maxBitmapDimension on its longest side,
        // then scale pixelPoints proportionally so positions remain correct.
        let largestDim = max(cgSize.width, cgSize.height)
        let capScale: CGFloat = largestDim > maxBitmapDimension
            ? maxBitmapDimension / largestDim
            : 1.0

        let w = max(1, Int(cgSize.width  * capScale))
        let h = max(1, Int(cgSize.height * capScale))
        bitmapSize = BitmapSize(width: w, height: h)
        rowData    = [UInt8](repeating: 0, count: w * h * 4)

        self.pixelPoints = pixelPoints.map { pp in
            PixelPoint(
                heatLevel:  pp.heatLevel,
                localPoint: CGPoint(x: pp.localPoint.x * capScale, y: pp.localPoint.y * capScale),
                radius:     pp.radius * capScale
            )
        }
    }

    /// Subclasses override to fill `rowData`.
    func produce(mixer: ColorMixer) {}
}

// MARK: - Radius producer

final class RadiusRowDataProducer: RowDataProducer {
    override func produce(mixer: ColorMixer) {
        let w = bitmapSize.width
        let h = bitmapSize.height
        var byteIndex = 0

        for y in 0..<h {
            for x in 0..<w {
                var density: Float = 0
                let px = CGFloat(x), py = CGFloat(y)

                for pp in pixelPoints {
                    let dx   = Float(px - pp.localPoint.x)
                    let dy   = Float(py - pp.localPoint.y)
                    let dist = (dx * dx + dy * dy).squareRoot()
                    let ratio = 1 - dist / Float(pp.radius)
                    if ratio > 0 { density += ratio * pp.heatLevel }
                }
                density = min(density, 1)

                let rgb = mixer.color(forDensity: density)
                rowData[byteIndex]     = rgb.red
                rowData[byteIndex + 1] = rgb.green
                rowData[byteIndex + 2] = rgb.blue
                rowData[byteIndex + 3] = rgb.alpha
                byteIndex += 4
            }
        }
    }
}

// MARK: - Flat producer

final class FlatRowDataProducer: RowDataProducer {
    override func produce(mixer: ColorMixer) {
        let w = bitmapSize.width
        let h = bitmapSize.height
        var byteIndex = 0

        for y in 0..<h {
            for x in 0..<w {
                var density: Float = 0
                let px = CGFloat(x), py = CGFloat(y)

                for pp in pixelPoints {
                    let dx   = Float(px - pp.localPoint.x)
                    let dy   = Float(py - pp.localPoint.y)
                    let dist = (dx * dx + dy * dy).squareRoot()
                    let ratio = 1 - dist / Float(pp.radius)
                    if ratio > 0 { density += ratio * pp.heatLevel }
                }
                // Flat mode fills the entire bounding area — zero density shows minimum colour.
                if density == 0 { density = 0.01 }
                density = min(density, 1)

                var rgb = mixer.color(forDensity: density)
                // Flat mode encodes density in alpha (overrides the mixer's opaque alpha)
                // so that the filled area fades at its edges.
                rgb.alpha = UInt8(min(density * 255, 255))
                rowData[byteIndex]     = rgb.red
                rowData[byteIndex + 1] = rgb.green
                rowData[byteIndex + 2] = rgb.blue
                rowData[byteIndex + 3] = rgb.alpha
                byteIndex += 4
            }
        }
    }
}
