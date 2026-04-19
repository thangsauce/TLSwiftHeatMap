import MapKit

/// Maximum safe latitude for radius calculations — avoids infinite map-point radii near poles.
private let maxSafeLatitude: Double = 85.0

/// Internal representation of a heat point in map-space coordinates.
struct HeatMapPoint {
    var heatLevel: Int
    var coordinate: CLLocationCoordinate2D
    var radiusInKm: Double

    init(from point: HeatPoint) {
        heatLevel  = point.intensity
        coordinate = point.coordinate
        radiusInKm = point.radiusInKm
    }

    var mapPoint: MKMapPoint {
        MKMapPoint(coordinate)
    }

    var radiusInMapPoints: Double {
        // Use MKMapSizeWorld.width (the SDK-authoritative world width) rather than
        // a hardcoded pow(2, 38) constant that Apple could change.
        let earthCircumferenceM = 40_075_016.686
        // Clamp latitude to ±85° to prevent cos(90°) ≈ 0, which would make
        // radiusInMapPoints approach infinity for points near the poles.
        let clampedLat = min(abs(coordinate.latitude), maxSafeLatitude)
            * (coordinate.latitude >= 0 ? 1 : -1)
        let metersPerMapPoint = earthCircumferenceM
            * cos(clampedLat * .pi / 180)
            / MKMapSize.world.width
        let kmPerMapPoint = metersPerMapPoint / 1_000
        return radiusInKm / kmPerMapPoint
    }

    var mapRect: MKMapRect {
        let r = radiusInMapPoints
        let origin = MKMapPoint(x: mapPoint.x - r, y: mapPoint.y - r)
        let size   = MKMapSize(width: 2 * r, height: 2 * r)
        return MKMapRect(origin: origin, size: size)
    }
}
