#!/usr/bin/env python3
"""Semantics-aware device driver for Rihla RD-QA.
Usage:
  drive.py dump A                     # list all labeled nodes + bounds
  drive.py find A "Create"            # show matches (no tap)
  drive.py tap  A "Create"            # tap center of best match (clickable-preferred)
  drive.py tapn A "Create" 2          # tap the 2nd match (0-indexed)
  drive.py xy   A 674 291             # raw coordinate tap
  drive.py type A "hello"             # input text into focused field
  drive.py key  A BACK               # keyevent (BACK/ENTER/DEL/...)
  drive.py swipe A 500 1500 500 500 300
  drive.py airplane A on|off
"""
import subprocess, sys, re

DEV = {"A": "4C171FDAS001U0", "B": "RF8N213CZWK"}
def did(d): return DEV.get(d, d)

def sh(d, *args, text=True):
    return subprocess.run(["adb", "-s", did(d), "shell", *args],
                          capture_output=True, text=text).stdout

def dump_xml(d):
    subprocess.run(["adb", "-s", did(d), "shell", "uiautomator", "dump", "/sdcard/ui.xml"],
                   capture_output=True)
    return sh(d, "cat", "/sdcard/ui.xml")

def nodes(xml):
    out = []
    for tag in re.finditer(r'<node\b([^>]*?)/?>', xml):
        a = dict(re.findall(r'(\S+?)="([^"]*)"', tag.group(1)))
        mb = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', a.get('bounds', ''))
        if not mb:
            continue
        x1, y1, x2, y2 = map(int, mb.groups())
        label = a.get('content-desc') or a.get('text') or ''
        out.append({'label': label, 'text': a.get('text', ''),
                    'desc': a.get('content-desc', ''),
                    'cx': (x1 + x2) // 2, 'cy': (y1 + y2) // 2,
                    'bounds': (x1, y1, x2, y2),
                    'clickable': a.get('clickable') == 'true',
                    'cls': a.get('class', '').split('.')[-1]})
    return out

def match(ns, q):
    ql = q.lower()
    exact = [n for n in ns if n['label'].lower() == ql]
    subs  = [n for n in ns if ql in n['label'].lower()]
    pool = exact or subs
    pool.sort(key=lambda n: (not n['clickable'], n['cy'], n['cx']))
    return pool

def main():
    cmd, d = sys.argv[1], sys.argv[2]
    if cmd == "dump":
        for n in nodes(dump_xml(d)):
            if n['label']:
                c = "•" if n['clickable'] else " "
                print(f"{c} ({n['cx']:>4},{n['cy']:>4}) [{n['cls']:<16}] {n['label'][:70]}")
    elif cmd in ("find", "tap", "tapn"):
        q = sys.argv[3]
        idx = int(sys.argv[4]) if cmd == "tapn" else 0
        m = match(nodes(dump_xml(d)), q)
        if not m:
            print(f"NO MATCH for '{q}'"); sys.exit(1)
        if cmd == "find":
            for i, n in enumerate(m):
                print(f"[{i}] ({n['cx']},{n['cy']}) clickable={n['clickable']} {n['label'][:70]}")
            return
        n = m[idx]
        subprocess.run(["adb", "-s", did(d), "shell", "input", "tap", str(n['cx']), str(n['cy'])])
        print(f"tapped ({n['cx']},{n['cy']}) '{n['label'][:50]}'")
    elif cmd == "xy":
        subprocess.run(["adb", "-s", did(d), "shell", "input", "tap", sys.argv[3], sys.argv[4]])
        print(f"tapped ({sys.argv[3]},{sys.argv[4]})")
    elif cmd == "type":
        subprocess.run(["adb", "-s", did(d), "shell", "input", "text", sys.argv[3].replace(" ", "%s")])
        print(f"typed '{sys.argv[3]}'")
    elif cmd == "key":
        subprocess.run(["adb", "-s", did(d), "shell", "input", "keyevent", f"KEYCODE_{sys.argv[3]}"])
        print(f"key {sys.argv[3]}")
    elif cmd == "swipe":
        subprocess.run(["adb", "-s", did(d), "shell", "input", "swipe", *sys.argv[3:8]])
        print("swiped")
    elif cmd == "airplane":
        on = sys.argv[3] == "on"
        sh(d, "cmd", "connectivity", "airplane-mode", "enable" if on else "disable")
        print(f"airplane {'ON' if on else 'OFF'} on {d}")

if __name__ == "__main__":
    main()
