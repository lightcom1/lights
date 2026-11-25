import Foundation

/// ZENGGE / LEDnetWF Bluetooth LE protocol (controller model A3, addressable WS2812B).
///
/// Every command is wrapped as
///     00 SEQ 80 00  LEN_HI LEN_LO  LEN+1  0B  <payload incl. checksum>
/// and long commands are split into fragments:
///     first:     40 SEQ [80 if last] 00   TOTAL_HI TOTAL_LO  BYTES  0B  data…
///     follow-up: 40 SEQ [80 if last] IDX  BYTES  data…
enum StripProtocol {
    static func withChecksum(_ b: [UInt8]) -> [UInt8] {
        b + [b.reduce(0, &+)]
    }

    static func power(_ on: Bool) -> [UInt8] {
        withChecksum([0x3b, on ? 0x23 : 0x24, 0, 0, 0, 0, 0, 0, 0, 0x32, 0, 0])
    }

    /// Whole-strip color (sent as HSV: hue/2, sat %, value %).
    static func color(_ c: RGB, brightness: Double) -> [UInt8] {
        let (h, s, v) = c.scaled(brightness).hsv
        return withChecksum([
            0x3b, 0xa1,
            UInt8(clamp((h / 2).rounded(), 0, 180)),
            UInt8(clamp((s * 100).rounded(), 0, 100)),
            UInt8(clamp((v * 100).rounded(), 0, 100)),
            0, 0, 0, 0, 0, 0, 0,
        ])
    }

    /// Controller's built-in strip effects, ids 1–99 (255 = cycle all).
    static func stripEffect(_ id: Int, speed: Int, brightness: Int) -> [UInt8] {
        withChecksum([0x42, UInt8(id & 0xff), UInt8(clamp(Double(speed), 1, 100)), UInt8(clamp(Double(brightness), 1, 100))])
    }

    /// Controller's foreground/background effects, ids 2–10.
    static func foregroundBackground(_ id: Int, fg: RGB, bg: RGB, speed: Int, brightness: Double) -> [UInt8] {
        withChecksum([0x41, UInt8(id)] + fg.bytes(scaledBy: brightness) + bg.bytes(scaledBy: brightness)
            + [UInt8(clamp(Double(speed), 1, 100)), 0x00, 0x00, 0xf0])
    }

    /// Per-LED frame (command 0x59, "format B").
    ///     59 LEN_HI LEN_LO  [R G B] × N  00 1E MODE SPEED 00  checksum
    /// mode 1 = static (we stream frames), 2 = controller scrolls the pattern.
    static func pixels(_ frame: [RGB], brightness: Double, mode: UInt8 = 1, speed: UInt8 = 50) -> [UInt8] {
        var rgb: [UInt8] = []
        rgb.reserveCapacity(frame.count * 3)
        for c in frame { rgb += c.bytes(scaledBy: brightness) }
        let len = rgb.count + 9
        return withChecksum([0x59, UInt8((len >> 8) & 0xff), UInt8(len & 0xff)] + rgb + [0x00, 0x1e, mode, speed, 0x00])
    }
}

/// Turns payloads into BLE writes, fragmenting to fit the link's max write length.
struct Framer {
    private(set) var seq: UInt8 = 0

    mutating func packets(for payload: [UInt8], maxWrite: Int) -> [Data] {
        seq &+= 1
        let total = payload.count
        if total + 8 <= maxWrite {
            return [Data([0x00, seq, 0x80, 0x00, UInt8((total >> 8) & 0xff), UInt8(total & 0xff), UInt8((total + 1) & 0xff), 0x0b] + payload)]
        }
        var out: [Data] = []
        var off = 0, idx: UInt8 = 0
        while off < total {
            let size = min(240, maxWrite - (idx == 0 ? 8 : 5))
            let end = min(total, off + size)
            let chunk = Array(payload[off..<end])
            let last: UInt8 = end >= total ? 0x80 : 0x00
            let head: [UInt8] = idx == 0
                ? [0x40, seq, last, 0, UInt8((total >> 8) & 0xff), UInt8(total & 0xff), UInt8((chunk.count + 1) & 0xff), 0x0b]
                : [0x40, seq, last, idx, UInt8(chunk.count & 0xff)]
            out.append(Data(head + chunk))
            off = end
            idx &+= 1
        }
        return out
    }
}
