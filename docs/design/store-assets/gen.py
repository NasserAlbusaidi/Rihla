#!/usr/bin/env python3
"""Regenerate the Google Play feature graphic + captioned phone screenshots (EN + AR).

On-brand marketing canvases rendered from the raw in-app screenshots in
raw-screens/ via headless Chrome. Outputs straight into the fastlane metadata
dir. Brand: Falaj (docs/DESIGN.md) — plaster #F6F7F5 + ink #1B1F1E + brass
#8A5D0D; Bricolage Grotesque 800 upright (EN display — Falaj bans italics);
Zain for subs and ALL Arabic text (bundled, Arabic-native — do NOT use the
Reem Kufi asset for sentences, it is a wordmark-only subset #636).

Usage:  python3 docs/design/store-assets/gen.py
Then review the outputs and `fastlane android listing` to publish.

raw-screens/{en,ar}/ hold the *source* in-app captures per locale (dark-theme,
current design); the PNGs under each locale's phoneScreenshots/ are the
*composited output*. To re-caption: edit SCREENS and re-run. To swap/add a
shot, drop a current PNG in raw-screens/<locale>/ and point its SCREENS row
at it.
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

# Falaj tokens — mirror lib/core/theme/tokens/color_tokens.dart (light + dark).
PLASTER, INK, BRASS, MUTED = "#F6F7F5", "#1B1F1E", "#8A5D0D", "#5C6462"
KOHL = "#111514"  # dark scaffold — device frame around dark-theme captures

FONT_FACE = f"""
@font-face {{ font-family:'Bricolage'; src:url('file://{FONTS}/BricolageGrotesque-800.ttf'); font-weight:800; }}
@font-face {{ font-family:'Zain'; src:url('file://{FONTS}/Zain-400.ttf'); font-weight:400; }}
@font-face {{ font-family:'Zain'; src:url('file://{FONTS}/Zain-700.ttf'); font-weight:700; }}
@font-face {{ font-family:'Zain'; src:url('file://{FONTS}/Zain-800.ttf'); font-weight:800; }}
"""


def fork_svg(width, height, color, rtl=False):
    """The falaj fork brand device (FalajForkPainter geometry): a main channel
    running 2.5u of 4u, then 3 round-cap rivulets fanning to the trailing
    edge, spread ±0.46h, stroke 0.11h. Mirrored for RTL."""
    w, h = 400.0, 100.0
    cy, sp, sw = h / 2, h * 0.46, h * 0.11
    node = w / 4.0 * 2.5
    flip = f' transform="translate({w},0) scale(-1,1)"' if rtl else ""
    return (
        f'<svg width="{width}" height="{height}" viewBox="0 0 {w:.0f} {h:.0f}" '
        f'fill="none" xmlns="http://www.w3.org/2000/svg"><g{flip} '
        f'stroke="{color}" stroke-width="{sw}" stroke-linecap="round">'
        f'<line x1="{sw / 2}" y1="{cy}" x2="{node}" y2="{cy}"/>'
        f'<line x1="{node}" y1="{cy}" x2="{w - sw / 2}" y2="{cy - sp}"/>'
        f'<line x1="{node}" y1="{cy}" x2="{w - sw / 2}" y2="{cy}"/>'
        f'<line x1="{node}" y1="{cy}" x2="{w - sw / 2}" y2="{cy + sp}"/>'
        f"</g></svg>"
    )


# Per row: raw source filename (same name under raw-screens/en/ and /ar/),
# then (headline, sub) per locale.
SCREENS = [
    ("settle_up.png",
        ("Settle up in the fewest payments", "Rihla finds the simplest transfers"),
        ("سَوِّ الديون بأقل عدد من الدفعات", "نحسب لك أبسط التحويلات")),
    ("ledger.png",
        ("Every expense, and who owes who", "one balance across every trip"),
        ("كل مصروف، ومن يدين لمن", "رصيد واحد عبر كل رحلة")),
    ("add_expense.png",
        ("Split evenly, by share, exact or %", "everyone, a few, or just you"),
        ("قسّم بالتساوي أو حصص أو مبلغ أو نسبة", "على الجميع أو البعض أو عليك وحدك")),
    ("activity.png",
        ("Follow every payment as it happens", "offline &middot; bilingual &middot; no sign-up"),
        ("تابع كل دفعة فور حدوثها", "دون اتصال · بالعربية · دون تسجيل")),
]

LOCALES = {
    "en-US": dict(suffix="en-US", dir="ltr", raw="en",
        hl_font="'Bricolage',sans-serif", hl_weight="800", hl_size="104px",
        hl_lh="1.04", hl_ls="-2px",
        sub_font="'Zain',sans-serif", sub_size="48px"),
    "ar": dict(suffix="ar", dir="rtl", raw="ar",
        hl_font="'Zain',sans-serif", hl_weight="800", hl_size="104px",
        hl_lh="1.14", hl_ls="0",
        sub_font="'Zain',sans-serif", sub_size="46px"),
}


def shot_css(L):
    return f"""<style>{FONT_FACE}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1242px;height:2208px;overflow:hidden;background:{PLASTER};-webkit-font-smoothing:antialiased}}
.wrap{{width:1242px;height:2208px;position:relative;
  background:radial-gradient(120% 80% at 50% -10%, #FFFFFF 0%, {PLASTER} 62%)}}
.cap{{padding:118px 90px 0;text-align:center}}
.fork{{margin:0 auto 40px;width:150px}}
.hl{{font-family:{L['hl_font']};font-weight:{L['hl_weight']};color:{INK};font-size:{L['hl_size']};
  line-height:{L['hl_lh']};letter-spacing:{L['hl_ls']}}}
.sub{{font-family:{L['sub_font']};font-weight:400;color:{MUTED};font-size:{L['sub_size']};line-height:1.3;
  margin-top:30px}}
.stage{{position:absolute;left:50%;transform:translateX(-50%);top:560px;width:1004px;
  background:{KOHL};padding:18px;border-radius:74px;
  box-shadow:0 50px 120px rgba(27,31,30,.26), 0 12px 30px rgba(27,31,30,.14)}}
.stage img{{display:block;width:100%;border-radius:58px}}
</style>"""


def shot_html(L, src, hl, sub):
    fork = fork_svg(150, 38, BRASS, rtl=(L["dir"] == "rtl"))
    return f"""<!doctype html><html dir="{L['dir']}"><head><meta charset="utf-8">{shot_css(L)}</head>
<body><div class="wrap"><div class="cap" dir="{L['dir']}"><div class="fork">{fork}</div>
<div class="hl">{hl}</div><div class="sub">{sub}</div></div>
<div class="stage"><img src="file://{RAW}/{L['raw']}/{src}"></div></div></body></html>"""


FEATURE = f"""<!doctype html><html><head><meta charset="utf-8">
<style>{FONT_FACE}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1024px;height:500px;overflow:hidden;
  background:radial-gradient(130% 120% at 8% 30%, #FFFFFF 0%, {PLASTER} 58%, #ECEEE8 100%);
  font-family:'Zain',sans-serif;-webkit-font-smoothing:antialiased}}
.fw{{width:1024px;height:500px;position:relative}}
.text{{position:absolute;left:90px;top:50%;transform:translateY(-50%)}}
.brand{{font-family:'Bricolage',sans-serif;font-weight:800;color:{INK};font-size:148px;
  line-height:.95;letter-spacing:-4px}}
.fork{{margin:18px 0 20px 8px}}
.tag{{color:{INK};font-size:50px;font-weight:700;letter-spacing:.2px}}
.tag2{{color:{MUTED};font-size:34px;font-weight:400;margin-top:6px}}
.motif{{position:absolute;right:-40px;top:0;width:520px;height:500px}}
.disc{{position:absolute;right:150px;top:120px;width:150px;height:150px;border-radius:50%;
  background:{BRASS};box-shadow:0 18px 50px rgba(138,93,13,.30)}}
.disc:after{{content:'';position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
  width:46px;height:46px;border-radius:50%;background:#FFFFFF}}
.disc:before{{content:'';position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
  width:20px;height:20px;border-radius:50%;background:{INK};z-index:2}}
.ring{{position:absolute;right:330px;top:300px;width:78px;height:78px;border-radius:50%;
  background:{INK};box-shadow:0 0 0 12px rgba(27,31,30,.12)}}
.path{{position:absolute;right:205px;top:200px;width:175px;height:140px;
  border-left:9px dotted {INK};transform:rotate(36deg);transform-origin:bottom left;opacity:.85}}
</style></head><body><div class="fw">
<div class="text"><div class="brand">Rihla</div>
<div class="fork">{fork_svg(190, 48, BRASS)}</div>
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


if __name__ == "__main__":
    # feature graphic (EN images dir; Play falls back to it for AR)
    render(FEATURE, f"{EN_IMG}/featureGraphic.png", 1024, 500)

    # screenshots, both locales — each locale composites its own raw captures
    for loc, L in LOCALES.items():
        out_dir = f"{META}/{loc}/images/phoneScreenshots"
        if os.path.isdir(out_dir):
            shutil.rmtree(out_dir)
        os.makedirs(out_dir)
        for i, (src, en, ar) in enumerate(SCREENS, 1):
            hl, sub = (en if loc == "en-US" else ar)
            render(shot_html(L, src, hl, sub), f"{out_dir}/{i}_{L['suffix']}.png", 1242, 2208)
    print("DONE")
