#!/usr/bin/env python3
"""Retarget raw iOS Simulator screenshots to the exact App Store slot sizes for
`fastlane ios screenshots`.

Capture the app's hero screens on a booted iOS Simulator (native iOS chrome, no
cropping needed), then run this to fit each onto the exact canvases App Store
Connect requires:
  * 6.5" iPhone : 1284 x 2778
  * 13"  iPad   : 2048 x 2732

Padding colour is sampled from each shot's own mid-left edge, so a dark-theme
capture gets dark bars and a light-theme one gets light bars (both blend in;
on the near-identical 6.5" aspect the padding is a few px and invisible).

Workflow:
    # 1. boot a sim + run the app (any device; size is normalised here)
    # 2. navigate to each hero screen and capture, numbered for ordering:
    xcrun simctl io booted screenshot /tmp/rihla_ios_shots/raw/1_dashboard.png
    xcrun simctl io booted screenshot /tmp/rihla_ios_shots/raw/2_ledger.png
    # ... etc
    # 3. retarget + upload:
    python3 tool/gen_ios_screenshots.py
    bundle exec fastlane ios screenshots

Input  : RAW_DIR (default /tmp/rihla_ios_shots/raw), *.png sorted by name.
Output : fastlane/screenshots/en-US/ (gitignored; deliver maps each PNG to a
         device by its pixel dimensions). Requires Pillow.
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.environ.get("RIHLA_IOS_RAW", "/tmp/rihla_ios_shots/raw")
OUT_DIR = os.path.join(ROOT, "fastlane", "screenshots", "en-US")
TARGETS = {"iphone65": (1284, 2778), "ipad13": (2048, 2732)}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for f in os.listdir(OUT_DIR):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT_DIR, f))

    raws = sorted(f for f in os.listdir(RAW_DIR) if f.endswith(".png"))
    if not raws:
        raise SystemExit(f"No raw captures in {RAW_DIR} — capture with simctl first.")

    for name in raws:
        src = Image.open(os.path.join(RAW_DIR, name)).convert("RGB")
        cw, ch = src.size
        bg = src.getpixel((2, ch // 2))  # edge colour → matching pad
        base = os.path.splitext(name)[0]
        for dev, (tw, th) in TARGETS.items():
            scale = min(tw / cw, th / ch)
            nw, nh = int(cw * scale), int(ch * scale)
            resized = src.resize((nw, nh), Image.LANCZOS)
            canvas = Image.new("RGB", (tw, th), bg)
            canvas.paste(resized, ((tw - nw) // 2, (th - nh) // 2))
            canvas.save(os.path.join(OUT_DIR, f"{dev}_{base}.png"))
        print(f"{name}: pad={bg}")


if __name__ == "__main__":
    main()
