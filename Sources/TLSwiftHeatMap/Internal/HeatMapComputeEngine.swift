import MapKit
import UIKit

/// All background heat map computation runs inside this actor.
/// Receives only `Sendable` value types across the boundary;
/// returns a ready-to-draw `CGImage` back to the main actor.
actor HeatMapComputeEngine {

    /// Number of interpolation steps between each colour anchor pair.
    private let colorDivideLevel = 2

    // MARK: - Entry point

    /// Compute a heat map image for the given points and overlay screen rect.
    ///
    /// - Parameters:
    ///   - points:              Consumer-supplied heat points.
    ///   - type:                Render mode (blurry / distinct / flat).
    ///   - uiColors:            Anchor colours for the gradient, cold → hot.
    ///   - overlayBoundingRect: The overlay's bounding rect in map-point space.
    ///   - overlayCGRect:       The overlay's rect in UIView screen-point space.
    /// - Returns: A ready-to-display `CGImage`, or `nil` if points is empty.
    func compute(
        points: [HeatPoint],
        type: HeatMapType,
        uiColors: [UIColor],
        overlayBoundingRect: MKMapRect,
        overlayCGRect: CGRect
    ) -> CGImage? {
        guard !points.isEmpty else { return nil }

        let heatPoints   = points.map { HeatMapPoint(from: $0) }
        let maxIntensity = heatPoints.map(\.heatLevel).max() ?? 1

        // Convert each heat point to overlay-local screen-point coordinates.
        let pixelPoints: [PixelPoint] = heatPoints.map { hp in
            let globalPoint = mapPointToCGPoint(
                hp.mapPoint,
                overlayRect:    overlayBoundingRect,
                overlayCGRect:  overlayCGRect
            )
            let localPoint = CGPoint(
                x: globalPoint.x - overlayCGRect.origin.x,
                y: globalPoint.y - overlayCGRect.origin.y
            )
            let radiusCG = radiusInCGPoints(
                hp.radiusInMapPoints,
                overlayBoundingRect: overlayBoundingRect,
                overlayCGRect:       overlayCGRect
            )
            return PixelPoint(
                heatLevel:  Float(hp.heatLevel) / Float(maxIntensity),
                localPoint: localPoint,
                radius:     radiusCG
            )
        }

        let mixerMode: ColorMixerMode = (type == .radiusBlurry) ? .blurry : .distinct
        let mixer = ColorMixer(colors: uiColors, divideLevel: colorDivideLevel, mode: mixerMode)

        // cgSize is the overlay's size in screen points — RowDataProducer
        // caps it to 512×512 and scales pixelPoints proportionally.
        let producer: RowDataProducer = type == .flatDistinct
            ? FlatRowDataProducer(cgSize: overlayCGRect.size, pixelPoints: pixelPoints)
            : RadiusRowDataProducer(cgSize: overlayCGRect.size, pixelPoints: pixelPoints)

        producer.produce(mixer: mixer)

        return HeatOverlayRenderer.makeImage(rowData: producer.rowData, size: producer.bitmapSize)
    }

    // MARK: - Coordinate conversion helpers
    //
    // These replicate the MKOverlayRenderer coordinate transforms without needing
    // the renderer instance (which is @MainActor). All maths is done in map-point
    // and screen-point space, which are both Sendable scalars.

    private func mapPointToCGPoint(
        _ mapPoint: MKMapPoint,
        overlayRect: MKMapRect,
        overlayCGRect: CGRect
    ) -> CGPoint {
        let xRatio = (mapPoint.x - overlayRect.origin.x) / overlayRect.size.width
        let yRatio = (mapPoint.y - overlayRect.origin.y) / overlayRect.size.height
        return CGPoint(
            x: overlayCGRect.origin.x + CGFloat(xRatio) * overlayCGRect.size.width,
            y: overlayCGRect.origin.y + CGFloat(yRatio) * overlayCGRect.size.height
        )
    }

    private func radiusInCGPoints(
        _ radiusMapPoints: Double,
        overlayBoundingRect: MKMapRect,
        overlayCGRect: CGRect
    ) -> CGFloat {
        guard overlayBoundingRect.size.width > 0 else { return 0 }
        let ratio = radiusMapPoints / overlayBoundingRect.size.width
        return CGFloat(ratio) * overlayCGRect.size.width
    }
}
