/// Rendering style for the heat map overlay.
public enum HeatMapType: Sendable {
    /// Smooth colour gradient, points grouped by overlapping radius. Best for density maps.
    case radiusBlurry
    /// Discrete colour bands, points grouped by overlapping radius.
    case radiusDistinct
    /// Fills the entire bounding area with discrete colour bands.
    case flatDistinct
}
