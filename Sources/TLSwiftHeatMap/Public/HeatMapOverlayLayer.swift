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

    public init(
        points: [HeatPoint],
        type: HeatMapType = .radiusBlurry,
        colors: [Color] = [.blue, .green, .red],
        camera: Binding<MapCameraPosition>
    ) {
        self.points = points
        self.type = type
        self.colors = colors
        _camera = camera
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
            camera: camera
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
            camera: MapCameraPosition
        ) {
            renderTask?.cancel()

            guard
                !points.isEmpty,
                imageView.bounds.width > 0,
                imageView.bounds.height > 0,
                let visibleMapRect = mapRect(from: camera)
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
                    overlayBoundingRect: visibleMapRect,
                    overlayCGRect: overlayRect
                )
                guard !Task.isCancelled else { return }
                imageView.image = image.map { UIImage(cgImage: $0) }
            }
        }

        private func mapRect(from camera: MapCameraPosition) -> MKMapRect? {
            if let rect = camera.rect {
                return rect
            }
            if let region = camera.region {
                return MKMapRect(region)
            }
            return nil
        }
    }
}
#endif
