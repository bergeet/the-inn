#!/usr/bin/env python3
"""Draw the tavern and badge artwork for The Inn and save it as TGA files
(the format WoW reads) in TheInn/Media.

Pure Python, no image libraries: every pixel is computed with a little math
and supersampled for smooth edges. Run it again after changing a shader.

    python3 scripts/make_textures.py [preview.png]

With a path, it also writes a PNG preview of the assembled badge.
"""
import math
import os
import struct
import sys
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "TheInn", "Media")


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def render(w, h, shader, ss=3):
    """Run shader(u, v) -> (r, g, b, a) over the image, u and v in 0..1 (v down)."""
    img = []
    n = ss * ss
    for y in range(h):
        row = []
        for x in range(w):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    cr, cg, cb, ca = shader((x + (sx + 0.5) / ss) / w, (y + (sy + 0.5) / ss) / h)
                    r += cr * ca
                    g += cg * ca
                    b += cb * ca
                    a += ca
            if a > 0:
                r, g, b = r / a, g / a, b / a
            row.append((clamp(r), clamp(g), clamp(b), clamp(a / n)))
        img.append(row)
    return img


def save_tga(img, path):
    h, w = len(img), len(img[0])
    # Uncompressed true-color, 32 bpp, 8 alpha bits, rows stored bottom-up:
    # the classic TGA layout every reader (including WoW) understands.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    data = bytearray()
    for row in reversed(img):
        for r, g, b, a in row:
            data += bytes((int(b * 255 + 0.5), int(g * 255 + 0.5), int(r * 255 + 0.5), int(a * 255 + 0.5)))
    with open(path, "wb") as f:
        f.write(header + bytes(data))


def save_png(img, path):
    h, w = len(img), len(img[0])
    raw = bytearray()
    for row in img:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5), int(a * 255 + 0.5)))

    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------------------
# Shaders
# ---------------------------------------------------------------------------

GOLD = (0.98, 0.78, 0.30)
GOLD_DARK = (0.45, 0.28, 0.06)
LIGHT = (-0.6, -0.8)  # light from the top left (v grows downward)

RING_IN, RING_OUT = 0.70, 0.90  # fractions of the texture's half-size


def polar(u, v):
    dx, dy = (u - 0.5) * 2, (v - 0.5) * 2
    r = math.hypot(dx, dy)
    return dx, dy, r


def gold_bevel(t, nx, ny):
    """Gold metal across a bevel: t = 0..1 across the band, (nx, ny) = outward direction."""
    slope = math.cos(math.pi * t)  # + on the inner half (faces inward), - on the outer half
    facing = -(nx * LIGHT[0] + ny * LIGHT[1])  # 1 where the outward direction points away from the light
    shade = clamp(0.55 + 0.45 * slope * -facing * 1.4 + 0.25 * math.sin(math.pi * t))
    col = mix(GOLD_DARK, GOLD, shade)
    spec = smooth(0.82, 1.0, shade) * 0.6
    return mix(col, (1.0, 0.97, 0.85), spec)


def ring(u, v):
    dx, dy, r = polar(u, v)
    if r < RING_IN or r > RING_OUT:
        return (0, 0, 0, 0)
    nx, ny = (dx / r, dy / r) if r > 0 else (0, 0)
    t = (r - RING_IN) / (RING_OUT - RING_IN)
    col = gold_bevel(t, nx, ny)
    # Two engraved grooves and a ring of small studs
    groove = min(abs(t - 0.2), abs(t - 0.8))
    if groove < 0.035:
        col = mix(col, GOLD_DARK, 0.65)
    ang = math.atan2(dy, dx)
    stud = (ang / (2 * math.pi) * 16) % 1.0
    if 0.4 < t < 0.6 and abs(stud - 0.5) < 0.09:
        col = mix(col, (1.0, 0.95, 0.75), 0.55)
    return col + (1.0,)


def disc(u, v):
    _, _, r = polar(u, v)
    if r > RING_OUT - 0.01:
        return (0, 0, 0, 0)
    t = r / RING_OUT
    return mix((0.20, 0.11, 0.08), (0.04, 0.02, 0.02), t) + (1.0,)


def mask(u, v):
    _, _, r = polar(u, v)
    return (1.0, 1.0, 1.0, 1.0 if r <= 0.98 else 0.0)


def glow(u, v):
    _, _, r = polar(u, v)
    a = clamp(1 - r) ** 2
    return (1.0, 0.85, 0.45, a)


def coin(u, v):
    dx, dy, r = polar(u, v)
    if r > 0.96:
        return (0, 0, 0, 0)
    if r > 0.72:
        nx, ny = dx / r, dy / r
        return gold_bevel((r - 0.72) / 0.24, nx, ny) + (1.0,)
    return mix((0.22, 0.10, 0.06), (0.06, 0.03, 0.02), r / 0.72) + (1.0,)


BAND_TOP, BAND_BOT = 0.16, 0.84


def banner(u, v):
    if v < BAND_TOP or v > BAND_BOT:
        return (0, 0, 0, 0)
    mid = (BAND_TOP + BAND_BOT) / 2
    half = (BAND_BOT - BAND_TOP) / 2
    off = abs(v - mid) / half  # 0 in the middle, 1 at the edges
    # Swallowtail on the right: the cut goes deepest in the middle
    end = 0.905 + 0.085 * off
    if u > end:
        return (0, 0, 0, 0)
    trim = 0.055
    edge = 1 - off  # distance from the top/bottom edge (0 at the edge)
    if edge < trim:
        t = edge / trim
        return gold_bevel(t, 0.0, -1.0 if v < mid else 1.0) + (1.0,)
    if edge < trim + 0.025:
        return GOLD_DARK + (1.0,)
    # Fabric: deep red, darker toward the tail, lit from above, faint weave
    base = mix((0.42, 0.07, 0.05), (0.16, 0.03, 0.03), smooth(0.0, 1.0, u))
    shade = 0.85 + 0.25 * (1 - (v - BAND_TOP) / (BAND_BOT - BAND_TOP))
    weave = 0.03 * math.sin(u * 900) * math.sin(v * 700)
    col = tuple(clamp(c * shade + weave) for c in base)
    # Gold stitching just inside the trim
    stitch_d = edge - (trim + 0.06)
    if abs(stitch_d) < 0.012 and (u * 160) % 1.0 < 0.55:
        col = mix(col, GOLD, 0.7)
    return col + (0.97,)


def glint(u, v):
    d = (u - 0.5) + (v - 0.5) * 0.35
    a = math.exp(-(d / 0.11) ** 2) * smooth(0.0, 0.25, v) * smooth(1.0, 0.75, v)
    return (1.0, 1.0, 1.0, a * 0.85)


# ---------------------------------------------------------------------------
# Tavern: wood, the inn sign, the chalkboard
# ---------------------------------------------------------------------------


def hash2(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 362437) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, seed=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash2(ix, iy, seed), hash2(ix + 1, iy, seed)
    c, d = hash2(ix, iy + 1, seed), hash2(ix + 1, iy + 1, seed)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def fbm(x, y, octaves=4, seed=0):
    v, amp, f, tot = 0.0, 0.5, 1.0, 0.0
    for o in range(octaves):
        v += amp * vnoise(x * f, y * f, seed + o * 17)
        tot += amp
        amp *= 0.5
        f *= 2
    return v / tot


def grain(along, across, seed, dark, light):
    """Wood: stripes running along the board, wobbled by noise, with a knot now and then."""
    warp = fbm(along * 0.004, across * 0.05, 3, seed) * 9.0
    stripes = 0.5 + 0.5 * math.sin(across * 0.55 + warp * 2.2)
    fine = fbm(along * 0.08, across * 0.9, 2, seed + 5)
    t = clamp(0.25 + 0.45 * stripes + 0.35 * (fine - 0.5))
    return mix(dark, light, t)


def wall(u, v):
    """The tavern wall: dark vertical planks with gaps and nails."""
    x, y = u * 512, v * 512
    plank_w = 512 / 6
    i = int(x // plank_w)
    lx = x - i * plank_w
    seed = 100 + i * 7
    tone = 0.85 + 0.3 * hash2(i, 0, 3)
    col = grain(y + i * 97, lx, seed, (0.11 * tone, 0.065 * tone, 0.04 * tone), (0.24 * tone, 0.15 * tone, 0.085 * tone))
    if lx < 2.5 or lx > plank_w - 1.5:  # gap between planks
        col = mix(col, (0.02, 0.01, 0.01), 0.85)
    elif lx < 5:  # rounded edge catches a little light
        col = mix(col, (0.32, 0.21, 0.12), 0.25)
    # (No nails: stretched over the window they ended up next to text, looking like glitches.)
    return col + (1.0,)


def plank(u, v):
    """A single horizontal board, for list rows, tabs and buttons (tinted in game)."""
    x, y = u * 512, v * 64
    col = grain(x, y * 1.4, 7, (0.30, 0.19, 0.10), (0.48, 0.31, 0.17))
    edge = min(y, 64 - y)
    if edge < 3:
        col = mix(col, (0.08, 0.05, 0.03), 0.7 * (1 - edge / 3))
    elif y < 7:
        col = mix(col, (0.62, 0.45, 0.28), 0.25 * (1 - (y - 3) / 4))
    for nx in (10, 502):
        d = math.hypot(x - nx, y - 32)
        if d < 3.2:
            col = mix((0.3, 0.3, 0.32), (0.7, 0.7, 0.72), clamp((32 - y + 3) / 6))
    return col + (1.0,)


IRON_DARK, IRON_LIGHT = (0.10, 0.10, 0.11), (0.42, 0.42, 0.45)
CHAIN_X = (128, 384)
BOARD = (18, 78, 494, 246)  # left, top, right, bottom in the 512x256 texture


def iron(t):
    return mix(IRON_DARK, IRON_LIGHT, clamp(t))


def sign(u, v):
    x, y = u * 512, v * 256
    L, T, R, B = BOARD
    # The board: a rounded rectangle of warm wood with a carved inner frame
    r = 16
    cx = min(max(x, L + r), R - r)
    cy = min(max(y, T + r), B - r)
    d_out = math.hypot(x - cx, y - cy) - r  # < 0 inside
    if d_out <= 0:
        inset = -d_out
        col = grain(x, y * 1.2, 21, (0.30, 0.17, 0.08), (0.52, 0.32, 0.15))
        if inset < 4:  # outer bevel: light on top, dark below
            col = mix(col, (0.70, 0.50, 0.28) if y < (T + B) / 2 else (0.10, 0.05, 0.02), 0.55 * (1 - inset / 4))
        elif 12 < inset < 16:  # carved groove
            col = mix(col, (0.12, 0.06, 0.03), 0.75)
        elif 16 <= inset < 17.5:
            col = mix(col, (0.66, 0.46, 0.25), 0.4)
        # Iron eye bolts where the chains attach
        for chx in CHAIN_X:
            dd = math.hypot(x - chx, y - (T + 6))
            if dd < 7:
                return iron(0.3 + 0.7 * (1 - abs(dd - 5) / 2)) + (1.0,) if dd > 3 else col + (1.0,)
        return col + (1.0,)
    # The bracket: an iron bar along the top with a curl at each end
    if 10 <= y <= 22 and 34 <= x <= 478:
        return iron(1 - abs(y - 14) / 8) + (1.0,)
    for ex in (26, 486):
        dd = math.hypot(x - ex, y - 18)
        if 6 <= dd <= 11:
            return iron(0.35 + 0.5 * (1 - abs(dd - 8.5) / 2.5)) + (1.0,)
    # Chains: alternating front-on and side-on links
    for chx in CHAIN_X:
        if abs(x - chx) <= 7 and 20 <= y <= T + 4:
            k = int((y - 20) // 11)
            ly = (y - 20) - k * 11 - 5.5
            if k % 2 == 0:
                e = math.hypot((x - chx) / 5.5, ly / 7.0)
                if 0.62 <= e <= 1.0:
                    return iron(0.25 + 0.75 * (1 - abs(e - 0.81) / 0.19)) + (1.0,)
            elif abs(x - chx) <= 1.6 and abs(ly) <= 7:
                return iron(0.75 - abs(x - chx) * 0.3) + (1.0,)
    return (0, 0, 0, 0)


def chalkboard(u, v):
    x, y = u * 512, v * 256
    frame = 10
    edge = min(x, 512 - x, y, 256 - y)
    if edge < frame:
        col = grain(x + y, edge * 3, 33, (0.22, 0.13, 0.06), (0.40, 0.25, 0.12))
        if edge < 2:
            col = mix(col, (0.05, 0.03, 0.02), 0.7)
        return col + (1.0,)
    slate = mix((0.09, 0.12, 0.10), (0.13, 0.16, 0.14), fbm(x * 0.01, y * 0.02, 3, 41))
    smudge = smooth(0.6, 0.85, fbm(x * 0.012, y * 0.024, 4, 43)) * 0.05  # half-wiped chalk, lightly
    dust = 0.03 * (hash2(int(x), int(y), 47) > 0.985)
    return tuple(clamp(c + smudge + dust) for c in slate) + (1.0,)


def ragged(x, y, w, h, depth, seed):
    """Distance inside a board or sheet whose edges wobble (negative outside)."""
    l = x - depth * vnoise(y * 0.08, 1.0, seed)
    r = (w - x) - depth * vnoise(y * 0.08, 2.0, seed)
    t = y - depth * vnoise(x * 0.05, 3.0, seed)
    b = (h - y) - depth * vnoise(x * 0.05, 4.0, seed)
    return min(l, r, t, b)


def sign_board(u, v):
    """The small hanging sign in the header: a warm board with a dark rim and ragged ends."""
    x, y = u * 512, v * 128
    d = ragged(x, y, 512, 128, 7, 61)
    if d < 0:
        return (0, 0, 0, 0)
    col = grain(x, y * 1.6, 63, (0.42, 0.27, 0.13), (0.70, 0.50, 0.27))
    col = mix(col, (1.0, 0.88, 0.66), 0.10 * (1 - v))  # lamplight from above
    if d < 5:
        col = mix(col, (0.13, 0.07, 0.03), 0.85 * (1 - d / 5))
    return col + (clamp(d / 1.5),)


def parchment(u, v):
    """A pinned note: cream paper, tea-stained, darker and torn at the edges."""
    x, y = u * 512, v * 256
    d = ragged(x, y, 512, 256, 5, 71)
    if d < 0:
        return (0, 0, 0, 0)
    stain = fbm(x * 0.006, y * 0.012, 4, 73)
    col = mix((0.93, 0.86, 0.69), (0.78, 0.64, 0.42), smooth(0.45, 0.9, stain) * 0.8)
    col = mix(col, (0.55, 0.38, 0.18), smooth(18, 0, d) * 0.55)  # browned edges
    fibre = 0.025 * (fbm(x * 0.2, y * 0.03, 2, 75) - 0.5)
    return tuple(clamp(c + fibre) for c in col) + (clamp(d / 1.5),)


def cork(u, v):
    """The gossip board: cork, speckled, in a dark wooden frame."""
    x, y = u * 512, v * 512
    edge = min(x, 512 - x, y, 512 - y)
    if edge < 12:
        col = grain(x + y, edge * 3, 81, (0.14, 0.08, 0.04), (0.26, 0.16, 0.08))
        if edge < 2 or edge > 10.5:
            col = mix(col, (0.03, 0.02, 0.01), 0.75)
        return col + (1.0,)
    base = mix((0.36, 0.23, 0.12), (0.50, 0.34, 0.18), fbm(x * 0.03, y * 0.03, 3, 83))
    h = hash2(int(x / 2), int(y / 2), 85)
    if h > 0.93:
        base = mix(base, (0.18, 0.11, 0.05), 0.6)
    elif h < 0.05:
        base = mix(base, (0.68, 0.52, 0.32), 0.5)
    shade = smooth(12, 40, edge)  # shadow under the frame
    return tuple(c * (0.7 + 0.3 * shade) for c in base) + (1.0,)


def corner(u, v):
    """An iron corner bracket with a rivet, for the window's top-left corner (mirrored in game)."""
    x, y = u * 64, v * 64
    arm = sd_box(x, y, 22, 5, 22, 5, 1.5)
    arm2 = sd_box(x, y, 5, 22, 5, 22, 1.5)
    d = min(arm, arm2)
    if d > 1:
        return (0, 0, 0, 0)
    t = clamp(0.5 - 0.5 * (x + y) / 64)
    col = mix((0.13, 0.12, 0.11), (0.33, 0.31, 0.28), t)
    if d > -1.2:
        col = (0.05, 0.04, 0.035)
    r = math.hypot(x - 6, y - 6)
    if r < 3.4:
        col = mix((0.94, 0.88, 0.70), (0.45, 0.40, 0.30), clamp(r / 3.4))
        if r > 2.8:
            col = (0.07, 0.05, 0.03)
    return col + (clamp(1 - d),)


# ---------------------------------------------------------------------------
# Achievement alert, in the style of the classic (Wrath-era) one: a dark bar
# with a gold frame, the icon in a gold square, the points on a shield.
# ---------------------------------------------------------------------------


def round_rect_dist(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
    out = math.hypot(max(qx, 0), max(qy, 0))
    return out + min(max(qx, qy), 0) - r


ALERT_BODY = (256, 70, 244, 44, 16)  # cx, cy, half width, half height, corner radius (512x128 texture)
ALERT_TAB = (256, 22, 92, 13, 8)


def alert_frame(u, v):
    x, y = u * 512, v * 128
    cx, cy, hw, hh, r = ALERT_BODY
    d = round_rect_dist(x, y, cx, cy, hw, hh, r)
    tcx, tcy, thw, thh, tr = ALERT_TAB
    dt = round_rect_dist(x, y, tcx, tcy, thw, thh, tr)
    border = 7
    if dt <= 0:  # the tab on top, for "Achievement Earned"
        inset = -dt
        if inset < 4:
            return gold_bevel(inset / 4, 0, -1 if y < tcy else 1) + (1.0,)
        return mix((0.10, 0.07, 0.04), (0.05, 0.03, 0.02), (y - (tcy - thh)) / (2 * thh)) + (1.0,)
    if d > 0:
        return (0, 0, 0, 0)
    inset = -d
    if inset < border:  # gold frame, beveled
        ny = -1 if y < cy else 1
        nx = -1 if x < cx else 1
        return gold_bevel(inset / border, nx * 0.3, ny) + (1.0,)
    if inset < border + 1.5:
        return (0.05, 0.03, 0.02, 1.0)
    # Body: dark stone, a little lighter at the top, with faint texture
    t = (y - (cy - hh)) / (2 * hh)
    base = mix((0.20, 0.18, 0.16), (0.07, 0.06, 0.05), t)
    n = (fbm(x * 0.05, y * 0.05, 3, 61) - 0.5) * 0.06
    return tuple(clamp(c + n) for c in base) + (0.97,)


def alert_glow(u, v):
    x, y = u * 512, v * 128
    cx, cy, hw, hh, r = ALERT_BODY
    d = round_rect_dist(x, y, cx, cy, hw, hh, r)
    a = clamp(1 - abs(d) / 18) ** 2
    return (1.0, 0.85, 0.35, a)


def shield(u, v):
    """A heater shield: flat top, straight sides, curving to a point."""
    x, y = (u - 0.5) * 2, v
    top, bottom, shoulder, half = 0.06, 0.96, 0.42, 0.78
    if y < top or y > bottom:
        return (0, 0, 0, 0)
    if y <= shoulder:
        w = half
    else:
        t = (y - shoulder) / (bottom - shoulder)
        w = half * math.sqrt(max(0.0, 1 - t ** 1.6))
    if abs(x) > w:
        return (0, 0, 0, 0)
    edge = min(w - abs(x), y - top)
    rim = 0.13
    if edge < rim:
        return gold_bevel(edge / rim, -1 if x < 0 else 1, -1 if y < 0.5 else 1) + (1.0,)
    if edge < rim + 0.025:
        return (0.18, 0.10, 0.03, 1.0)
    # Field: deep bronze, lit from the top left
    shade = clamp(0.75 - x * 0.25 - (y - 0.3) * 0.5)
    return mix((0.22, 0.12, 0.04), (0.55, 0.36, 0.12), shade) + (1.0,)


def icon_frame(u, v):
    """A square gold frame for an icon, open in the middle."""
    x, y = u * 128, v * 128
    d = round_rect_dist(x, y, 64, 64, 60, 60, 8)
    if d > 0:
        return (0, 0, 0, 0)
    inset = -d
    if inset > 12:
        return (0, 0, 0, 0)
    if inset > 10:
        return (0.06, 0.04, 0.02, 1.0)
    return gold_bevel(inset / 10, -1 if x < 64 else 1, -1 if y < 64 else 1) + (1.0,)


# ---------------------------------------------------------------------------
# Chess pieces: silhouettes built from simple shapes (signed distances, so
# the outline comes for free), ivory for white and ebony for black.
# ---------------------------------------------------------------------------


def sd_circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r


def sd_box(x, y, cx, cy, hw, hh, r=0.0):
    return round_rect_dist(x, y, cx, cy, hw, hh, r)


def sd_poly(x, y, pts):
    d, inside = 1e9, False
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        t = clamp(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey))
        d = min(d, math.hypot(x - ax - ex * t, y - ay - ey * t))
        if (ay > y) != (by > y) and x < ax + (y - ay) * ex / (by - ay):
            inside = not inside
    return -d if inside else d


def sd_segment(x, y, ax, ay, bx, by):
    ex, ey = bx - ax, by - ay
    t = clamp(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey))
    return math.hypot(x - ax - ex * t, y - ay - ey * t)


def base(x, y):
    return min(sd_box(x, y, 0.5, 0.87, 0.30, 0.055, 0.03), sd_box(x, y, 0.5, 0.79, 0.22, 0.03, 0.01))


def body(x, y, top, hw_top, hw_bottom=0.15):
    return sd_poly(x, y, [(0.5 - hw_bottom, 0.78), (0.5 + hw_bottom, 0.78), (0.5 + hw_top, top), (0.5 - hw_top, top)])


def pawn(x, y):
    return min(base(x, y), body(x, y, 0.47, 0.06, 0.16), sd_box(x, y, 0.5, 0.48, 0.13, 0.025, 0.01),
               sd_circle(x, y, 0.5, 0.33, 0.13)), []


def rook(x, y):
    top = sd_box(x, y, 0.5, 0.29, 0.21, 0.08, 0.01)
    for cx in (0.40, 0.60):  # crenels
        top = max(top, -sd_box(x, y, cx, 0.22, 0.035, 0.05))
    return min(base(x, y), sd_box(x, y, 0.5, 0.56, 0.15, 0.22, 0.01), top), []


def bishop(x, y):
    mitre = min(sd_circle(x, y, 0.5, 0.40, 0.155), sd_poly(x, y, [(0.37, 0.36), (0.63, 0.36), (0.5, 0.15)]))
    shape = min(base(x, y), body(x, y, 0.55, 0.07, 0.15), sd_box(x, y, 0.5, 0.57, 0.14, 0.025, 0.01),
                mitre, sd_circle(x, y, 0.5, 0.135, 0.045))
    return shape, [((0.45, 0.29), (0.57, 0.42))]  # the slit


def knight(x, y):
    head = sd_poly(x, y, [(0.70, 0.78), (0.72, 0.52), (0.69, 0.33), (0.61, 0.21), (0.57, 0.09), (0.50, 0.17),
                          (0.41, 0.20), (0.27, 0.35), (0.21, 0.46), (0.27, 0.53), (0.38, 0.49), (0.47, 0.50),
                          (0.37, 0.66), (0.32, 0.78)])
    return min(base(x, y), head), [("eye", 0.44, 0.31, 0.022), ((0.62, 0.24), (0.66, 0.50))]  # eye, mane


def queen(x, y):
    crown = sd_poly(x, y, [(0.25, 0.27), (0.35, 0.47), (0.40, 0.22), (0.50, 0.44), (0.60, 0.22), (0.65, 0.47),
                           (0.75, 0.27), (0.67, 0.62), (0.33, 0.62)])
    balls = min(sd_circle(x, y, 0.25, 0.25, 0.045), sd_circle(x, y, 0.40, 0.20, 0.045),
                sd_circle(x, y, 0.60, 0.20, 0.045), sd_circle(x, y, 0.75, 0.25, 0.045))
    return min(base(x, y), body(x, y, 0.60, 0.11, 0.15), crown, balls), []


def king(x, y):
    cross = min(sd_box(x, y, 0.5, 0.15, 0.028, 0.09), sd_box(x, y, 0.5, 0.14, 0.08, 0.028))
    head = min(sd_circle(x, y, 0.5, 0.40, 0.165), sd_box(x, y, 0.5, 0.27, 0.05, 0.04))
    return min(base(x, y), body(x, y, 0.55, 0.11, 0.15), head, cross), []


PIECES = {"K": king, "Q": queen, "R": rook, "B": bishop, "N": knight, "P": pawn}


def piece_shader(shape, white):
    def shader(u, v):
        d, lines = shape(u, v)
        if d > 0:
            # A soft shadow just outside, so pieces read on both square colors
            a = clamp(1 - d / 0.035) * 0.35
            return (0, 0, 0, a)
        inset = -d
        outline = 0.028
        if white:
            fill = mix((0.98, 0.95, 0.86), (0.72, 0.64, 0.52), clamp(0.2 + (u - 0.4) * 0.9 + (v - 0.3) * 0.5))
            edge = (0.18, 0.11, 0.06)
        else:
            fill = mix((0.38, 0.28, 0.22), (0.10, 0.07, 0.06), clamp(0.2 + (u - 0.4) * 0.9 + (v - 0.3) * 0.5))
            edge = (0.82, 0.66, 0.40)  # a gold rim so black reads on dark squares
        if inset < outline:
            return edge + (1.0,)
        for line in lines:
            if line[0] == "eye":
                if math.hypot(u - line[1], v - line[2]) < line[3]:
                    return edge + (1.0,)
            elif sd_segment(u, v, line[0][0], line[0][1], line[1][0], line[1][1]) < 0.016:
                return edge + (1.0,)
        return fill + (1.0,)
    return shader


def dot(u, v):
    _, _, r = polar(u, v)
    return (1.0, 1.0, 1.0, clamp((1 - r) * 3))


# ---------------------------------------------------------------------------
# The addon's icon: a tankard of beer with foam spilling over
# ---------------------------------------------------------------------------


def beer(u, v):
    x, y = u, v
    body = sd_box(x, y, 0.44, 0.60, 0.25, 0.30, 0.06)
    handle = abs(sd_circle(x, y, 0.71, 0.58, 0.14)) - 0.045
    handle = max(handle, -(x - 0.66))  # only the part sticking out of the mug
    foam = min(sd_circle(x, y, 0.27, 0.30, 0.10), sd_circle(x, y, 0.40, 0.24, 0.12),
               sd_circle(x, y, 0.55, 0.27, 0.11), sd_circle(x, y, 0.65, 0.33, 0.08),
               sd_box(x, y, 0.44, 0.36, 0.25, 0.06, 0.04),
               sd_circle(x, y, 0.21, 0.42, 0.045), sd_box(x, y, 0.21, 0.47, 0.03, 0.06, 0.03))  # a drip
    shape = min(body, handle, foam)
    if shape > 0:
        return (0, 0, 0, clamp(1 - shape / 0.04) * 0.5)  # soft shadow
    outline = (0.16, 0.08, 0.03)
    if -shape < 0.03:
        return outline + (1.0,)
    if foam <= 0:
        t = clamp((y - 0.18) / 0.25)
        return mix((1.0, 0.99, 0.94), (0.86, 0.80, 0.68), t) + (1.0,)
    if handle <= 0 and body > 0:
        return mix((0.62, 0.42, 0.20), (0.36, 0.22, 0.10), clamp((x - 0.70) * 5)) + (1.0,)
    # Beer: amber, darker at the bottom, a highlight down the left, and bubbles
    t = clamp((y - 0.40) / 0.5)
    col = mix((1.0, 0.78, 0.22), (0.78, 0.42, 0.06), t)
    if 0.24 < x < 0.29:
        col = mix(col, (1.0, 0.97, 0.80), 0.55)
    for bx, by, br in ((0.38, 0.62, 0.018), (0.50, 0.72, 0.014), (0.45, 0.52, 0.012), (0.56, 0.58, 0.016)):
        if abs(math.hypot(x - bx, y - by) - br) < 0.006:
            col = mix(col, (1.0, 0.95, 0.75), 0.7)
    # Wooden hoops around the mug
    for hy in (0.50, 0.80):
        if abs(y - hy) < 0.025:
            col = mix((0.55, 0.36, 0.16), (0.30, 0.18, 0.08), abs(y - hy) / 0.025)
    return col + (1.0,)


TEXTURES = [
    ("Wall", 512, 512, wall),
    ("Plank", 512, 64, plank),
    ("Sign", 512, 256, sign),
    ("Chalkboard", 512, 256, chalkboard),
    ("SignBoard", 512, 128, sign_board),
    ("Parchment", 512, 256, parchment),
    ("Cork", 512, 512, cork),
    ("Corner", 64, 64, corner),
    ("BadgeDisc", 128, 128, disc),
    ("BadgeGlint", 64, 128, glint),
    ("AlertFrame", 512, 128, alert_frame),
    ("AlertGlow", 512, 128, alert_glow),
    ("AlertShield", 128, 128, shield),
    ("AlertIconFrame", 128, 128, icon_frame),
    ("ChessDot", 64, 64, dot),
    ("Icon", 128, 128, beer),
]
for _color in ("w", "b"):
    for _kind, _shape in PIECES.items():
        TEXTURES.append(("Chess" + _color.upper() + _kind, 128, 128, piece_shader(_shape, _color == "w")))



def composite(dst, src, ox, oy, sw, sh, add=False, alpha=1.0):
    """Nearest-sample src scaled to sw x sh onto dst at (ox, oy), for the preview."""
    sh0, sw0 = len(src), len(src[0])
    for y in range(sh):
        for x in range(sw):
            px, py = ox + x, oy + y
            if not (0 <= py < len(dst) and 0 <= px < len(dst[0])):
                continue
            r, g, b, a = src[int(y * sh0 / sh)][int(x * sw0 / sw)]
            a *= alpha
            dr, dg, db, da = dst[py][px]
            if add:
                dst[py][px] = (clamp(dr + r * a), clamp(dg + g * a), clamp(db + b * a), da)
            else:
                dst[py][px] = (dr + (r - dr) * a, dg + (g - dg) * a, db + (b - db) * a, max(da, a))


def main():
    os.makedirs(ROOT, exist_ok=True)
    imgs = {}
    for name, w, h, shader in TEXTURES:
        # Big wood textures don't need supersampling; edges of round things do.
        imgs[name] = render(w, h, shader, ss=1 if name in ("Wall", "Plank", "Chalkboard", "Cork", "Parchment", "SignBoard") else 3)
        save_tga(imgs[name], os.path.join(ROOT, name + ".tga"))
        if name == "Icon":  # also as a PNG for the repo's README (GitHub doesn't show TGA)
            docs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
            os.makedirs(docs, exist_ok=True)
            save_png(imgs[name], os.path.join(docs, "icon.png"))
        print("wrote", name + ".tga", w, "x", h)

    if len(sys.argv) > 1:
        # Rough preview of the alert (the game adds the icon, text and animation)
        W, H = 560, 170
        out = [[(0.05, 0.05, 0.06, 1.0)] * W for _ in range(H)]
        composite(out, imgs["AlertGlow"], 10, 10, 540, 150, add=True, alpha=0.5)
        composite(out, imgs["AlertFrame"], 30, 25, 500, 125)
        icon = [[(0.25 + 0.5 * x / 63, 0.45, 0.85 - 0.5 * y / 63, 1.0) for x in range(64)] for y in range(64)]
        composite(out, icon, 64, 74, 56, 56)
        composite(out, imgs["AlertIconFrame"], 56, 66, 72, 72)
        composite(out, imgs["AlertShield"], 440, 66, 72, 72)
        composite(out, imgs["BadgeGlint"], 300, 50, 40, 100, add=True, alpha=0.6)
        save_png(out, sys.argv[1])
        print("preview", sys.argv[1])
        I = [[(0.12, 0.12, 0.14, 1.0)] * 220 for _ in range(128)]
        composite(I, imgs["Icon"], 0, 0, 128, 128)
        composite(I, imgs["Icon"], 140, 20, 32, 32)
        composite(I, imgs["Icon"], 190, 30, 18, 18)
        save_png(I, sys.argv[1].replace(".png", "_icon.png"))
        # Chess pieces on board squares
        B = [[(0.0, 0.0, 0.0, 1.0)] * 480 for _ in range(160)]
        for i in range(12):
            col, row = i % 6, i // 6
            light = (col + row) % 2 == 0
            sq = [[((0.86, 0.72, 0.52) if light else (0.52, 0.33, 0.18)) + (1.0,)] * 80 for _ in range(80)]
            composite(B, sq, col * 80, row * 80, 80, 80)
            name = "Chess" + ("W" if row == 0 else "B") + "KQRBNP"[col]
            composite(B, imgs[name], col * 80 + 4, row * 80 + 4, 72, 72)
        save_png(B, sys.argv[1].replace(".png", "_chess.png"))
        # And the tavern pieces side by side
        T = [[(0.0, 0.0, 0.0, 1.0)] * 760 for _ in range(560)]
        composite(T, imgs["Wall"], 0, 0, 760, 560)
        composite(T, imgs["Sign"], 205, 0, 350, 175)
        for i in range(4):
            composite(T, imgs["Plank"], 180, 230 + i * 54, 560, 50, alpha=1.0)
        composite(T, imgs["Chalkboard"], 20, 230, 150, 300)
        save_png(T, sys.argv[1].replace(".png", "_tavern.png"))
        print("preview", sys.argv[1].replace(".png", "_tavern.png"))


if __name__ == "__main__":
    main()
