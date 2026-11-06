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

def polar(u, v):
    dx, dy = (u - 0.5) * 2, (v - 0.5) * 2
    r = math.hypot(dx, dy)
    return dx, dy, r


def round_rect_dist(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
    out = math.hypot(max(qx, 0), max(qy, 0))
    return out + min(max(qx, qy), 0) - r


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


# Only the chess pieces are the addon's own art; everything else in the UI
# uses the game's own textures. The beer mug is drawn for the repository's
# README (docs/icon.png) only.
TEXTURES = [
    ("ChessDot", 32, 32, dot),
]
for _color in ("w", "b"):
    for _kind, _shape in PIECES.items():
        TEXTURES.append(("Chess" + _color.upper() + _kind, 64, 64, piece_shader(_shape, _color == "w")))


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
        imgs[name] = render(w, h, shader, ss=3)
        save_tga(imgs[name], os.path.join(ROOT, name + ".tga"))
        print("wrote", name + ".tga", w, "x", h)
    # The README's icon (GitHub doesn't show TGA); the game uses one of its own icons
    docs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
    os.makedirs(docs, exist_ok=True)
    save_png(render(128, 128, beer, ss=3), os.path.join(docs, "icon.png"))
    print("wrote docs/icon.png")

    if len(sys.argv) > 1:
        # Chess pieces on board squares
        B = [[(0.0, 0.0, 0.0, 1.0)] * 480 for _ in range(160)]
        for i in range(12):
            col, row = i % 6, i // 6
            light = (col + row) % 2 == 0
            sq = [[((0.86, 0.72, 0.52) if light else (0.52, 0.33, 0.18)) + (1.0,)] * 80 for _ in range(80)]
            composite(B, sq, col * 80, row * 80, 80, 80)
            name = "Chess" + ("W" if row == 0 else "B") + "KQRBNP"[col]
            composite(B, imgs[name], col * 80 + 4, row * 80 + 4, 72, 72)
        save_png(B, sys.argv[1])
        print("preview", sys.argv[1])


if __name__ == "__main__":
    main()
