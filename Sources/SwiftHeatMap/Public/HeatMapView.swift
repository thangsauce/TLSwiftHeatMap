import SwiftUI
import MapKit
import UIKit

/// A SwiftUI view that renders a heat map overlay on top of a `MKMapView`.
///
/// Example usage:
/// ```swift
/// HeatMapView(points: myHeatPoints, type: .radiusBlurry)
///     .frame(maxWidth: .infinity, maxHeight: .infinity)
/// ```
public struct HeatMapView: UIViewRepresentable {
    private let points: [HeatPoint]
    private let type: HeatMapType
    private let colors: [Color]
    @Binding private var camera: MapCameraPosition

    // MARK: - Init

    public init(
        points: [HeatPoint],
        type: HeatMapType = .radiusBlurry,
        colors: [Color] = [.blue, .green, .red],
        camera: Binding<MapCameraPosition> = .constant(.automatic)
    ) {
        self.points = points
        self.type   = type
        self.colors = colors
        _camera     = camera
    }

    // MARK: - UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            points: points,
            type: type,
            colors: colors.map { UIColor($0) }
        )
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?

        private let engine = HeatMapComputeEngine()
        private var currentOverlay: HeatOverlay?
        private var currentRenderer: HeatOverlayRenderer?
        private var isComputing = false
        private var pendingUpdate: (() -> Void)?

        // Track last rendered state to avoid redundant recomputes
        private var lastPoints: [HeatPoint] = []
        private var lastType: HeatMapType?
        private var lastColors: [UIColor] = []

        func update(mapView: MKMapView, points: [HeatPoint], type: HeatMapType, colors: [UIColor]) {
            guard
                !points.isEmpty,
                points.map(\.coordinate.latitude) != lastPoints.map(\.coordinate.latitude) ||
                type != lastType ||
                colors.map(\.description) != lastColors.map(\.description)
            else { return }

            lastPoints = points
            lastType   = type
            lastColors = colors

            recompute(mapView: mapView, points: points, type: type, colors: colors)
        }

        private func recompute(
            mapView: MKMapView,
            points: [HeatPoint],
            type: HeatMapType,
            colors: [UIColor]
        ) {
            if isComputing {
                pendingUpdate = { [weak self] in
                    self?.recompute(mapView: mapView, points: points, type: type, colors: colors)
                }
                return
            }
            isComputing = true

            // Build overlay to get bounding rect before going async
            let overlay = buildOverlay(from: points, type: type)

            // Remove old overlay
            if let old = currentOverlay { mapView.removeOverlay(old) }
            mapView.addOverlay(overlay, level: .aboveLabels)
            currentOverlay = overlay

            let visibleRect   = mapView.visibleMapRect
            let visibleCGSize = mapView.bounds.size
            let boundingRect  = overlay.boundingMapRect

            // Compute the CGRect for the overlay bounding rect in map view coordinates
            let overlayCGRect = mapView.convert(
                MKCoordinateRegion(boundingRect),
                toRectTo: mapView
            ).asCGRect(in: mapView)

            Task {
                let image = await engine.compute(
                    points: points,
                    type: type,
                    colors: colors,
                    visibleMapRect: visibleRect,
                    visibleMapRectCGSize: visibleCGSize,
                    overlayBoundingRect: boundingRect,
                    overlayCGRect: overlayCGRect
                )

                if let renderer = currentRenderer, let image {
                    renderer.renderedImage = image
                    renderer.setNeedsDisplay()
                }

                isComputing = false
                if let pending = pendingUpdate {
                    pendingUpdate = nil
                    pending()
                }
            }
        }

        private func buildOverlay(from points: [HeatPoint], type: HeatMapType) -> HeatOverlay {
            let heatPoints = points.map { HeatMapPoint(from: $0) }
            if type == .flatDistinct {
                let overlay = FlatHeatOverlay(first: heatPoints[0])
                heatPoints.dropFirst().forEach { overlay.insert($0) }
                return overlay
            } else {
                // Cluster into radius overlays
                var overlays: [RadiusHeatOverlay] = []
                for hp in heatPoints {
                    var inserted = false
                    for existing in overlays {
                        if existing.boundingMapRect.intersects(hp.mapRect) {
                            existing.insert(hp)
                            inserted = true
                            break
                        }
                    }
                    if !inserted {
                        overlays.append(RadiusHeatOverlay(first: hp))
                    }
                }
                // Merge intersecting overlays
                overlays = mergeOverlapping(overlays)
                // Return the largest as the single overlay (simplification)
                return overlays.max(by: {
                    $0.boundingMapRect.size.width * $0.boundingMapRect.size.height <
                    $1.boundingMapRect.size.width * $1.boundingMapRect.size.height
                }) ?? overlays[0]
            }
        }

        private func mergeOverlapping(_ overlays: [RadiusHeatOverlay]) -> [RadiusHeatOverlay] {
            var result = overlays
            var didMerge = true
            while didMerge {
                didMerge = false
                outer: for i in 0..<result.count {
                    for j in 0..<result.count where i != j {
                        if result[i].boundingMapRect.intersects(result[j].boundingMapRect) {
                            result[j].heatPoints.forEach { result[i].insert($0) }
                            result.remove(at: j)
                            didMerge = true
                            break outer
                        }
                    }
                }
            }
            return result
        }

        // MARK: - MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatOverlay = overlay as? HeatOverlay {
                let renderer = HeatOverlayRenderer(overlay: heatOverlay)
                currentRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Re-render at new zoom level if we have points
            guard !lastPoints.isEmpty, let mv = self.mapView else { return }
            recompute(mapView: mv, points: lastPoints, type: lastType ?? .radiusBlurry, colors: lastColors)
        }
    }
}

// MARK: - Helpers

private extension CGRect {
    /// Fallback: if MapKit conversion fails, use the full map view bounds.
    @MainActor
    func asCGRect(in view: UIView) -> CGRect {
        guard !isNull, !isInfinite, !isEmpty else { return view.bounds }
        return self
    }
}
