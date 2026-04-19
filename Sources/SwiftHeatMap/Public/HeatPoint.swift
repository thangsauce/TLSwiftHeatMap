import CoreLocation

/// A single data point on the heat map.
public struct HeatPoint: Sendable {
    /// Geographic coordinate of this point.
    public var coordinate: CLLocationCoordinate2D
    /// Heat intensity, 0–100. Higher values contribute more heat colour.
    public var intensity: Int
    /// Radius of influence in kilometres. Defaults to 100 km.
    public var radiusInKm: Double

    public init(
        coordinate: CLLocationCoordinate2D,
        intensity: Int,
        radiusInKm: Double = 100
    ) {
        self.coordinate = coordinate
        self.intensity = intensity
        self.radiusInKm = radiusInKm
    }
}
