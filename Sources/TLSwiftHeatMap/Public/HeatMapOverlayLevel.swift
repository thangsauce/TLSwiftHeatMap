import MapKit

/// Display level used when adding the heat map overlay to `MKMapView`.
public enum HeatMapOverlayLevel: Sendable {
    /// Renders above roads and map tiles, but below labels and annotations.
    case aboveRoads
    /// Renders above labels and annotations.
    case aboveLabels

    var mapKitValue: MKOverlayLevel {
        switch self {
        case .aboveRoads:
            return .aboveRoads
        case .aboveLabels:
            return .aboveLabels
        }
    }
}
