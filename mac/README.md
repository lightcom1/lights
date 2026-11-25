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
3. Everything from the web app is here: custom modes, running lights styles, your favorites, the 1–99 effect browser, and pixel effects with an fps readout.

## Troubleshooting

- **The strip doesn't show up:** tick **Show all devices** in the picker.
- **"Bluetooth permission denied":** go to System Settings → Privacy & Security → Bluetooth, and turn on LED Control.
- **To pick a different strip:** open **Log** and click **Forget saved strip**.
- **If something misbehaves:** open **Log**. It shows every packet sent (`→`) and received (`←`).
