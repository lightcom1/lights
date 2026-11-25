# LED control: ZENGGE LED strip controller

A controller for a ZENGGE / LEDnetWF addressable LED strip: controller model A3, 216 WS2812B LEDs.

## Mac app (`mac/`)

A native macOS app (SwiftUI and CoreBluetooth). It has custom modes, running lights, patterns that run on the strip itself, and pixel effects streamed LED by LED.
See [mac/README.md](mac/README.md) to build it.

**Close the ZENGGE app first.** The strip accepts only one Bluetooth connection at a time.

## Python CLI (`zengge.py`)

```
pip install bleak
python zengge.py on
python zengge.py color ff3c00
python zengge.py mode fire
```

## Protocol notes

These are reverse-engineered and confirmed on this strip.

- **Bluetooth:** service `FFFF`. Commands are written to `FF01`, and replies arrive as notifications on `FF02`.
- **Wrapper:** each command is wrapped as `00 SEQ 80 00 LEN_HI LEN_LO LEN+1 0B <payload+checksum>`.
- **Long commands:** split into fragments. The first fragment is `40 SEQ [80 if last] 00 TOT_HI TOT_LO N+1 0B data`, and each follow-up is `40 SEQ [80 if last] IDX N data`.
- **Write size:** each write must fit the link's write size (197 bytes on a Mac). Larger writes stall the controller.
- **Commands:**
  - `3B 23` / `3B 24`: power on / off.
  - `3B A1 H/2 S V …`: whole-strip color.
  - `42 ID SPEED BRIGHT`: built-in effect 1–99.
  - `41 ID FG BG SPEED 00 00 F0`: foreground/background effect 2–10.
  - `59 LEN_HI LEN_LO [RGB × N] 00 1E MODE SPEED 00`: per-LED colors. MODE 1 is static. MODE 2 makes the controller scroll the pattern itself.
