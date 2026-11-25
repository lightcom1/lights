import Foundation

/// Inputs an effect may read (colors and sizes the user picks).
struct EffectParams {
    var base = RGB(255, 60, 0)       // "Base color" for Breathe / Heartbeat
    var fg = RGB(0, 229, 255)        // Runner color
    var bg = RGB(26, 0, 64)          // Background color
    var groupSize = 10
    var waves = 2
}

/// Whole-strip custom modes: f(t) -> one color for the entire strip.
struct StripMode: Identifiable {
    let id: String
    let name: String
    let desc: String
    let fn: (Double, EffectParams) -> RGB
}

let stripModes: [StripMode] = [
    StripMode(id: "rainbow", name: "Rainbow", desc: "smooth hue cycle") { t, _ in .hsv(t * 40, 1, 1) },
    StripMode(id: "breathe", name: "Breathe", desc: "slow inhale/exhale") { t, p in
        p.base.scaled(0.05 + 0.95 * pow((sin(t * 1.6) + 1) / 2, 2.2))
    },
    StripMode(id: "fire", name: "Fireplace", desc: "flickering embers") { t, _ in
        let n = Noise.at(t * 6) * 0.6 + Noise.at(t * 17 + 50) * 0.4
        return .hsv(8 + n * 22, 1, 0.35 + n * 0.65)
    },
    StripMode(id: "candle", name: "Candle", desc: "warm & cozy") { t, _ in
        let n = Noise.at(t * 3) * 0.7 + Noise.at(t * 11 + 9) * 0.3
        return RGB(255, 120, 25).scaled(0.45 + n * 0.55)
    },
    StripMode(id: "aurora", name: "Aurora", desc: "northern lights") { t, _ in
        .hsv(120 + 160 * Noise.at(t * 0.35), 0.85, 0.4 + 0.6 * Noise.at(t * 0.8 + 100))
    },
    StripMode(id: "ocean", name: "Ocean", desc: "rolling waves") { t, _ in
        let w = (sin(t * 0.9) + sin(t * 1.7 + 1) * 0.5 + 1.5) / 3
        return .hsv(185 + 35 * w, 0.9, 0.35 + 0.65 * w)
    },
    StripMode(id: "lava", name: "Lava lamp", desc: "red ↔ purple blobs") { t, _ in
        .hsv(330 + 50 * Noise.at(t * 0.5), 1, 0.5 + 0.5 * Noise.at(t * 0.7 + 30))
    },
    StripMode(id: "storm", name: "Thunderstorm", desc: "distant lightning") { t, _ in
        let k = floor(t / 4), dt = t - (k * 4 + hash01(k) * 3)
        var f = 0.0
        if dt >= 0 {
            f = exp(-dt * 12)
            if hash01(k + 99) < 0.5 && dt > 0.18 { f += exp(-(dt - 0.18) * 14) }
        }
        return RGB(5, 10, 40).mixed(with: RGB(230, 235, 255), clamp(f, 0, 1))
    },
    StripMode(id: "heartbeat", name: "Heartbeat", desc: "lub-dub pulse") { t, p in
        let ph = (t * 0.9).truncatingRemainder(dividingBy: 1)
        let k = exp(-pow((ph - 0.1) / 0.04, 2)) + 0.7 * exp(-pow((ph - 0.3) / 0.05, 2))
        return p.base.scaled(0.04 + 0.96 * k)
    },
    StripMode(id: "twilight", name: "Twilight", desc: "blue hour drift") { t, _ in
        .hsv(235 + 45 * swell(t, 14), 0.9, 0.45 + 0.35 * swell(t + 3, 9))
    },
    StripMode(id: "cotton", name: "Cotton candy", desc: "pink ↔ baby blue") { t, _ in
        cycle([RGB(255, 110, 190), RGB(140, 170, 255), RGB(200, 120, 255)], t, 4)
    },
    StripMode(id: "forest", name: "Forest", desc: "sunlight through leaves") { t, _ in
        .hsv(85 + 60 * Noise.at(t * 0.4), 0.85, 0.45 + 0.5 * Noise.at(t * 0.6 + 40))
    },
    StripMode(id: "sakura", name: "Sakura", desc: "cherry blossom pinks") { t, _ in
        cycle([RGB(255, 150, 190), RGB(255, 200, 215), RGB(235, 90, 150), RGB(255, 175, 200)], t, 3.5)
    },
    StripMode(id: "neon", name: "Neon dream", desc: "cyan ↔ magenta") { t, _ in .hsv(180 + 125 * swell(t, 8), 1, 1) },
    StripMode(id: "tropical", name: "Tropical", desc: "lagoon → coral → mango") { t, _ in
        cycle([RGB(0, 210, 190), RGB(255, 110, 90), RGB(255, 190, 40), RGB(0, 160, 255)], t, 3.5)
    },
    StripMode(id: "galaxy", name: "Galaxy", desc: "deep space nebula") { t, _ in
        .hsv(250 + 70 * Noise.at(t * 0.3), 0.9, 0.25 + 0.55 * Noise.at(t * 0.45 + 70))
    },
    StripMode(id: "peach", name: "Peach", desc: "soft sorbet glow") { t, _ in
        cycle([RGB(255, 130, 80), RGB(255, 170, 120), RGB(255, 105, 95)], t, 4)
    },
    StripMode(id: "mint", name: "Mint breeze", desc: "fresh green ↔ sky") { t, _ in
        cycle([RGB(60, 255, 170), RGB(40, 200, 255), RGB(120, 255, 220)], t, 4)
    },
    StripMode(id: "fireflies", name: "Fireflies", desc: "warm glows at dusk") { t, _ in
        let g = max(swell(t, 5.3), swell(t + 2.1, 7.7) * 0.8, swell(t + 4, 11) * 0.6)
        return RGB(0, 20, 12).mixed(with: RGB(200, 255, 60), pow(g, 3))
    },
    StripMode(id: "pastel", name: "Pastel rainbow", desc: "gentle hue cycle") { t, _ in .hsv(t * 25, 0.45, 1) },
    StripMode(id: "huebreath", name: "Color breathe", desc: "new hue each breath") { t, _ in
        let period = 4.5
        return .hsv(floor(t / period) * 67 + t * 4, 1, 0.05 + 0.95 * pow(swell(t, period), 1.6))
    },
    StripMode(id: "autumn", name: "Autumn", desc: "amber, rust & gold") { t, _ in
        cycle([RGB(255, 120, 0), RGB(190, 40, 10), RGB(255, 190, 30), RGB(230, 80, 20)], t, 3.5)
    },
    StripMode(id: "arctic", name: "Arctic", desc: "icy whites & blues") { t, _ in
        cycle([RGB(200, 235, 255), RGB(80, 170, 255), RGB(230, 250, 255), RGB(40, 120, 255)], t, 4)
    },
    StripMode(id: "sunset", name: "Sunset", desc: "gold → pink → indigo") { t, _ in
        cycle([RGB(255, 170, 40), RGB(255, 80, 60), RGB(200, 40, 120), RGB(60, 20, 140)], t, 3)
    },
]

/// Per-LED effects: f(t, ledCount) -> one color per LED.
struct PixelEffect: Identifiable {
    let id: String
    let name: String
    let desc: String
    let fn: (Double, Int, EffectParams) -> [RGB]
}

private func centerBurst(_ t: Double, _ n: Int, _ p: EffectParams) -> [RGB] {
    let L = max(1, min(50, p.groupSize)), waves = max(1, min(6, p.waves))
    let half = Double(n) / 2, cycleLen = half + Double(L)
    var f = [RGB](repeating: p.bg, count: n)
    for w in 0..<waves {
        var head = (t * 40 + Double(w) * cycleLen / Double(waves)).truncatingRemainder(dividingBy: cycleLen)
        if head < 0 { head += cycleLen }
        for k in 0..<L {
            let d = Int(floor(head - Double(k)))
            if d < 0 || Double(d) >= half { continue }
            let c = p.bg.mixed(with: p.fg, 1 - Double(k) / Double(L) * 0.7) // bright front, soft tail
            let right = Int(floor(half)) + d, left = Int(ceil(half - 1)) - d
            if right < n { f[right] = c }
            if left >= 0 { f[left] = c }
        }
    }
    return f
}

let pixelEffects: [PixelEffect] = [
    PixelEffect(id: "burst", name: "Center burst", desc: "groups fly out from the middle", fn: centerBurst),
    PixelEffect(id: "implode", name: "Center implode", desc: "groups rush into the middle") { t, n, p in
        centerBurst(1000 - t, n, p)
    },
    PixelEffect(id: "comet", name: "Comet", desc: "one runner with a long tail") { t, n, p in
        let L = Double(max(2, min(100, p.groupSize * 2)))
        let head = (t * 45).truncatingRemainder(dividingBy: Double(n) + L)
        return (0..<n).map { i in
            let d = head - Double(i)
            return d >= 0 && d < L ? p.bg.mixed(with: p.fg, pow(1 - d / L, 1.5)) : p.bg
        }
    },
    PixelEffect(id: "rainbowBurst", name: "Rainbow from center", desc: "rainbow rings flowing outward") { t, n, _ in
        (0..<n).map { i in .hsv(abs(Double(i) - Double(n) / 2) * 4 - t * 120, 1, 1) }
    },
    PixelEffect(id: "fire", name: "Fire", desc: "every LED flickers on its own") { t, n, _ in
        (0..<n).map { i in
            let v = Noise.at(t * 5 + Double(i) * 0.37) * 0.65 + Noise.at(t * 13 + Double(i) * 1.7 + 50) * 0.35
            return .hsv(4 + v * 30, 1, pow(v, 1.6))
        }
    },
    PixelEffect(id: "twinkle", name: "Twinkle", desc: "random LEDs softly glow") { t, n, p in
        (0..<n).map { i in
            let w = max(0, sin(t * (0.6 + hash01(Double(i) + 7)) + hash01(Double(i)) * 10))
            return p.bg.mixed(with: p.fg, pow(w, 8))
        }
    },
    PixelEffect(id: "rainbowRun", name: "Rainbow run", desc: "rainbow scrolling along") { t, n, _ in
        (0..<n).map { i in .hsv(Double(i) * 3 - t * 90, 1, 1) }
    },
    PixelEffect(id: "ocean", name: "Ocean waves", desc: "blue swells rolling by") { t, n, _ in
        (0..<n).map { i in
            let x = Double(i)
            let w = (sin(x * 0.09 - t * 2.2) + sin(x * 0.031 + t * 1.3) * 0.6 + 1.6) / 3.2
            return .hsv(195 + 30 * w, 0.95, 0.15 + 0.85 * pow(w, 1.5))
        }
    },
]
