# LED control: Mac app

A native macOS version of the browser app. It talks to the strip over Bluetooth using CoreBluetooth.
It sends each write at the link's real maximum size, as fast as the Bluetooth stack allows, so pixel effects stream much faster than in the browser.
It also keeps running when the window is hidden.

## Build (one time)

You need macOS 13 or newer and Apple's command-line tools. Xcode itself isn't required.

```bash
xcode-select --install        # skip if you already have Xcode or the tools
cd lights/mac
./build.sh
open "build/LED Control.app"
```

Drag `build/LED Control.app` into **Applications** to keep it.
The first time it starts, macOS asks for **Bluetooth** permission. Click **Allow**.

## Use

1. **Close the ZENGGE app.** The strip accepts only one connection at a time.
2. Click **Connect…** and pick your strip, marked **LED strip** in the list. Next time, the app reconnects automatically.
3. Pick what to play:
   - **Custom modes:** the whole strip changes color together.
   - **Running lights / My effects / 1–99 browser:** the controller's own effects.
   - **Patterns:** your own per-LED design (runners, comets, chases, rainbows). It's sent once and the strip scrolls it itself, so it's perfectly smooth and keeps going with the app closed.
   - **Pixel effects:** drawn frame by frame and streamed. Use these for things the strip can't scroll itself, like the mirrored center burst or fire. Each frame is about 650 bytes over Bluetooth, so they top out around 15–20 fps. A steady **Frame rate** (default 15) looks smoother than a higher but uneven one.

## Troubleshooting

- **The strip doesn't show up:** tick **Show all devices** in the picker.
- **"Bluetooth permission denied":** go to System Settings → Privacy & Security → Bluetooth, and turn on LED Control.
- **To pick a different strip:** open **Log** and click **Forget saved strip**.
- **If something misbehaves:** open **Log**. It shows every packet sent (`→`) and received (`←`).
