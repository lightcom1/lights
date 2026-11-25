# LED control: ZENGGE / LEDnetWF LED strip controller

Device: `08:65:F0:92:BF:DD`

## Browser app (`index.html`)

This works in Chrome or Edge on Android, Windows, macOS and Linux. On iPhone, use the Bluefy browser.
Web Bluetooth needs `https://` or `localhost`:

- **Easiest:** turn on GitHub Pages for this repo (Settings → Pages → deploy from branch), then open the page on your phone.
- **On a computer:** `python3 -m http.server 8000`, then open http://localhost:8000

**Close the ZENGGE app first.** The strip accepts only one Bluetooth connection at a time.

Features: power, color picker and swatches, brightness, 24 smooth custom modes with live previews (Rainbow, Breathe, Fireplace, Candle, Twilight, Cotton candy, Galaxy, Fireflies…
and more), the controller's built-in effects, and a raw hex console.

The browser renders the custom modes and streams them to the strip at about 20 fps, so keep the page open while a mode runs.

## Python CLI (`zengge.py`)

```
pip install bleak
python zengge.py on
python zengge.py color ff3c00
python zengge.py mode fire
```

If colors don't respond, try the **Legacy** protocol in the app (Advanced) or pass `--legacy` to the script.
