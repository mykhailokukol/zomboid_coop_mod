"""Draws the AFK sidebar icons and the badge texture, with the standard library only.

    python3 tools/afk_icons.py

Writes into mods/CO-OP/42/media/ui/:
  COOP_Afk_Off_<w>.png / COOP_Afk_On_<w>.png  for w in 48, 64, 80, 96, 128
  COOP_AfkBadge.png                            a white rounded pill, tinted in Lua

The sidebar icons copy the vanilla ones' canvas (w x 0.75w) and their look: a grey
shape with a vertical shading and a thick black outline when off, the same shape in
colour when on. The shape is a crescent moon with two small z's - the usual "away".
Drawn by supersampling a signed coverage test per pixel, so the edges are smooth.
"""
import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "mods", "CO-OP", "42", "media", "ui")

SS = 4  # supersamples per axis


def write_png(path, w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def icon(w, on):
    h = int(w * 0.75)
    s = w / 128.0  # everything below is laid out on the 128 canvas

    # crescent: a disc with a second disc taken out of its upper right
    mx, my, mr = 56 * s, 50 * s, 36 * s
    cx, cy, cr = 74 * s, 36 * s, 30 * s
    outline = 4.5 * s

    # two z's, upper right, each three strokes
    def zed(x, y, size):
        return [
            (x, y, x + size, y),
            (x + size, y, x, y + size),
            (x, y + size, x + size, y + size),
        ]

    zs = zed(88 * s, 14 * s, 14 * s) + zed(104 * s, 40 * s, 10 * s)
    zstroke = 3.2 * s
    zoutline = zstroke + 3.0 * s

    if on:
        top, bottom = (255, 214, 102), (214, 140, 30)
    else:
        top, bottom = (222, 222, 222), (128, 128, 128)

    px = [0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            fill = edge = zfill = zedge = 0
            for sy in range(SS):
                for sx in range(SS):
                    fx = x + (sx + 0.5) / SS
                    fy = y + (sy + 0.5) / SS
                    dm = math.hypot(fx - mx, fy - my) - mr       # <0 inside the moon
                    dc = cr - math.hypot(fx - cx, fy - cy)       # <0 outside the bite
                    d = max(dm, dc)                              # crescent
                    if d < 0:
                        fill += 1
                    elif d < outline:
                        edge += 1
                    if d < 0 and d > -outline:
                        edge += 1
                    dz = min(seg_dist(fx, fy, *seg) for seg in zs)
                    if dz < zstroke / 2:
                        zfill += 1
                    elif dz < zoutline / 2:
                        zedge += 1
            n = SS * SS
            t = y / max(1, h - 1)
            shade = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
            r = g = b = a = 0.0
            # body
            body = (fill - min(fill, edge)) / n
            line = min(1.0, edge / n)
            zf = zfill / n
            ze = zedge / n
            a = min(1.0, body + line + zf + ze)
            if a > 0:
                colour = [0.0, 0.0, 0.0]
                wsum = body + line + zf + ze
                for i in range(3):
                    colour[i] = (shade[i] * body + 0 * line + shade[i] * zf + 0 * ze) / wsum
                r, g, b = colour
            o = (y * w + x) * 4
            px[o:o + 4] = [int(r), int(g), int(b), int(a * 255)]
    return w, h, px


def badge():
    w, h, rad = 64, 24, 11
    px = [0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            cov = 0
            for sy in range(SS):
                for sx in range(SS):
                    fx = x + (sx + 0.5) / SS
                    fy = y + (sy + 0.5) / SS
                    qx = max(rad, min(w - rad, fx))
                    qy = max(rad, min(h - rad, fy))
                    if math.hypot(fx - qx, fy - qy) <= rad:
                        cov += 1
            o = (y * w + x) * 4
            px[o:o + 4] = [255, 255, 255, int(255 * cov / (SS * SS))]
    return w, h, px


def main():
    os.makedirs(OUT, exist_ok=True)
    for w in (48, 64, 80, 96, 128):
        for on in (False, True):
            iw, ih, px = icon(w, on)
            name = "COOP_Afk_%s_%d.png" % ("On" if on else "Off", w)
            write_png(os.path.join(OUT, name), iw, ih, px)
    bw, bh, px = badge()
    write_png(os.path.join(OUT, "COOP_AfkBadge.png"), bw, bh, px)


if __name__ == "__main__":
    main()
