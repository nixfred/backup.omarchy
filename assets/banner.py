#!/usr/bin/env python3
"""Regenerate assets/banner.svg.

    pip install fonttools && python3 assets/banner.py assets/banner.svg

All text is baked to vector paths so the banner renders identically for every
viewer on GitHub regardless of installed fonts -- which also means text cannot
be edited in the SVG by hand. Change it here and regenerate.

Needs Noto Sans Black and JetBrains Mono (Nerd Font); adjust the paths below if
they live elsewhere. Deliberately uses no SVG filters: glows are layered strokes
and radial gradients, so it renders the same in librsvg and every browser.
"""
import math, random, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Transform

_cache = {}
def load(path):
    if path not in _cache:
        _cache[path] = TTFont(path)
    return _cache[path]

def text_path(fontfile, text, size, tracking=0.0):
    font = load(fontfile)
    upem = font['head'].unitsPerEm
    scale = size / upem
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    hmtx = font['hmtx']
    pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}")
    x = 0.0
    for ch in text:
        gname = cmap.get(ord(ch))
        if gname is None:
            x += size * 0.5 + tracking
            continue
        adv = hmtx[gname][0]
        gs[gname].draw(TransformPen(pen, Transform(scale, 0, 0, -scale, x, 0)))
        x += adv * scale + tracking
    return pen.getCommands(), x - (tracking if text else 0)

BLACK = "/usr/share/fonts/noto/NotoSans-Black.ttf"
MONOB = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf"
MONOR = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"

W, H = 1280, 460

# ---------------------------------------------------------------- palette
INK    = "#e9eff6"
MUTED  = "#78899c"
DIM    = "#4a5866"
GREEN  = "#3fdd8a"
AMBER  = "#ffa63d"

def T(font, text, size, tracking=0.0):
    d, w = text_path(font, text, size, tracking)
    return d, w

def put(d, x, y, fill, opacity=None):
    o = f' opacity="{opacity}"' if opacity is not None else ""
    return f'<path transform="translate({x:.2f},{y:.2f})" d="{d}" fill="{fill}"{o}/>'

out = []
A = out.append

# ---------------------------------------------------------------- defs
A(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
  f'role="img" aria-label="Backup Sizzle — restic to Backblaze B2 bar widget for Omarchy">')
A('<title>Backup Sizzle — restic to Backblaze B2 monitoring widget for the Omarchy bar</title>')
A('''<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#080d13"/><stop offset="0.55" stop-color="#0c131b"/><stop offset="1" stop-color="#0a1017"/>
  </linearGradient>
  <linearGradient id="heat" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0" stop-color="#ff3d2e"/><stop offset="0.45" stop-color="#ff6a3d"/>
    <stop offset="0.8" stop-color="#ffa63d"/><stop offset="1" stop-color="#ffd07a"/>
  </linearGradient>
  <linearGradient id="heatV" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffc76b"/><stop offset="0.5" stop-color="#ff7a3d"/><stop offset="1" stop-color="#ff3d2e"/>
  </linearGradient>
  <linearGradient id="waveFill" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ff8a3d" stop-opacity="0.55"/>
    <stop offset="0.55" stop-color="#ff5f3d" stop-opacity="0.16"/>
    <stop offset="1" stop-color="#ff3d2e" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="waveLine" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#ff5f3d"/><stop offset="0.5" stop-color="#ffa63d"/><stop offset="1" stop-color="#ffd888"/>
  </linearGradient>
  <radialGradient id="glowWarm" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#ff8a3d" stop-opacity="0.20"/>
    <stop offset="0.55" stop-color="#ff5f3d" stop-opacity="0.06"/>
    <stop offset="1" stop-color="#ff3d2e" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowCool" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#3fdd8a" stop-opacity="0.10"/><stop offset="1" stop-color="#3fdd8a" stop-opacity="0"/>
  </radialGradient>
  <pattern id="dots" width="26" height="26" patternUnits="userSpaceOnUse">
    <circle cx="1.5" cy="1.5" r="1.1" fill="#1b2836"/>
  </pattern>
  <clipPath id="card"><rect x="0" y="0" width="1280" height="460" rx="22"/></clipPath>
</defs>''')

A('<g clip-path="url(#card)">')
A(f'<rect width="{W}" height="{H}" fill="url(#bg)"/>')
A(f'<rect width="{W}" height="{H}" fill="url(#dots)" opacity="0.55"/>')
A('<ellipse cx="206" cy="214" rx="430" ry="360" fill="url(#glowWarm)"/>')
A('<ellipse cx="1010" cy="150" rx="360" ry="260" fill="url(#glowCool)"/>')

# ---------------------------------------------------------------- countdown ring
CX, CY, R = 206, 214, 112
PROG = 0.68
circ = 2 * math.pi * R
A(f'<g transform="rotate(-90 {CX} {CY})">')
A(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="none" stroke="#16202b" stroke-width="17"/>')
# layered glow (no SVG filters — maximum renderer compatibility)
for w, op in ((31, 0.06), (25, 0.10), (20, 0.18)):
    A(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="none" stroke="url(#heat)" stroke-width="{w}" '
      f'stroke-linecap="round" stroke-dasharray="{circ*PROG:.2f} {circ:.2f}" opacity="{op}"/>')
A(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="none" stroke="url(#heat)" stroke-width="15" '
  f'stroke-linecap="round" stroke-dasharray="{circ*PROG:.2f} {circ:.2f}"/>')
A('</g>')
A(f'<circle cx="{CX}" cy="{CY}" r="88" fill="none" stroke="#141e29" stroke-width="1.5"/>')
A(f'<circle cx="{CX}" cy="{CY}" r="96" fill="#0a1017" opacity="0.55"/>')
# arc head
ang = math.radians(-90 + PROG * 360)
hx, hy = CX + R * math.cos(ang), CY + R * math.sin(ang)
A(f'<circle cx="{hx:.2f}" cy="{hy:.2f}" r="17" fill="#ff6a3d" opacity="0.16"/>')
A(f'<circle cx="{hx:.2f}" cy="{hy:.2f}" r="11" fill="#ff8a3d" opacity="0.30"/>')
A(f'<circle cx="{hx:.2f}" cy="{hy:.2f}" r="6.5" fill="#fff1dc"/>')
# ring text
d, w = T(MONOB, "NEXT RUN", 13, 2.6); A(put(d, CX - w/2, 194, MUTED))
d, w = T(MONOB, "01:00", 46, -1.0);   A(put(d, CX - w/2, 248, INK))

# ---------------------------------------------------------------- status pill
px, py = 370, 98
d, w = T(MONOB, "HEALTHY", 13, 2.4)
pw = w + 52
A(f'<rect x="{px}" y="{py}" width="{pw:.2f}" height="30" rx="15" fill="#3fdd8a" opacity="0.10"/>')
A(f'<rect x="{px}.5" y="{py}.5" width="{pw:.2f}" height="29" rx="14.5" fill="none" stroke="{GREEN}" stroke-opacity="0.34"/>')
A(f'<circle cx="{px+19}" cy="{py+15}" r="9" fill="{GREEN}" opacity="0.16"/>')
A(f'<circle cx="{px+19}" cy="{py+15}" r="4.2" fill="{GREEN}"/>')
A(put(d, px + 34, py + 20, GREEN))

# ---------------------------------------------------------------- wordmark
d, w = T(BLACK, "BACKUP", 64, -1.5); A(put(d, 368, 190, INK))
d, w2 = T(BLACK, "SIZZLE", 64, -1.5); A(put(d, 368, 254, "url(#heat)"))
d, w3 = T(MONOR, "restic → Backblaze B2  ·  omarchy bar widget", 14, 0.2)
A(put(d, 370, 292, MUTED))

# ---------------------------------------------------------------- heatmap
HX, HY, CELL, GAP, COLS, ROWS = 760, 106, 20, 6, 17, 7
d, w = T(MONOB, "90-DAY OUTCOMES", 12, 2.4); A(put(d, HX, 92, DIM))
d, w = T(MONOB, "v3.0.0", 12, 2.4);          A(put(d, 1202 - w, 92, DIM))
rng = random.Random(20260906)
GREENS = ["#123a28", "#18613f", "#1f8a57", "#2fbd74", "#48e694"]
n = COLS * ROWS
fails = {23, 61}
warns = {12, 47, 88}
for i in range(n):
    c, r = divmod(i, ROWS)
    x = HX + c * (CELL + GAP)
    y = HY + r * (CELL + GAP)
    age = i / n
    if i < n - 90:
        fill, op = "#101922", 1.0
    elif i in fails:
        fill, op = "#ff4438", 1.0
    elif i in warns:
        fill, op = AMBER, 0.92
    else:
        fill = GREENS[min(4, int(rng.random() * 2.2 + age * 2.6))]
        op = 1.0
    A(f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" rx="5" fill="{fill}" opacity="{op}"/>')
# legend
lx, ly = HX, HY + ROWS * (CELL + GAP) + 16
d, w = T(MONOB, "LESS", 11, 1.8); A(put(d, lx, ly + 9, DIM))
for j, cfill in enumerate(["#101922"] + GREENS):
    A(f'<rect x="{lx + w + 10 + j*16}" y="{ly}" width="11" height="11" rx="3" fill="{cfill}"/>')
d2, w2 = T(MONOB, "MORE", 11, 1.8); A(put(d2, lx + w + 10 + 6*16 + 4, ly + 9, DIM))

# ---------------------------------------------------------------- throughput wave
WX0, WX1, BASE, AMP = 60, 1220, 424, 92
rng2 = random.Random(4242)
pts = []
N = 58
for i in range(N + 1):
    t = i / N
    v = (0.32 * math.sin(t * 11.5) + 0.22 * math.sin(t * 27.3 + 1.1)
         + 0.16 * math.sin(t * 5.1 + 0.4) + 0.30 * rng2.random())
    env = 0.42 + 0.58 * math.sin(math.pi * min(1.0, 0.10 + t * 0.92)) ** 0.7
    v = max(0.04, v * 0.6 + 0.34) * env
    if i in (17, 18, 19): v = min(1.0, v + 0.15)
    if i in (48, 49):     v = min(1.0, v + 0.30)
    pts.append((WX0 + t * (WX1 - WX0), BASE - v * AMP))

def smooth(p):
    dpath = f"M {p[0][0]:.2f} {p[0][1]:.2f}"
    for i in range(len(p) - 1):
        x0, y0 = p[max(i - 1, 0)]; x1, y1 = p[i]; x2, y2 = p[i + 1]
        x3, y3 = p[min(i + 2, len(p) - 1)]
        c1x, c1y = x1 + (x2 - x0) / 6, y1 + (y2 - y0) / 6
        c2x, c2y = x2 - (x3 - x1) / 6, y2 - (y3 - y1) / 6
        dpath += f" C {c1x:.2f} {c1y:.2f} {c2x:.2f} {c2y:.2f} {x2:.2f} {y2:.2f}"
    return dpath

line = smooth(pts)
A(f'<path d="{line} L {WX1} {BASE} L {WX0} {BASE} Z" fill="url(#waveFill)"/>')
for sw, op in ((9, 0.08), (5.5, 0.16)):
    A(f'<path d="{line}" fill="none" stroke="url(#waveLine)" stroke-width="{sw}" opacity="{op}" stroke-linecap="round"/>')
A(f'<path d="{line}" fill="none" stroke="url(#waveLine)" stroke-width="2.6" stroke-linecap="round"/>')
A(f'<line x1="{WX0}" y1="{BASE}" x2="{WX1}" y2="{BASE}" stroke="#1d2a38" stroke-width="1.5"/>')
peak = min(pts, key=lambda p: p[1])
A(f'<line x1="{peak[0]:.2f}" y1="{peak[1]:.2f}" x2="{peak[0]:.2f}" y2="{BASE}" stroke="#ffa63d" stroke-width="1" opacity="0.28" stroke-dasharray="3 4"/>')
A(f'<circle cx="{peak[0]:.2f}" cy="{peak[1]:.2f}" r="9" fill="#ffa63d" opacity="0.18"/>')
A(f'<circle cx="{peak[0]:.2f}" cy="{peak[1]:.2f}" r="4" fill="#ffe0b0"/>')
d, w = T(MONOB, "LIVE B2 UPLOAD", 12, 2.4); A(put(d, 370, 334, DIM))

A('<rect x="0.75" y="0.75" width="1278.5" height="458.5" rx="21.25" fill="none" stroke="#1e2b3a" stroke-width="1.5"/>')
A('</g></svg>')

open(sys.argv[1], "w").write("\n".join(out))
print("wrote", sys.argv[1])
