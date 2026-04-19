import UIKit

enum ColorMixerMode {
    case blurry
    case distinct
}

struct BytesRGB {
    var red: UInt8 = 0
    var green: UInt8 = 0
    var blue: UInt8 = 0
    var alpha: UInt8 = 255
}

/// Precomputes an interpolated colour ramp and maps a density value [0,1] to RGBA bytes.
///
/// All state is set at `init` time and is read-only thereafter, making this safe to
/// pass across actor boundaries without `@unchecked Sendable`.
final class ColorMixer: Sendable {
    private let colorArray: [UIColor]
    let mode: ColorMixerMode

    /// - Parameters:
    ///   - colors: Anchor colours from cold to hot (minimum 2).
    ///   - divideLevel: Number of interpolation steps between each anchor pair (minimum 1).
    ///   - mode: Blurry (linear interpolation) or distinct (nearest-bin).
    init(colors: [UIColor], divideLevel: Int, mode: ColorMixerMode) {
        precondition(divideLevel > 0, "divideLevel must be > 0")
        self.mode = mode

        guard colors.count >= 2 else {
            colorArray = colors
            return
        }

        var built: [UIColor] = []
        for index in 0..<(colors.count - 1) {
            guard
                let rgb1 = colors[index].rgbComponents(),
                let rgb2 = colors[index + 1].rgbComponents()
            else { continue }

            let redStep   = (rgb2.red   - rgb1.red)   / Float(divideLevel)
            let greenStep = (rgb2.green - rgb1.green) / Float(divideLevel)
            let blueStep  = (rgb2.blue  - rgb1.blue)  / Float(divideLevel)

            // Exclusive upper bound avoids duplicating the shared boundary colour
            // between adjacent segments (e.g. green would appear twice for [blue,green,red]).
            for step in 0..<divideLevel {
                let f = Float(step)
                built.append(UIColor(
                    red:   CGFloat((rgb1.red   + redStep   * f) / 255),
                    green: CGFloat((rgb1.green + greenStep * f) / 255),
                    blue:  CGFloat((rgb1.blue  + blueStep  * f) / 255),
                    alpha: 1
                ))
            }
        }
        // Append the final anchor exactly once.
        if let last = colors.last { built.append(last) }
        colorArray = built
    }

    func color(forDensity density: Float) -> BytesRGB {
        switch mode {
        case .distinct: return distinct(density: density)
        case .blurry:   return blurry(density: density)
        }
    }

    // MARK: - Private

    private func distinct(density: Float) -> BytesRGB {
        guard density > 0 else { return .transparent }

        let count = colorArray.count
        guard count >= 2 else { return .transparent }

        let binWidth = 1.0 / Float(count - 1)
        let index = min(Int(density / binWidth), count - 1)
        guard let rgb = colorArray[index].rgbComponents() else { return .transparent }

        return BytesRGB(red: UInt8(rgb.red), green: UInt8(rgb.green), blue: UInt8(rgb.blue), alpha: 255)
    }

    private func blurry(density: Float) -> BytesRGB {
        guard density > 0 else { return .transparent }

        let count = colorArray.count
        guard count >= 2 else { return .transparent }

        // Clamp to [0, 1) to avoid out-of-bounds at density == 1.0.
        let d = min(density, Float(1) - Float.ulpOfOne)
        let binWidth = Float(1) / Float(count - 1)
        let rawIndex = d / binWidth
        let lowerIndex = Int(rawIndex)
        let upperIndex = min(lowerIndex + 1, count - 1)
        let t = rawIndex - Float(lowerIndex) // blend factor [0,1)

        guard
            let lRGB = colorArray[lowerIndex].rgbComponents(),
            let rRGB = colorArray[upperIndex].rgbComponents()
        else { return .transparent }

        let r = lRGB.red   * (1 - t) + rRGB.red   * t
        let g = lRGB.green * (1 - t) + rRGB.green * t
        let b = lRGB.blue  * (1 - t) + rRGB.blue  * t

        return BytesRGB(
            red:   UInt8(min(r, 255)),
            green: UInt8(min(g, 255)),
            blue:  UInt8(min(b, 255)),
            alpha: UInt8(min(d * 255, 255))
        )
    }
}

// MARK: - Helpers

private extension BytesRGB {
    static let transparent = BytesRGB(red: 0, green: 0, blue: 0, alpha: 0)
}

private extension UIColor {
    func rgbComponents() -> (red: Float, green: Float, blue: Float)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Float(r * 255), Float(g * 255), Float(b * 255))
    }
}
