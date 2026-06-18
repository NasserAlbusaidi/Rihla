#!/usr/bin/env python3
"""Regenerate the Google Play feature graphic + captioned phone screenshots (EN + AR).

On-brand marketing canvases rendered from the raw in-app screenshots in
raw-screens/ via headless Chrome. Outputs straight into the fastlane metadata
dir. Brand: cream #FBF7EE + ink #1F1B17 + terracotta #D17B2C; Instrument Serif
Italic (EN display) / Reem Kufi (AR display); Geist UI — matches
lib/core/theme/tokens/.

Usage:  python3 docs/design/store-assets/gen.py
Then review the outputs and `fastlane android listing` to publish.

raw-screens/ holds the *source* in-app captures; the PNGs under each locale's
phoneScreenshots/ are the *composited output*. To re-caption: edit SCREENS and
re-run. To swap/add a shot, drop a current PNG in raw-screens/ and point its
SCREENS row at it. Captures must be CURRENT-DESIGN (sage palette, no
gear/logistics) — old-theme shots have been removed.
"""
import os, subprocess, shutil

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
FONTS = f"{REPO}/assets/fonts"
RAW = f"{REPO}/docs/design/store-assets/raw-screens"
META = f"{REPO}/fastlane/metadata/android"
EN_IMG = f"{META}/en-US/images"
HTMLDIR = "/tmp/rihla-aso-html"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
os.makedirs(HTMLDIR, exist_ok=True)

CREAM, INK, TERRA, MUTED = "#FBF7EE", "#1F1B17", "#D17B2C", "#6B675D"

FONT_FACE = f"""
@font-face {{ font-family:'Serif'; src:url('file://{FONTS}/InstrumentSerif-Italic.ttf'); }}
@font-face {{ font-family:'Geist'; src:url('file://{FONTS}/Geist-Variable.ttf'); }}
@font-face {{ font-family:'Kufi';  src:url('file://{FONTS}/ReemKufi-Variable.ttf'); }}
"""

# Per row: raw source in raw-screens/, then (headline, sub) per locale. Same shot, both locales.
SCREENS = [
    ("3_en-US.png",
        ("Settle up in the fewest payments", "Rihla finds the simplest transfers"),
        ("سَوِّ الديون بأقل عدد من الدفعات", "نحسب لك أبسط التحويلات")),
    ("4_en-US.png",
        ("Every expense, and who owes who", "one balance across every trip"),
        ("كل مصروف، ومن يدين لمن", "رصيد واحد عبر كل رحلة")),
    ("5_en-US.png",
        ("Split evenly, by share, exact or %", "everyone, a few, or just you"),
        ("قسّم بالتساوي أو حصص أو مبلغ أو نسبة", "على الجميع أو البعض أو عليك وحدك")),
    ("6_en-US.png",
        ("Follow every payment as it happens", "offline &middot; bilingual &middot; no sign-up"),
        ("تابع كل دفعة فور حدوثها", "دون اتصال · بالعربية · دون تسجيل")),
]

LOCALES = {
    "en-US": dict(suffix="en-US", dir="ltr",
        hl_font="'Serif',serif", hl_style="font-style:italic", hl_size="118px", hl_lh="1.02",
        sub_font="'Geist',sans-serif", sub_size="46px"),
    "ar": dict(suffix="ar", dir="rtl",
        hl_font="'Kufi',sans-serif", hl_style="font-weight:600", hl_size="100px", hl_lh="1.18",
        sub_font="'Kufi',sans-serif", sub_size="42px"),
}

def shot_css(L):
    return f"""<style>{FONT_FACE}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1242px;height:2208px;overflow:hidden;background:{CREAM};-webkit-font-smoothing:antialiased}}
.wrap{{width:1242px;height:2208px;position:relative;
  background:radial-gradient(120% 80% at 50% -10%, #FFFDF8 0%, {CREAM} 60%)}}
.cap{{padding:128px 90px 0;text-align:center}}
.dot{{width:34px;height:34px;border-radius:50%;background:{TERRA};margin:0 auto 44px;
  box-shadow:0 0 0 12px rgba(209,123,44,.12)}}
.hl{{font-family:{L['hl_font']};{L['hl_style']};color:{INK};font-size:{L['hl_size']};
  line-height:{L['hl_lh']};letter-spacing:-.5px}}
.sub{{font-family:{L['sub_font']};color:{MUTED};font-size:{L['sub_size']};line-height:1.3;
  margin-top:34px;font-weight:500}}
.stage{{position:absolute;left:50%;transform:translateX(-50%);top:560px;width:1004px;
  background:{INK};padding:18px;border-radius:74px;
  box-shadow:0 50px 120px rgba(31,27,23,.28), 0 12px 30px rgba(31,27,23,.16)}}
.stage img{{display:block;width:100%;border-radius:58px}}
</style>"""

def shot_html(L, src, hl, sub):
    return f"""<!doctype html><html dir="{L['dir']}"><head><meta charset="utf-8">{shot_css(L)}</head>
<body><div class="wrap"><div class="cap" dir="{L['dir']}"><div class="dot"></div>
<div class="hl">{hl}</div><div class="sub">{sub}</div></div>
<div class="stage"><img src="file://{RAW}/{src}"></div></div></body></html>"""

FEATURE = f"""<!doctype html><html><head><meta charset="utf-8">
<style>{FONT_FACE}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1024px;height:500px;overflow:hidden;
  background:radial-gradient(130% 120% at 8% 30%, #FFFDF8 0%, {CREAM} 58%, #F4EEDF 100%);
  font-family:'Geist',sans-serif;-webkit-font-smoothing:antialiased}}
.fw{{width:1024px;height:500px;position:relative}}
.text{{position:absolute;left:90px;top:50%;transform:translateY(-50%)}}
.brand{{font-family:'Serif',serif;font-style:italic;color:{INK};font-size:168px;line-height:.9;letter-spacing:-2px}}
.rule{{width:120px;height:9px;background:{TERRA};border-radius:6px;margin:30px 0 26px 6px}}
.tag{{font-family:'Geist';color:{INK};font-size:48px;font-weight:600;letter-spacing:.2px}}
.tag2{{font-family:'Geist';color:{MUTED};font-size:33px;font-weight:500;margin-top:12px}}
.motif{{position:absolute;right:-40px;top:0;width:520px;height:500px}}
.disc{{position:absolute;right:150px;top:120px;width:150px;height:150px;border-radius:50%;
  background:{TERRA};box-shadow:0 18px 50px rgba(209,123,44,.35)}}
.disc:after{{content:'';position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
  width:46px;height:46px;border-radius:50%;background:{CREAM}}}
.disc:before{{content:'';position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
  width:20px;height:20px;border-radius:50%;background:{INK};z-index:2}}
.ring{{position:absolute;right:330px;top:300px;width:78px;height:78px;border-radius:50%;
  background:{INK};box-shadow:0 0 0 12px rgba(31,27,23,.14)}}
.path{{position:absolute;right:205px;top:200px;width:175px;height:140px;
  border-left:9px dotted {INK};transform:rotate(36deg);transform-origin:bottom left;opacity:.85}}
</style></head><body><div class="fw">
<div class="text"><div class="brand">Rihla</div><div class="rule"></div>
<div class="tag">Split group expenses</div>
<div class="tag2">Who owes who &middot; settle up &middot; offline</div></div>
<div class="motif"><div class="disc"></div><div class="ring"></div><div class="path"></div></div>
</div></body></html>"""

def render(htmlstr, outp, w, h):
    p = f"{HTMLDIR}/{os.path.basename(outp)}.html"
    with open(p, "w") as f:
        f.write(htmlstr)
    subprocess.run([CHROME, "--headless=new", f"--screenshot={outp}",
        f"--window-size={w},{h}", "--force-device-scale-factor=1", "--hide-scrollbars",
        "--allow-file-access-from-files", "--no-sandbox", "--disable-gpu", f"file://{p}"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("rendered", outp.replace(REPO + "/", ""))

# feature graphic (EN images dir; Play falls back to it for AR)
render(FEATURE, f"{EN_IMG}/featureGraphic.png", 1024, 500)

# screenshots, both locales
for loc, L in LOCALES.items():
    out_dir = f"{META}/{loc}/images/phoneScreenshots"
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    for i, (src, en, ar) in enumerate(SCREENS, 1):
        hl, sub = (en if loc == "en-US" else ar)
        render(shot_html(L, src, hl, sub), f"{out_dir}/{i}_{L['suffix']}.png", 1242, 2208)
print("DONE")
