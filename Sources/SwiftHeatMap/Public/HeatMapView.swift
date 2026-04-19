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
            colors: colors,
            uiColors: colors.map { UIColor($0) }
        )
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?

        private let engine = HeatMapComputeEngine()
        private var currentOverlay: HeatOverlay?
        private var currentRenderer: HeatOverlayRenderer?
        /// Renderer pre-created for the next overlay, image set before `addOverlay` is called.
        private var pendingRenderer: HeatOverlayRenderer?
        private var isComputing = false
        private var pendingUpdate: (() -> Void)?

        // Change-detection state
        private var lastPoints: [HeatPoint] = []
        private var lastType: HeatMapType?
        private var lastColors: [Color] = []

        func update(
            mapView: MKMapView,
            points: [HeatPoint],
            type: HeatMapType,
            colors: [Color],
            uiColors: [UIColor]
        ) {
            guard
                !points.isEmpty,
                points != lastPoints || type != lastType || colors != lastColors
            else { return }

            lastPoints = points
            lastType   = type
            lastColors = colors

            recompute(mapView: mapView, points: points, type: type, uiColors: uiColors)
        }

        private func recompute(
            mapView: MKMapView,
            points: [HeatPoint],
            type: HeatMapType,
            uiColors: [UIColor]
        ) {
            if isComputing {
                pendingUpdate = { [weak self] in
                    self?.recompute(mapView: mapView, points: points, type: type, uiColors: uiColors)
                }
                return
            }
            isComputing = true

            // Build the new overlay and pre-create its renderer.
            // The image is set on the renderer BEFORE the overlay is added to the map,
            // avoiding a blank-flash during the first draw call.
            let overlay = buildOverlay(from: points, type: type)
            let renderer = HeatOverlayRenderer(overlay: overlay)
            pendingRenderer = renderer

            let visibleRect   = mapView.visibleMapRect
            let visibleCGSize = mapView.bounds.size
            let boundingRect  = overlay.boundingMapRect
            let overlayCGRect = mapView.convert(
                MKCoordinateRegion(boundingRect),
                toRectTo: mapView
            ).validated(fallback: mapView.bounds)

            Task {
                let image = await engine.compute(
                    points: points,
                    type: type,
                    uiColors: uiColors,
                    visibleMapRect: visibleRect,
                    visibleMapRectCGSize: visibleCGSize,
                    overlayBoundingRect: boundingRect,
                    overlayCGRect: overlayCGRect
                )

                // Set image on renderer before adding the overlay to the map.
                if let image { renderer.renderedImage = image }

                // Swap old overlay out, new one in — renderer already has its image.
                if let old = currentOverlay { mapView.removeOverlay(old) }
                mapView.addOverlay(overlay, level: .aboveLabels)
                currentOverlay  = overlay
                currentRenderer = renderer

                isComputing = false
                if let pending = pendingUpdate {
                    pendingUpdate = nil
                    pending()
                }
            }
        }

        /// Builds a single overlay containing all points.
        ///
        /// A single overlay (rather than multiple clustered ones) is correct here because
        /// the 512×512 bitmap cap means there is no performance benefit to clustering,
        /// and a single overlay guarantees no points are silently dropped across
        /// geographically separated regions.
        private func buildOverlay(from points: [HeatPoint], type: HeatMapType) -> HeatOverlay {
            let heatPoints = points.map { HeatMapPoint(from: $0) }
            let overlay: HeatOverlay = type == .flatDistinct
                ? FlatHeatOverlay(first: heatPoints[0])
                : RadiusHeatOverlay(first: heatPoints[0])
            heatPoints.dropFirst().forEach { overlay.insert($0) }
            return overlay
        }

        // MARK: - MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let heatOverlay = overlay as? HeatOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            // Return the pre-created renderer if it matches, so its image is already set.
            if let pending = pendingRenderer, pending.overlay === heatOverlay {
                pendingRenderer = nil
                currentRenderer = pending
                return pending
            }
            // Fallback (e.g. map view recreates overlays internally).
            let renderer = HeatOverlayRenderer(overlay: heatOverlay)
            currentRenderer = renderer
            return renderer
        }

        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !lastPoints.isEmpty, let mv = self.mapView else { return }
            recompute(
                mapView: mv,
                points: lastPoints,
                type: lastType ?? .radiusBlurry,
                uiColors: lastColors.map { UIColor($0) }
            )
        }
    }
}

// MARK: - Helpers

private extension CGRect {
    /// Returns `self` if valid, otherwise falls back to the view's bounds.
    @MainActor
    func validated(fallback: CGRect) -> CGRect {
        (isNull || isInfinite || isEmpty) ? fallback : self
    }
}
