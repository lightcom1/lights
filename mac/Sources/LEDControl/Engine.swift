import Foundation
import SwiftUI

/// What's currently playing.
enum Activity: Equatable {
    case none
    case color
    case mode(String)        // whole-strip custom mode (streamed)
    case pixel(String)       // per-LED effect (streamed)
    case style(Int)          // controller's foreground/background effect (runs on the strip)
    case stripEffect(Int)    // controller's built-in effect 1–99 (runs on the strip)
    case pattern(String)     // our pattern, scrolled by the controller (runs on the strip)
}

struct Favorite: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
}

/// App state + the animation clock that renders and streams effects.
/// Everything runs on the main thread (timer on the main run loop, Bluetooth on the main queue).
final class Engine: ObservableObject {
    let strip = StripConnection()

    @Published var activity: Activity = .none
    @Published var color = RGB(124, 92, 255)
    @Published var brightness = 100.0           // %
    @Published var modeSpeed = 50.0             // 1...100, 50 = normal
    @Published var runSpeed = 50.0              // speed for strip effects / pixel effects
    @Published var params = EffectParams()
    @Published var ledCount = 216
    @Published var fps = 0
    @Published var streamFPS = 15.0             // steady target frame rate for streamed pixel effects
    @Published var reverse = false              // scroll direction for on-strip patterns
    @Published var favorites: [Favorite] = [] { didSet { saveFavorites() } }

    private var timer: Timer?
    private var t = 0.0
    private var lastTick = Date()
    private var lastSentColor: [UInt8] = []
    private var lastModeSend = Date.distantPast
    private var nextFrameAt = Date.distantPast
    private var fpsCount = 0
    private var fpsStamp = Date()
    private var activityToken: NSObjectProtocol?

    init() {
        loadFavorites()
        // keep animating when the window is hidden/minimised (no App Nap throttling)
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Streaming LED effects")
        let tm = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    private var bright01: Double { brightness / 100 }
    static func speedFactor(_ s: Double) -> Double { pow(4, (s - 50) / 50) } // 0.25x … 4x

    // MARK: - Actions

    func power(_ on: Bool) {
        stop()
        strip.send(StripProtocol.power(on))
    }

    func setColor(_ c: RGB) {
        color = c
        activity = .color
        sendColor(c, force: true)
    }

    func toggleMode(_ id: String) {
        if activity == .mode(id) { stop() } else { start(.mode(id)) }
    }

    func togglePixel(_ id: String) {
        if activity == .pixel(id) { stop() } else { start(.pixel(id)) }
    }

    func playStyle(_ id: Int) {
        activity = .style(id)
        strip.send(StripProtocol.foregroundBackground(id, fg: params.fg, bg: params.bg,
                                                      speed: Int(runSpeed), brightness: bright01))
    }

    func playStripEffect(_ id: Int) {
        activity = .stripEffect(id)
        strip.send(StripProtocol.stripEffect(id, speed: Int(runSpeed), brightness: Int(brightness)))
    }

    /// Re-send the on-strip effect after speed/color/brightness changes.
    func refresh() {
        switch activity {
        case .style(let id): playStyle(id)
        case .stripEffect(let id): playStripEffect(id)
        case .pattern(let id): playPattern(id)
        case .color: sendColor(color, force: false)
        default: break
        }
    }

    func playPattern(_ id: String) {
        guard let pat = stripPatterns.first(where: { $0.id == id }) else { return }
        activity = .pattern(id)
        strip.send(StripProtocol.pixels(pat.build(ledCount, params), brightness: bright01,
                                        mode: 2, speed: UInt8(clamp(runSpeed, 1, 100)), direction: reverse ? 1 : 0))
    }

    func pixelTest() {
        stop()
        let n = ledCount
        let frame = (0..<n).map { i -> RGB in
            i < n / 3 ? RGB(255, 0, 0) : i < 2 * n / 3 ? RGB(0, 255, 0) : RGB(0, 0, 255)
        }
        strip.send(StripProtocol.pixels(frame, brightness: bright01))
    }

    func stop() {
        activity = .none
        fps = 0
    }

    func addFavorite(_ id: Int, name: String) {
        favorites.removeAll { $0.id == id }
        favorites.append(Favorite(id: id, name: name))
    }

    // MARK: - Clock

    private func start(_ a: Activity) {
        activity = a
        t = 0
        lastTick = Date()
        lastSentColor = []
        fpsCount = 0
        fpsStamp = Date()
        nextFrameAt = Date()
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        switch activity {
        case .mode(let id):
            guard let m = stripModes.first(where: { $0.id == id }) else { return }
            t += dt * Self.speedFactor(modeSpeed)
            // whole-strip modes: ~30 updates/s is plenty and keeps the controller relaxed
            if !strip.isBusy && now.timeIntervalSince(lastModeSend) >= 1.0 / 30 {
                lastModeSend = now
                sendColor(m.fn(t, params), force: false)
            }
        case .pixel(let id):
            guard let fx = pixelEffects.first(where: { $0.id == id }) else { return }
            // Steady pacing: frames go out on a fixed schedule and the animation advances by the
            // same step every frame, so motion stays even. (Sending "as fast as possible" gives
            // irregular gaps that look laggy even at a higher average fps.)
            let interval = 1 / streamFPS
            if now >= nextFrameAt && !strip.isBusy {
                nextFrameAt = max(nextFrameAt.addingTimeInterval(interval), now.addingTimeInterval(-interval))
                t += interval * Self.speedFactor(runSpeed)
                strip.stream(StripProtocol.pixels(fx.fn(t, ledCount, params), brightness: bright01))
                fpsCount += 1
            }
            if now.timeIntervalSince(fpsStamp) >= 1 {
                fps = fpsCount
                fpsCount = 0
                fpsStamp = now
            }
        default:
            break
        }
    }

    private func sendColor(_ c: RGB, force: Bool) {
        let payload = StripProtocol.color(c, brightness: bright01)
        if !force && payload == lastSentColor { return }
        lastSentColor = payload
        if case .mode = activity { strip.stream(payload) } else { strip.send(payload, logIt: false) }
    }

    // MARK: - Favorites

    private func loadFavorites() {
        if let d = UserDefaults.standard.data(forKey: "favorites"),
           let f = try? JSONDecoder().decode([Favorite].self, from: d) {
            favorites = f
        } else {
            favorites = [Favorite(id: 4, name: "Colors from middle")]
        }
    }

    private func saveFavorites() {
        if let d = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(d, forKey: "favorites")
        }
    }
}
