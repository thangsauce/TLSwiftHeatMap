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
        /// Renderer pre-created for the in-flight overlay, image set before `addOverlay`.
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

            recompute(points: points, type: type, uiColors: uiColors)
        }

        private func recompute(points: [HeatPoint], type: HeatMapType, uiColors: [UIColor]) {
            if isComputing {
                // Capture `self` weakly; re-read `mapView` at call time to avoid
                // holding a stale reference if SwiftUI has recycled the UIView.
                pendingUpdate = { [weak self] in
                    self?.recompute(points: points, type: type, uiColors: uiColors)
                }
                return
            }
            guard let mapView else { return }
            isComputing = true

            // Build the new overlay and pre-create its renderer.
            // The image is set on the renderer BEFORE the overlay is added to the map,
            // eliminating the blank-flash that would occur if we added first and rendered later.
            guard let overlay = buildOverlay(from: points, type: type) else {
                isComputing = false
                return
            }
            let renderer = HeatOverlayRenderer(overlay: overlay)
            pendingRenderer = renderer

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
                    overlayBoundingRect: boundingRect,
                    overlayCGRect: overlayCGRect
                )

                // Apply image before adding overlay — no blank-flash on first draw.
                if let image { renderer.renderedImage = image }

                // Re-read mapView in case SwiftUI replaced it while computing.
                guard let mv = self.mapView else {
                    isComputing = false
                    return
                }

                // Atomically swap old overlay for new one.
                if let old = currentOverlay { mv.removeOverlay(old) }
                mv.addOverlay(overlay, level: .aboveLabels)
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
        /// Returns `nil` if `points` is empty (caller must guard before calling).
        /// A single overlay (rather than multiple clustered ones) ensures no points
        /// are silently dropped for geographically separated data sets.
        private func buildOverlay(from points: [HeatPoint], type: HeatMapType) -> HeatOverlay? {
            let heatPoints = points.map { HeatMapPoint(from: $0) }
            guard let first = heatPoints.first else { return nil }

            let overlay: HeatOverlay = type == .flatDistinct
                ? FlatHeatOverlay(first: first)
                : RadiusHeatOverlay(first: first)
            heatPoints.dropFirst().forEach { overlay.insert($0) }
            return overlay
        }

        // MARK: - MKMapViewDelegate

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let heatOverlay = overlay as? HeatOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            // Return the pre-created renderer so its image is already set.
            if let pending = pendingRenderer, pending.overlay === heatOverlay {
                pendingRenderer = nil
                currentRenderer = pending
                return pending
            }
            // Fallback: map view recreated the overlay internally.
            let renderer = HeatOverlayRenderer(overlay: heatOverlay)
            currentRenderer = renderer
            return renderer
        }

        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !lastPoints.isEmpty else { return }
            recompute(
                points: lastPoints,
                type: lastType ?? .radiusBlurry,
                uiColors: lastColors.map { UIColor($0) }
            )
        }
    }
}

// MARK: - Helpers

private extension CGRect {
    /// Returns `self` if the rect is valid, otherwise returns `fallback`.
    @MainActor
    func validated(fallback: CGRect) -> CGRect {
        (isNull || isInfinite || isEmpty) ? fallback : self
    }
}
