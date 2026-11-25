import Foundation

/// An RGB color with components in 0...255 (kept as Double for smooth math).
struct RGB: Equatable, Codable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let black = RGB(0, 0, 0)

    /// Bytes for the wire, scaled by `k` (0...1) and clamped.
    func bytes(scaledBy k: Double = 1) -> [UInt8] {
        [r, g, b].map { UInt8(max(0, min(255, ($0 * k).rounded()))) }
    }

    func scaled(_ k: Double) -> RGB { RGB(r * k, g * k, b * k) }

    func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    /// Hue 0...360, saturation 0...1, value 0...1.
    var hsv: (h: Double, s: Double, v: Double) {
        let rr = r / 255, gg = g / 255, bb = b / 255
        let mx = max(rr, gg, bb), mn = min(rr, gg, bb), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rr { h = ((gg - bb) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == gg { h = (bb - rr) / d + 2 }
            else { h = (rr - gg) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        var hh = h.truncatingRemainder(dividingBy: 360)
        if hh < 0 { hh += 360 }
        let c = v * s
        let x = c * (1 - abs((hh / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch hh {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGB((r + m) * 255, (g + m) * 255, (b + m) * 255)
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff))
    }
}

// MARK: - Animation helpers (same shapes as the web app)

func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }

/// Smooth 1-D value noise in 0...1.
enum Noise {
    private static let table: [Double] = {
        var g = SystemRandomNumberGenerator()
        return (0..<256).map { _ in Double.random(in: 0...1, using: &g) }
    }()

    static func at(_ x: Double) -> Double {
        let i = Int(floor(x)), f = x - floor(x), u = f * f * (3 - 2 * f)
        let a = table[((i % 256) + 256) % 256], b = table[(((i + 1) % 256) + 256) % 256]
        return a + (b - a) * u
    }
}

/// Deterministic pseudo-random 0...1 for an integer.
func hash01(_ n: Double) -> Double {
    let x = sin(n * 127.1 + 311.7) * 43758.5453
    return x - floor(x)
}

func ease(_ x: Double) -> Double { (1 - cos(Double.pi * x)) / 2 }

/// 0...1 soft wave with the given period (seconds).
func swell(_ t: Double, _ period: Double) -> Double { (1 - cos(2 * Double.pi * t / period)) / 2 }

/// Loop smoothly through color stops; `secs` = seconds per stop.
func cycle(_ stops: [RGB], _ t: Double, _ secs: Double) -> RGB {
    let n = Double(stops.count)
    var x = (t / secs).truncatingRemainder(dividingBy: n)
    if x < 0 { x += n }
    let i = Int(floor(x))
    return stops[i].mixed(with: stops[(i + 1) % stops.count], ease(x - Double(i)))
}
