import AppKit
import SwiftUI

// MARK: - Helpers

extension RGB {
    var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        self.init(Double(ns.redComponent) * 255, Double(ns.greenComponent) * 255, Double(ns.blueComponent) * 255)
    }
}

private let accent = Color(red: 0.49, green: 0.36, blue: 1)

struct Card<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).kerning(0.8)
                    .foregroundStyle(.secondary)
                if !subtitle.isEmpty { Text("— " + subtitle).font(.system(size: 12)).foregroundStyle(.tertiary) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.17)))
    }
}

/// A tappable tile with title, subtitle and an optional live preview strip.
struct Tile: View {
    let title: String
    var subtitle: String = ""
    var active = false
    var preview: ((Double, Int) -> [RGB])? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                if let preview { PreviewStrip(render: preview).frame(height: 8) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? accent : Color(white: 0.2), lineWidth: active ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Animated color line showing the next few seconds of an effect.
struct PreviewStrip: View {
    let render: (Double, Int) -> [RGB]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { g, size in
                let n = max(1, Int(size.width / 2))
                let colors = render(ctx.date.timeIntervalSinceReferenceDate, n)
                let w = size.width / CGFloat(colors.count)
                for (i, c) in colors.enumerated() {
                    g.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.5, height: size.height)),
                           with: .color(c.color))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Main view

struct ContentView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var strip: StripConnection
    @State private var showDevices = false
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                modesCard
                runningCard
                patternsCard
                pixelCard
                HStack(alignment: .top, spacing: 14) {
                    colorCard
                    settingsCard
                }
                logCard
            }
            .padding(16)
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.08))
        .sheet(isPresented: $showDevices) { DevicePicker(strip: strip, isPresented: $showDevices) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(engine.activity == .none ? Color(white: 0.15) : accent)
                .frame(width: 40, height: 40)
                .shadow(color: accent.opacity(engine.activity == .none ? 0 : 0.8), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("LED control").font(.system(size: 20, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(strip.isConnected ? .green : .red).frame(width: 7, height: 7)
                    Text(strip.isConnected ? "Connected · \(strip.deviceName)" : strip.status)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if strip.isConnected {
                Button("Disconnect") { strip.disconnect() }
            } else {
                Button("Connect…") { showDevices = true; strip.startScan() }
                    .buttonStyle(.borderedProminent).tint(accent)
            }
            Button("On") { engine.power(true) }
            Button("Off") { engine.power(false) }
        }
        .controlSize(.large)
    }

    // MARK: Custom modes

    private var modesCard: some View {
        Card(title: "Custom modes", subtitle: "tap again to stop") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(stripModes) { m in
                    Tile(title: m.name, subtitle: m.desc, active: engine.activity == .mode(m.id),
                         preview: { now, n in
                             let k = Engine.speedFactor(engine.modeSpeed), p = engine.params
                             return (0..<n).map { i in m.fn(now * k + Double(i) / Double(n) * 8 * k, p) }
                         }) { engine.toggleMode(m.id) }
                }
            }
        }
    }

    // MARK: Running lights (on the strip)

    private var runningCard: some View {
        Card(title: "Running lights", subtitle: "runs on the strip itself, keeps going with the app closed") {
            HStack(spacing: 14) {
                ColorPicker("Background", selection: rgbBinding(\.bg), supportsOpacity: false)
                ColorPicker("Runner", selection: rgbBinding(\.fg), supportsOpacity: false)
                Text("Speed").foregroundStyle(.secondary)
                Slider(value: $engine.runSpeed, in: 1...100, onEditingChanged: { editing in if !editing { engine.refresh() } })
                Text("\(Int(engine.runSpeed))").monospacedDigit().frame(width: 28)
            }
            HStack(spacing: 6) {
                Text("Style").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                ForEach(2...10, id: \.self) { id in
                    Button("\(id - 1)") { engine.playStyle(id) }
                        .buttonStyle(.bordered)
                        .tint(engine.activity == .style(id) ? accent : nil)
                }
            }
            Text("MY EFFECTS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
            if engine.favorites.isEmpty {
                Text("Nothing saved yet — find one below and tap ★.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(engine.favorites) { f in
                    Tile(title: f.name, subtitle: "effect \(f.id)", active: engine.activity == .stripEffect(f.id)) {
                        engine.playStripEffect(f.id)
                    }
                    .contextMenu {
                        Button("Remove") { engine.favorites.removeAll { $0.id == f.id } }
                    }
                }
            }
            EffectBrowser(engine: engine)
        }
    }

    // MARK: Patterns (scrolled by the controller)

    private var patternsCard: some View {
        Card(title: "Patterns", subtitle: "your design, animated by the strip itself — smooth, keeps going with the app closed") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(stripPatterns) { pat in
                    Tile(title: pat.name, subtitle: pat.desc, active: engine.activity == .pattern(pat.id),
                         preview: { now, n in
                             let frame = pat.build(engine.ledCount, engine.params)
                             let shift = Int(now * (5 + engine.runSpeed * 0.6)) * (engine.reverse ? -1 : 1)
                             let c = frame.count
                             return (0..<n).map { i in frame[(((i * c / n) - shift) % c + c) % c] }
                         }) { engine.playPattern(pat.id) }
                }
            }
            HStack(spacing: 14) {
                Stepper("Group size: \(engine.params.groupSize)", value: $engine.params.groupSize, in: 1...50)
                    .onChange(of: engine.params.groupSize) { _ in engine.refresh() }
                Stepper("Groups: \(engine.params.waves)", value: $engine.params.waves, in: 1...6)
                    .onChange(of: engine.params.waves) { _ in engine.refresh() }
                Toggle("Reverse direction", isOn: $engine.reverse)
                    .onChange(of: engine.reverse) { _ in engine.refresh() }
                Spacer()
            }
            Text("Uses the Background / Runner colors and Speed from Running lights.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Pixel effects (streamed)

    private var pixelCard: some View {
        Card(title: "Pixel effects", subtitle: "drawn LED by LED and streamed over Bluetooth — for what patterns can't do (mirrored, random)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(pixelEffects) { fx in
                    Tile(title: fx.name, subtitle: fx.desc, active: engine.activity == .pixel(fx.id),
                         preview: { now, n in
                             let full = fx.fn(now * Engine.speedFactor(engine.runSpeed), engine.ledCount, engine.params)
                             return (0..<n).map { full[$0 * full.count / n] }
                         }) { engine.togglePixel(fx.id) }
                }
            }
            HStack(spacing: 14) {
                Stepper("Frame rate: \(Int(engine.streamFPS))", value: $engine.streamFPS, in: 6...30, step: 1)
                    .help("Steady rate beats a high but uneven one. Lower it if motion stutters.")
                Stepper("LEDs: \(engine.ledCount)", value: $engine.ledCount, in: 1...600)
                Spacer()
                if case .pixel = engine.activity {
                    Text("\(engine.fps) fps").monospacedDigit().foregroundStyle(.secondary)
                }
                Button("Test pattern") { engine.pixelTest() }
                    .help("Whole strip red · green · blue in thirds")
            }
            Text("Uses the colors, Speed, Group size and Groups from above.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Color

    private static let swatches: [String] = [
        "#ff0000", "#ff6a00", "#ffc400", "#00ff40", "#00e5ff", "#0040ff", "#8a2be2", "#ff00aa",
        "#ffffff", "#ffd9a0", "#ff8c5a", "#40ffb0", "#3a7bff", "#c070ff", "#ff4060", "#000000",
    ]

    private var colorCard: some View {
        Card(title: "Color") {
            HStack {
                ColorPicker("Pick", selection: Binding(
                    get: { engine.color.color },
                    set: { engine.setColor(RGB($0)) }), supportsOpacity: false)
                Spacer()
            }
            HStack {
                Text("Brightness").foregroundStyle(.secondary)
                Slider(value: $engine.brightness, in: 1...100, onEditingChanged: { editing in if !editing { engine.refresh() } })
                Text("\(Int(engine.brightness))").monospacedDigit().frame(width: 28)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(Self.swatches, id: \.self) { hex in
                    let c = RGB(hex: hex) ?? .black
                    Button { engine.setColor(c) } label: {
                        RoundedRectangle(cornerRadius: 7).fill(c.color)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(white: 0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var settingsCard: some View {
        Card(title: "Mode settings") {
            HStack {
                Text("Speed").foregroundStyle(.secondary)
                Slider(value: $engine.modeSpeed, in: 1...100)
                Text("\(Int(engine.modeSpeed))").monospacedDigit().frame(width: 28)
            }
            ColorPicker("Base color (Breathe & Heartbeat)", selection: rgbBinding(\.base), supportsOpacity: false)
        }
    }

    // MARK: Log

    private var logCard: some View {
        DisclosureGroup("Log", isExpanded: $showLog) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(strip.log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .onChange(of: strip.log.count) { n in proxy.scrollTo(n - 1) }
            }
            HStack {
                if strip.hasSavedDevice {
                    Button("Forget saved strip") { strip.forgetSaved() }
                }
                Text("max write \(strip.maxWrite) bytes").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
    }

    private func rgbBinding(_ kp: WritableKeyPath<EffectParams, RGB>) -> Binding<Color> {
        Binding(
            get: { engine.params[keyPath: kp].color },
            set: { engine.params[keyPath: kp] = RGB($0); engine.refresh() })
    }
}

// MARK: - 1–99 effect browser

struct EffectBrowser: View {
    @ObservedObject var engine: Engine
    @State private var open = false
    @State private var naming = false
    @State private var name = ""

    private var playing: Int? {
        if case .stripEffect(let id) = engine.activity { return id }
        return nil
    }

    var body: some View {
        DisclosureGroup("Browse all 99 strip effects", isExpanded: $open) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 5)], spacing: 5) {
                ForEach(1...99, id: \.self) { id in
                    Button("\(id)") { engine.playStripEffect(id) }
                        .buttonStyle(.bordered)
                        .tint(playing == id ? accent : nil)
                }
            }
            .padding(.vertical, 6)
            HStack {
                Text("Playing: \(playing.map { "Effect \($0)" } ?? "—")").foregroundStyle(.secondary)
                Button("★ Save as favorite") {
                    name = playing.map { "Effect \($0)" } ?? ""
                    naming = true
                }
                .disabled(playing == nil)
            }
        }
        .alert("Name this effect", isPresented: $naming) {
            TextField("e.g. Fire", text: $name)
            Button("Save") { if let id = playing, !name.isEmpty { engine.addFavorite(id, name: name) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Device picker

struct DevicePicker: View {
    @ObservedObject var strip: StripConnection
    @Binding var isPresented: Bool
    @State private var showAll = false

    private var list: [FoundDevice] { showAll ? strip.devices : strip.devices.filter(\.likelyStrip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose your strip").font(.headline)
                Spacer()
                if strip.isScanning { ProgressView().controlSize(.small) }
            }
            Text("Close the ZENGGE app first — the strip accepts one connection at a time.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            List(list) { d in
                Button {
                    strip.connect(d.id)
                    isPresented = false
                } label: {
                    HStack {
                        Text(d.name)
                        if d.likelyStrip {
                            Text("LED strip").font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(accent.opacity(0.3)))
                        }
                        Spacer()
                        Text("\(d.rssi) dBm").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 220)
            HStack {
                Toggle("Show all devices", isOn: $showAll)
                Spacer()
                Button("Scan again") { strip.startScan() }
                Button("Cancel") { strip.stopScan(); isPresented = false }
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
