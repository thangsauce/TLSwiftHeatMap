#if canImport(UIKit)
import SwiftUI
import MapKit
import UIKit

/// A transparent heatmap-only layer that can be overlaid on an existing SwiftUI `Map`.
///
/// Use this when you already have your own `Map(position:)` and want only the heatmap
/// rendered above it.
public struct HeatMapOverlayLayer: UIViewRepresentable {
    private let points: [HeatPoint]
    private let type: HeatMapType
    private let colors: [Color]
    @Binding private var camera: MapCameraPosition
    @Binding private var visibleMapRect: MKMapRect?

    public init(
        points: [HeatPoint],
        type: HeatMapType = .radiusBlurry,
        colors: [Color] = [.blue, .green, .red],
        camera: Binding<MapCameraPosition>,
        visibleMapRect: Binding<MKMapRect?> = .constant(nil)
    ) {
        self.points = points
        self.type = type
        self.colors = colors
        _camera = camera
        _visibleMapRect = visibleMapRect
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true
        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        return view
    }

    public func updateUIView(_ uiView: UIImageView, context: Context) {
        context.coordinator.update(
            imageView: uiView,
            points: points,
            type: type,
            uiColors: colors.map { UIColor($0) },
            camera: camera,
            visibleMapRect: visibleMapRect
        )
    }

    @MainActor
    public final class Coordinator {
        private let engine = HeatMapComputeEngine()
        private var renderTask: Task<Void, Never>?

        deinit {
            renderTask?.cancel()
        }

        func update(
            imageView: UIImageView,
            points: [HeatPoint],
            type: HeatMapType,
            uiColors: [UIColor],
            camera: MapCameraPosition,
            visibleMapRect: MKMapRect?
        ) {
            renderTask?.cancel()

            guard
                !points.isEmpty,
                imageView.bounds.width > 0,
                imageView.bounds.height > 0,
                let effectiveMapRect = mapRect(
                    from: visibleMapRect,
                    camera: camera,
                    points: points
                )
            else {
                imageView.image = nil
                return
            }

            let overlayRect = CGRect(origin: .zero, size: imageView.bounds.size)

            renderTask = Task {
                let image = await engine.compute(
                    points: points,
                    type: type,
                    uiColors: uiColors,
                    overlayBoundingRect: effectiveMapRect,
                    overlayCGRect: overlayRect
                )
                guard !Task.isCancelled else { return }
                imageView.image = image.map { UIImage(cgImage: $0) }
            }
        }

        private func mapRect(
            from visibleMapRect: MKMapRect?,
            camera: MapCameraPosition,
            points: [HeatPoint]
        ) -> MKMapRect? {
            if let rect = visibleMapRect, rect.size.width > 0, rect.size.height > 0 {
                return rect
            }
            if let rect = camera.rect, rect.size.width > 0, rect.size.height > 0 {
                return rect
            }
            if let region = camera.region {
                return mapRect(from: region)
            }
            return pointBoundsRect(from: points)
        }

        private func mapRect(from region: MKCoordinateRegion) -> MKMapRect {
            let latDelta = region.span.latitudeDelta / 2
            let lonDelta = region.span.longitudeDelta / 2

            let north = region.center.latitude + latDelta
            let south = region.center.latitude - latDelta
            let west = region.center.longitude - lonDelta
            let east = region.center.longitude + lonDelta

            let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
            let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))

            let x = min(topLeft.x, bottomRight.x)
            let y = min(topLeft.y, bottomRight.y)
            let width = abs(bottomRight.x - topLeft.x)
            let height = abs(bottomRight.y - topLeft.y)

            // Crossing the International Date Line can produce a very large x-span
            // with this simple corner-based conversion. In that case, use a world-width
            // rect for correctness.
            if width > MKMapSize.world.width / 2 {
                return MKMapRect(
                    x: 0,
                    y: y,
                    width: MKMapSize.world.width,
                    height: max(height, 1)
                )
            }

            return MKMapRect(x: x, y: y, width: max(width, 1), height: max(height, 1))
        }

        private func pointBoundsRect(from points: [HeatPoint]) -> MKMapRect? {
            let mapPoints = points.map { HeatMapPoint(from: $0).mapPoint }
            guard let first = mapPoints.first else { return nil }

            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y

            for point in mapPoints.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }

            let width = max(maxX - minX, 1)
            let height = max(maxY - minY, 1)
            return MKMapRect(x: minX, y: minY, width: width, height: height)
        }
    }
}
#endif
