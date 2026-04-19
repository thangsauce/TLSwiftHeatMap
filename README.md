# SwiftHeatMap

A modern Swift Package for rendering heat map overlays on MapKit maps in SwiftUI. Built for **iOS 17+**, **Swift 6**, and **Swift Package Manager**.

> Ported and modernised from [JDSwiftHeatMap](https://github.com/jamesdouble/JDSwiftHeatMap) — fully rewritten with Swift 6 strict concurrency, a SwiftUI-idiomatic API, and 6 bug fixes from the original.

---

![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![iOS](https://img.shields.io/badge/iOS-17%2B-blue)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## Features

- ✅ **SwiftUI native** — drop `HeatMapView` anywhere in your view hierarchy
- ✅ **Swift 6 concurrency** — actor-isolated background computation, zero data races
- ✅ **Swift Package Manager** — no CocoaPods, no Carthage
- ✅ **iOS 17+** — built on modern MapKit APIs
- ✅ **Three render modes** — radius blurry, radius distinct, flat distinct
- ✅ **Customisable colours** — pass any gradient from cold to hot
- ✅ **Performance cap** — bitmap capped at 512×512 to prevent on-device freezes
- ✅ **Camera binding** — optional two-way `MapCameraPosition` binding

---

## Requirements

| | Minimum |
|---|---|
| iOS | 17.0 |
| Swift | 6.0 |
| Xcode | 16.0 |

---

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, go to **File → Add Package Dependencies…**
2. Enter the repository URL:
   ```
   https://github.com/your-username/SwiftHeatMap
   ```
3. Select **Up to Next Major Version** starting from `1.0.0`
4. Add `SwiftHeatMap` to your target

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/your-username/SwiftHeatMap", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["SwiftHeatMap"]
    )
]
```

---

## Quick Start

```swift
import SwiftUI
import SwiftHeatMap
import CoreLocation

struct ContentView: View {
    let points: [HeatPoint] = [
        HeatPoint(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), intensity: 90),
        HeatPoint(coordinate: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4180), intensity: 60),
        HeatPoint(coordinate: CLLocationCoordinate2D(latitude: 37.7740, longitude: -122.4200), intensity: 40, radiusInKm: 50),
    ]

    var body: some View {
        HeatMapView(points: points, type: .radiusBlurry)
            .ignoresSafeArea()
    }
}
```

---

## API Reference

### `HeatPoint`

A single data point on the heat map.

```swift
public struct HeatPoint: Sendable {
    public var coordinate: CLLocationCoordinate2D  // geographic position
    public var intensity: Int                       // heat level, 0–100
    public var radiusInKm: Double                  // radius of influence (default: 100 km)

    public init(
        coordinate: CLLocationCoordinate2D,
        intensity: Int,
        radiusInKm: Double = 100
    )
}
```

| Property | Type | Description |
|---|---|---|
| `coordinate` | `CLLocationCoordinate2D` | Geographic position of this point |
| `intensity` | `Int` | Heat contribution, 0–100. Higher = hotter colour. |
| `radiusInKm` | `Double` | How far this point's heat spreads (kilometres). Default: `100`. |

---

### `HeatMapType`

Controls how heat points are rendered.

```swift
public enum HeatMapType: Sendable {
    case radiusBlurry    // smooth gradient, best for density visualisation
    case radiusDistinct  // discrete colour bands, radius-based
    case flatDistinct    // fills the entire bounding area with discrete bands
}
```

| Mode | Description | Best for |
|---|---|---|
| `.radiusBlurry` | Smooth colour gradient around each point | Population density, signal strength |
| `.radiusDistinct` | Hard colour bands around each point | Category-based data |
| `.flatDistinct` | Colours the whole map area uniformly by density | Area-wide intensity maps |

---

### `HeatMapView`

The SwiftUI view. Drop it anywhere — it manages its own `MKMapView` internally.

```swift
public struct HeatMapView: View {
    public init(
        points: [HeatPoint],
        type: HeatMapType = .radiusBlurry,
        colors: [Color] = [.blue, .green, .red],
        camera: Binding<MapCameraPosition> = .constant(.automatic)
    )
}
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `points` | `[HeatPoint]` | — | Heat data to render |
| `type` | `HeatMapType` | `.radiusBlurry` | Render mode |
| `colors` | `[Color]` | `[.blue, .green, .red]` | Gradient anchors, cold → hot |
| `camera` | `Binding<MapCameraPosition>` | `.constant(.automatic)` | Optional camera control |

---

## Examples

### Custom colour gradient

```swift
HeatMapView(
    points: points,
    type: .radiusBlurry,
    colors: [.purple, .yellow, .orange, .red]
)
```

### Distinct bands

```swift
HeatMapView(points: points, type: .radiusDistinct)
```

### Camera binding

```swift
struct ContentView: View {
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    var body: some View {
        HeatMapView(points: points, camera: $camera)
    }
}
```

### Responding to data changes

`HeatMapView` re-renders automatically whenever `points` changes — just update your array:

```swift
struct ContentView: View {
    @State private var points: [HeatPoint] = []

    var body: some View {
        VStack {
            HeatMapView(points: points, type: .radiusBlurry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("Load data") {
                points = fetchHeatPoints()
            }
        }
    }
}
```

---

## Render Modes Visual Guide

```
radiusBlurry          radiusDistinct         flatDistinct
─────────────         ──────────────         ────────────
   🔵→🟢→🔴           🔵 | 🟢 | 🔴          ██████████
  (smooth blend)      (hard colour bands)    (fills area)
```

---

## Performance Notes

- Bitmap computation runs on a background **actor** — the UI stays responsive during calculation.
- Output bitmap is capped at **512 × 512 pixels** regardless of map zoom or screen size. This prevents the O(width × height × points) pixel loop from freezing the device on large maps.
- The heat map **re-renders on zoom change** — only if the new zoom is significantly different (more than a 66% change in map rect width).
- Memory scales with point count, not map size. Thousands of points are fine; tens of thousands may slow the computation step.

---

## Architecture

```
HeatMapView (UIViewRepresentable)
    └── Coordinator (@MainActor, MKMapViewDelegate)
            ├── HeatMapComputeEngine (actor)    ← background bitmap work
            │       ├── ColorMixer              ← gradient precomputation
            │       └── RowDataProducer         ← pixel loop
            ├── HeatOverlay (MKOverlay)         ← MapKit overlay data
            └── HeatOverlayRenderer (MKOverlayRenderer) ← draws CGImage to map
```

All data crossing the actor boundary (`[HeatPoint]`, `MKMapRect`, `CGImage`) is `Sendable`. No shared mutable state between the main actor and the compute actor.

---

## Differences from JDSwiftHeatMap

| | JDSwiftHeatMap | SwiftHeatMap |
|---|---|---|
| Integration | CocoaPods only | Swift Package Manager |
| SwiftUI | ❌ Requires UIKit wrapper | ✅ Native `View` |
| Swift 6 | ❌ Data races throughout | ✅ Full actor isolation |
| API | Delegate protocol | Array of `HeatPoint` |
| Bugs | 6 known bugs | Fixed |
| Deprecated APIs | Several | None |
| iOS minimum | 9.0 | 17.0 |

---

## License

MIT. See [LICENSE](LICENSE) for details.

Original work © 2017 JamesDouble. Modernised implementation © 2026.
