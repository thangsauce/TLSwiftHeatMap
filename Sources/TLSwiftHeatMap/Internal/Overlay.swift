import MapKit

// MARK: - Base overlay

class HeatOverlay: NSObject, MKOverlay {
    var heatPoints: [HeatMapPoint] = []

    /// Cached bounding rect — computed once on first access, invalidated by `insert`.
    /// Safe to read from MapKit's rendering thread because overlays are never
    /// mutated after `mapView.addOverlay` is called.
    private var _cachedBoundingRect: MKMapRect?

    var coordinate: CLLocationCoordinate2D {
        let rect = boundingMapRect
        return MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }

    var boundingMapRect: MKMapRect {
        if let cached = _cachedBoundingRect { return cached }
        let rect = computeBoundingRect()
        _cachedBoundingRect = rect
        return rect
    }

    init(first point: HeatMapPoint) {
        super.init()
        heatPoints.append(point)
    }

    func insert(_ point: HeatMapPoint) {
        heatPoints.append(point)
        _cachedBoundingRect = nil // invalidate so the next read recomputes
    }

    /// Computes the smallest `MKMapRect` enclosing all heat points.
    func computeBoundingRect() -> MKMapRect {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for point in heatPoints {
            let rect = point.mapRect
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        guard maxX >= minX else { return .null }

        return MKMapRect(
            origin: MKMapPoint(x: minX, y: minY),
            size: MKMapSize(width: maxX - minX, height: maxY - minY)
        )
    }
}

// MARK: - Subclasses

/// Radius-based overlay: each point's heat spreads outward by `radiusInKm`.
final class RadiusHeatOverlay: HeatOverlay {}

/// Flat overlay: fills the entire bounding area with density-based colour.
final class FlatHeatOverlay: HeatOverlay {}
