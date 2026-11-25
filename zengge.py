#!/usr/bin/env python3
"""Control a ZENGGE / LEDnetWF Bluetooth LED strip from the command line.

    pip install bleak
    python zengge.py scan
    python zengge.py on
    python zengge.py color ff3c00
    python zengge.py mode fire          # rainbow | breathe | fire | police | aurora
    python zengge.py off

Uses the MAC address below by default (works on Windows and Linux).
macOS hides MAC addresses, so run `scan` there and pass --addr <uuid>.
"""
import argparse
import asyncio
import colorsys
import math
import random
import time

from bleak import BleakClient, BleakScanner

DEFAULT_ADDR = "08:65:F0:92:BF:DD"
WRITE_CHAR = "0000ff01-0000-1000-8000-00805f9b34fb"
NOTIFY_CHAR = "0000ff02-0000-1000-8000-00805f9b34fb"


class Strip:
    def __init__(self, client: BleakClient, legacy: bool = False):
        self.c, self.legacy, self.seq = client, legacy, 0

    async def send(self, payload: list[int]):
        payload = payload + [sum(payload) & 0xFF]
        self.seq = (self.seq + 1) & 0xFF
        n = len(payload)
        pkt = bytes([0x00, self.seq, 0x80, 0x00, 0x00, n, n + 1, 0x0B, *payload])
        await self.c.write_gatt_char(WRITE_CHAR, pkt, response=False)

    async def power(self, on: bool):
        if self.legacy:
            await self.send([0x71, 0x23 if on else 0x24, 0x0F])
        else:
            await self.send([0x3B, 0x23 if on else 0x24, 0, 0, 0, 0, 0, 0, 0, 0x32, 0, 0])

    async def rgb(self, r: int, g: int, b: int):
        if self.legacy:
            await self.send([0x31, r, g, b, 0, 0, 0x0F])
            return
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        await self.send([0x3B, 0xA1, round(h * 180), round(s * 100), round(v * 100), 0, 0, 0, 0, 0, 0, 0])


def hsv(h, s=1.0, v=1.0):
    return tuple(round(x * 255) for x in colorsys.hsv_to_rgb((h % 360) / 360, s, v))


MODES = {
    "rainbow": lambda t: hsv(t * 40),
    "breathe": lambda t: tuple(round(c * (0.05 + 0.95 * ((math.sin(t * 1.6) + 1) / 2) ** 2.2)) for c in (255, 60, 0)),
    "fire": lambda t: hsv(8 + random.random() * 20, 1, 0.45 + random.random() * 0.55),
    "police": lambda t: (255, 0, 0) if int(t * 4) % 2 == 0 else (0, 30, 255),
    "aurora": lambda t: hsv(120 + 80 * (math.sin(t * 0.3) + 1), 0.85, 0.5 + 0.5 * abs(math.sin(t * 0.7))),
}


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["scan", "on", "off", "color", "mode", "raw"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--addr", default=DEFAULT_ADDR)
    ap.add_argument("--legacy", action="store_true", help="use the older 0x31/0x71 command set")
    a = ap.parse_args()

    if a.cmd == "scan":
        for d in await BleakScanner.discover(timeout=8):
            print(f"{d.address}  {d.name}")
        return

    async with BleakClient(a.addr, timeout=20) as client:
        try:
            await client.start_notify(NOTIFY_CHAR, lambda _, data: print("<-", data.hex(" ")))
        except Exception:
            pass
        s = Strip(client, a.legacy)
        if a.cmd in ("on", "off"):
            await s.power(a.cmd == "on")
        elif a.cmd == "color":
            h = (a.arg or "ffffff").lstrip("#")
            await s.rgb(*(int(h[i:i + 2], 16) for i in (0, 2, 4)))
        elif a.cmd == "raw":
            await s.send([int(x, 16) for x in a.arg.split()])
        elif a.cmd == "mode":
            fn = MODES[a.arg or "rainbow"]
            print("Running", a.arg, "— Ctrl+C to stop")
            t0 = time.monotonic()
            while True:
                await s.rgb(*fn(time.monotonic() - t0))
                await asyncio.sleep(0.05)
        await asyncio.sleep(0.3)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
