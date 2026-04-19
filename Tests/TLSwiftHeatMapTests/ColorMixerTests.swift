import XCTest
@testable import TLSwiftHeatMap

final class ColorMixerTests: XCTestCase {

    // MARK: - Distinct mode

    func test_distinct_zeroDensity_returnsTransparent() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 2, mode: .distinct)
        let rgb = mixer.color(forDensity: 0)
        XCTAssertEqual(rgb.alpha, 0, "Zero density should be fully transparent")
    }

    func test_distinct_fullDensity_returnsOpaque() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 2, mode: .distinct)
        let rgb = mixer.color(forDensity: 1.0)
        XCTAssertEqual(rgb.alpha, 255, "Full density should be fully opaque in distinct mode")
    }

    func test_distinct_midDensity_returnsOpaque() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 2, mode: .distinct)
        let rgb = mixer.color(forDensity: 0.5)
        XCTAssertEqual(rgb.alpha, 255)
    }

    // MARK: - Blurry mode

    func test_blurry_zeroDensity_returnsTransparent() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 2, mode: .blurry)
        let rgb = mixer.color(forDensity: 0)
        XCTAssertEqual(rgb.alpha, 0, "Zero density should be fully transparent in blurry mode")
    }

    /// Regression: original code fatalError'd at density == 1.0 in blurry mode.
    func test_blurry_fullDensity_doesNotCrash() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 2, mode: .blurry)
        // Should not crash
        let rgb = mixer.color(forDensity: 1.0)
        XCTAssertGreaterThan(rgb.alpha, 0, "Full density blurry should have some alpha")
    }

    func test_blurry_midDensity_alphaEncodesDensity() {
        let mixer = ColorMixer(colors: [.blue, .green, .red], divideLevel: 4, mode: .blurry)
        let rgb = mixer.color(forDensity: 0.5)
        // Alpha should be ~127 (0.5 * 255)
        XCTAssertEqual(Int(rgb.alpha), 127, accuracy: 2)
    }

    // MARK: - Edge cases

    func test_singleColor_doesNotCrash() {
        // Should fall back gracefully, not crash
        let mixer = ColorMixer(colors: [.red], divideLevel: 2, mode: .distinct)
        let rgb = mixer.color(forDensity: 0.5)
        // Just verify no crash and returns something
        _ = rgb
    }

    func test_differentDensities_mapToDifferentColors() {
        // divideLevel:2 with [.blue, .red] produces 3 colours: blue, purple, red.
        // binWidth = 1/(3-1) = 0.5, so density 0.1 → bin 0 (blue, red=0)
        // and density 0.9 → bin 1 (purple, red≈127). They must differ.
        let mixer = ColorMixer(colors: [.blue, .red], divideLevel: 2, mode: .distinct)
        let low  = mixer.color(forDensity: 0.1)
        let high = mixer.color(forDensity: 0.9)
        XCTAssertNotEqual(low.red, high.red, "Low and high density should produce different red components")
    }
}
