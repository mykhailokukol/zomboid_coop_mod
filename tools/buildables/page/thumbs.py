import json, struct, io, sys, collections
from PIL import Image
PACK = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media\texturepacks\Tiles2x.pack"
cat = json.load(open("catalog.json"))["objects"]
P = json.load(open("pack2x.json")); idx = P["idx"]; pages = P["pages"]
need = collections.defaultdict(set)
for o in cat:
    face = next(iter(o["faces"].values()))
    for _, s in face:
        if s in idx: need[idx[s][0]].add(s)
crops = {}
f = open(PACK, "rb")
for p, names in sorted(need.items()):
    f.seek(pages[p][1]); img = Image.open(io.BytesIO(f.read(pages[p][2]))).convert("RGBA")
    for s in names:
        _, x, y, w, h, ox, oy, fw, fh = idx[s]
        crops[s] = (img.crop((x, y, x + w, y + h)), ox, oy)
    print("page", p, len(names), flush=True)
CW, CH, COLS, ROWS = 96, 128, 16, 16
out = {}; sheets = []; sheet = None; n = 0
for o in cat:
    face = next(iter(o["faces"].values()))
    parts = []
    for pos, s in face:
        if s not in crops: continue
        gx, gy = pos[0], pos[1]; gz = pos[2] if len(pos) > 2 else 0
        parts.append(((gz, gx + gy), (gx - gy) * 64, (gx + gy) * 32 - gz * 192, crops[s]))
    if not parts: continue
    parts.sort(key=lambda t: t[0])
    minx = min(dx + c[1] for _, dx, dy, c in parts); miny = min(dy + c[2] for _, dx, dy, c in parts)
    maxx = max(dx + c[1] + c[0].width for _, dx, dy, c in parts); maxy = max(dy + c[2] + c[0].height for _, dx, dy, c in parts)
    canvas = Image.new("RGBA", (maxx - minx, maxy - miny))
    for _, dx, dy, (im, ox, oy) in parts:
        canvas.alpha_composite(im, (dx + ox - minx, dy + oy - miny))
    bb = canvas.getbbox()
    if bb: canvas = canvas.crop(bb)
    scale = min(1.0, CW / canvas.width, CH / canvas.height)
    if scale < 1: canvas = canvas.resize((max(1, round(canvas.width * scale)), max(1, round(canvas.height * scale))), Image.LANCZOS)
    if n % (COLS * ROWS) == 0:
        sheet = Image.new("RGBA", (CW * COLS, CH * ROWS)); sheets.append(sheet)
    k = n % (COLS * ROWS); cx, cy = (k % COLS) * CW, (k // COLS) * CH
    sheet.paste(canvas, (cx + (CW - canvas.width) // 2, cy + CH - canvas.height))
    out[o["id"]] = [len(sheets) - 1, k]
    n += 1
for i, s in enumerate(sheets):
    s.save(f"sheet{i}.webp", "WEBP", quality=82, method=6)
json.dump(out, open("thumbs.json", "w"))
print(n, "thumbs,", len(sheets), "sheets")
