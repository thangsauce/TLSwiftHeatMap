import MapKit

/// Internal representation of a heat point in map-space coordinates.
struct HeatMapPoint {
    var heatLevel: Int
    var coordinate: CLLocationCoordinate2D
    var radiusInKm: Double

    init(from point: HeatPoint) {
        heatLevel = point.intensity
        coordinate = point.coordinate
        radiusInKm = point.radiusInKm
    }

    var mapPoint: MKMapPoint {
        MKMapPoint(coordinate)
    }

    var radiusInMapPoints: Double {
        // Earth circumference at equator / MKMapSizeWorld.width (2^38),
        // scaled by cos(latitude) to account for map-point compression near poles.
        let earthCircumferenceM = 40_075_016.686
        let worldWidth: Double = pow(2, 38) // MKMapSizeWorld.width
        let metersPerMapPoint = earthCircumferenceM
            * cos(coordinate.latitude * .pi / 180)
            / worldWidth
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
