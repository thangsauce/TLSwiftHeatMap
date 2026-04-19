import MapKit
import UIKit

/// All background heat map computation runs inside this actor.
/// Receives only `Sendable` value types across the boundary;
/// returns a ready-to-draw `CGImage` back to the main actor.
actor HeatMapComputeEngine {

    // MARK: - Entry point

    /// Compute a heat map image for the given points and visible region.
    /// - Parameters:
    ///   - points:      Consumer-supplied heat points.
    ///   - type:        Render mode (blurry / distinct / flat).
    ///   - colors:      Anchor colours for the gradient, cold → hot.
    ///   - mapView:     Used to convert map coordinates → screen points. Must be called on main actor.
    /// - Returns: A ready-to-display `CGImage`, or `nil` if points is empty.
    func compute(
        points: [HeatPoint],
        type: HeatMapType,
        colors: [UIColor],
        visibleMapRect: MKMapRect,
        visibleMapRectCGSize: CGSize,
        overlayBoundingRect: MKMapRect,
        overlayCGRect: CGRect
    ) -> CGImage? {
        guard !points.isEmpty else { return nil }

        let heatPoints = points.map { HeatMapPoint(from: $0) }
        let maxIntensity = heatPoints.map(\.heatLevel).max() ?? 1

        // Build pixel-space data
        let pixelPoints: [PixelPoint] = heatPoints.map { hp in
            let globalPoint = mapPointToCGPoint(
                hp.mapPoint,
                overlayRect: overlayBoundingRect,
                overlayCGRect: overlayCGRect
            )
            let localPoint = CGPoint(
                x: globalPoint.x - overlayCGRect.origin.x,
                y: globalPoint.y - overlayCGRect.origin.y
            )
            let radiusCG = radiusInCGPoints(
                hp.radiusInMapPoints,
                overlayBoundingRect: overlayBoundingRect,
                overlayCGRect: overlayCGRect
            )
            return PixelPoint(
                heatLevel: Float(hp.heatLevel) / Float(maxIntensity),
                localPoint: localPoint,
                radius: radiusCG
            )
        }

        let scale = Double(visibleMapRectCGSize.width) / visibleMapRect.size.width
        let mixerMode: ColorMixerMode = (type == .radiusBlurry) ? .blurry : .distinct
        let mixer = ColorMixer(colors: colors, divideLevel: 2, mode: mixerMode)

        let producer: RowDataProducer
        if type == .flatDistinct {
            producer = FlatRowDataProducer(
                cgSize: overlayCGRect.size,
                pixelPoints: pixelPoints,
                scale: scale
            )
        } else {
            producer = RadiusRowDataProducer(
                cgSize: overlayCGRect.size,
                pixelPoints: pixelPoints,
                scale: scale
            )
        }

        producer.produce(mixer: mixer)

        return HeatOverlayRenderer.makeImage(rowData: producer.rowData, size: producer.bitmapSize)
    }

    // MARK: - Coordinate conversion helpers
    // These replicate the MKOverlayRenderer coordinate transforms without needing
    // the renderer instance (which is @MainActor). We perform the maths manually.

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
        let ratio = radiusMapPoints / overlayBoundingRect.size.width
        return CGFloat(ratio) * overlayCGRect.size.width
    }
}
