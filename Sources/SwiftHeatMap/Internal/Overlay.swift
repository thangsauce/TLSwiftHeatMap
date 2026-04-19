import MapKit

// MARK: - Base overlay

class HeatOverlay: NSObject, MKOverlay {
    var heatPoints: [HeatMapPoint] = []

    var coordinate: CLLocationCoordinate2D {
        let rect = boundingMapRect
        return MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }

    var boundingMapRect: MKMapRect {
        computeBoundingRect()
    }

    init(first point: HeatMapPoint) {
        super.init()
        heatPoints.append(point)
    }

    func insert(_ point: HeatMapPoint) {
        heatPoints.append(point)
    }

    func computeBoundingRect() -> MKMapRect {
        fatalError("Subclass must implement computeBoundingRect()")
    }
}

// MARK: - Radius overlay

final class RadiusHeatOverlay: HeatOverlay {
    override func computeBoundingRect() -> MKMapRect {
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

// MARK: - Flat overlay

final class FlatHeatOverlay: HeatOverlay {
    override func computeBoundingRect() -> MKMapRect {
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
