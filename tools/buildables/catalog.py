"""The buildable-object catalog: every placeable tile in the game grouped into objects,
each priced with the CO-OP build formula.

Used by generate.py (the entity scripts the mod ships) and by page/ (the browse page
the picks were made on). Standard library only.

Where the data comes from
-------------------------
media/newtiledefinitions.tiles.txt is a text dump of every tile's properties that the
game ships next to the binary .tiles file. The properties that matter here:

  IsMoveAble          the tile can be picked up and placed - the candidates
  CustomName/GroupName the moveable's name ("Fancy" + "Bed"); Translate/<lang>/
                      Moveables.json has the display name under "Fancy_Bed"
  Facing, SpriteGridPos which way a tile faces, and its cell in a multi-tile object
  Material(2,3)       what scrapping it gives back; here, what building it costs
  PickUpWeight        tenths of a kilo, per tile
  PickUpTool/Level    what vanilla wants to pick it up - an appliance's Electrical
                      level is taken from here
  MoveType            Window, WallObject, ... (Vegitation and FloorTile are skipped)
"""
import collections
import json
import math
import os
import re

GAME = os.environ.get("PZ_MEDIA", "/mnt/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media")
TILE_DUMP = GAME + "/newtiledefinitions.tiles.txt"


# ---------------------------------------------------------------------------
# reading the game
# ---------------------------------------------------------------------------

def load_tiles(path=TILE_DUMP):
    """sprite name -> {property: value}"""
    tiles, cur, tileset, width = {}, None, None, 0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        m = re.match(r"file = (\S+)", line)
        if m:
            tileset = m.group(1)
            continue
        m = re.match(r"size = (\d+),(\d+)", line)
        if m:
            width = int(m.group(1))
            continue
        m = re.match(r"xy = (\d+),(\d+)", line)
        if m:
            cur = {}
            tiles[f"{tileset}_{int(m.group(2)) * width + int(m.group(1))}"] = cur
            continue
        m = re.match(r"(\w+) = ?(.*)$", line)
        if m and cur is not None:
            cur[m.group(1)] = m.group(2)
    return tiles


def vanilla_entity_sprites():
    """Every sprite a vanilla entity already uses. A sprite may belong to one entity
    only (SpriteConfigManager throws "Sprite ... is duplicate"), so these are out."""
    used = set()
    for root, _, files in os.walk(GAME + "/scripts"):
        for f in files:
            if f.endswith(".txt"):
                text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                for m in re.finditer(r"row\s*=\s*([^,\n]+)", text):
                    used.update(m.group(1).split())
    return used


def idx(name):
    return int(name.rsplit("_", 1)[1])


def tileset(name):
    return name.rsplit("_", 1)[0]


# ---------------------------------------------------------------------------
# the formula
# ---------------------------------------------------------------------------

METAL = {"MetalPlates", "SmallMetalPlates", "MetalScrap", "MetalBars", "MetalPipe",
         "AluminumScrap", "Steel"}
ELECTRIC = {"Electric", "Fridge", "Mechanical"}


def materials(p):
    out = [p.get(k) for k in ("Material", "Material2", "Material3")]
    out = [m for m in out if m and m != "Undefined"]
    if not out:
        mt = (p.get("MaterialType") or "").split("_")[0]
        out = [{"Wood": "Wood", "Metal": "MetalScrap", "Glass": "Glass", "Fabric": "Fabric",
                "Plastic": "Plastic", "Stone": "Stone", "Ceramic": "Stone"}.get(mt, "Wood")]
    return out


# A material's share of the budget, in kilos, becomes items: (item, kg per item, cap).
CONVERT = {
    "Wood": [("Base.Plank", 3.0, 12)],
    "Log": [("Base.Plank", 3.0, 12)],
    "Nails": [("Base.Nails", 0.5, 12)],
    "Steel": [("Base.Screws", 0.5, 12)],
    "MetalPlates": [("Base.SheetMetal", 2.0, 8)],
    "SmallMetalPlates": [("Base.SmallSheetMetal", 0.5, 10)],
    "MetalBars": [("Base.MetalBar", 1.5, 8)],
    "MetalPipe": [("Base.MetalPipe", 1.5, 8)],
    "MetalScrap": [("Base.ScrapMetal", 1.0, 10)],
    "AluminumScrap": [("Base.AluminumScrap", 0.5, 10)],
    "Electric": [("Base.ElectronicsScrap", 0.5, 6), ("Base.ElectricWire", 3.0, 3)],
    "Fridge": [("Base.SheetMetal", 3.0, 6), ("Base.ElectronicsScrap", 3.0, 3)],
    "Mechanical": [("Base.ScrapMetal", 1.5, 8), ("Base.Screws", 1.0, 8)],
    "Plumbing": [("Base.MetalPipe", 2.0, 6), ("Base.Screws", 1.0, 8)],
    "Fabric": [("Base.Sheet", 1.0, 6), ("Base.Thread", 3.0, 3)],
    "Foam": [("Base.Sheet", 1.0, 6)],
    "Leather": [("Base.LeatherStrips", 0.3, 12)],
    "Glass": [("Base.GlassPanel", 1.0, 8)],
    "Brick": [("Base.ClayBrick", 0.5, 20)],
    "Stone": [("Base.ClayBrick", 0.5, 20)],
    "Paper": [("Base.SheetPaper2", 0.2, 10)],
    "Plastic": [("Base.Glue", 3.0, 2)],
    "PlasticHard": [("Base.Glue", 3.0, 2)],
    "PlasticBag": [("Base.Plasticbag", 0.5, 4)],
    "Natural": [("Base.Twigs", 0.3, 10)],
}
SHARE = {1: [1.0], 2: [0.7, 0.3], 3: [0.6, 0.3, 0.1]}
ITEM_CAP = {"Base.ElectronicsScrap": 8, "Base.Nails": 12, "Base.Screws": 12}


def inputs_for(mats, kg):
    """About three quarters of the object's weight, split across its material slots."""
    budget = kg * 0.75
    out = collections.OrderedDict()
    for m, share in zip(mats, SHARE[len(mats)]):
        for item, per, cap in CONVERT.get(m, CONVERT["Wood"]):
            n = max(1, min(cap, round(budget * share / per)))
            out[item] = min(ITEM_CAP.get(item, 99), out.get(item, 0) + n)
    return [[k, v] for k, v in out.items()]


def size_step(kg):
    return 0 if kg < 10 else 1 if kg < 30 else 2 if kg < 60 else 3


def level(base, kg, tiles_n):
    """Vanilla pickup level, + a step for size, + 1 for a multi-tile object; 1..10."""
    return max(1, min(10, base + size_step(kg) + (1 if tiles_n > 1 else 0)))


def price(p, kg, tiles_n, kind, name=""):
    """-> {skills, tools, inputs, xp, time, action}. kind is the object's category."""
    mats = materials(p)
    pick = int(p.get("PickUpLevel") or 1)
    main = mats[0]
    metalish = main in METAL or main in ("Fridge", "Mechanical", "Plumbing") or \
        (p.get("MaterialType") or "").startswith("Metal")
    extra = []

    if kind == "windows":
        # vanilla's own glazed window is 4 panes, 2 planks, 4 nails a wall section
        skills = [["Glassmaking", level(2, kg, tiles_n)]]
        inputs = [["Base.GlassPanel", 4 * tiles_n]]
        if "metal" in p.get("_set", ""):
            skills.append(["MetalWelding", 3])
            inputs.append(["Base.SmallSheetMetal", 2 * tiles_n])
            tools, action = ["BlowTorch", "WeldingRods", "WeldingMask"], "BuildMetalStructureMedium"
        else:
            skills.append(["Woodwork", 3])
            inputs += [["Base.Plank", 2 * tiles_n], ["Base.Nails", 4 * tiles_n]]
            tools, action = ["Hammer"], "BuildWoodenStructureMedium"
    elif kind == "frames":
        # vanilla's wooden window frame is 2 planks and 4 nails on a wall frame
        skills = [["Woodwork", 3]]
        inputs = [["Base.Plank", 3], ["Base.Nails", 6]]
        tools, action = ["Hammer"], "BuildWallHammer"
    elif kind == "walls":
        # standalone wall pieces, priced by what the wall is made of
        wmat = p.get("_wallmat", "wood")
        if wmat == "masonry":
            skills = [["Masonry", 3]]
            inputs = [["Base.ClayBrick", 10]]
            tools, action = ["Trowel"], "Make_With_Brick"
        elif wmat == "metal":
            skills = [["MetalWelding", 3]]
            inputs = [["Base.SheetMetal", 3]]
            tools, action = ["BlowTorch", "WeldingRods", "WeldingMask"], "BuildWallMetal"
        elif wmat == "glass":
            skills = [["Glassmaking", 2], ["Woodwork", 2]]
            inputs = [["Base.GlassPanel", 4], ["Base.Plank", 2], ["Base.Nails", 4]]
            tools, action = ["Hammer"], "BuildWallHammer"
        else:
            skills = [["Woodwork", 3]]
            inputs = [["Base.Plank", 4], ["Base.Nails", 8]]
            tools, action = ["Hammer", "Saw"], "BuildWallHammer"
    elif kind == "plants":
        if "Plantbed" in name:
            skills = [["Woodwork", level(1, kg, tiles_n)]]
            inputs = [["Base.Plank", 3], ["Base.Nails", 6], ["Base.Dirtbag", 2]]
            tools, action = ["Hammer"], "BuildWoodenStructureMedium"
        else:
            skills = [["Farming", level(1, kg, tiles_n)]]
            inputs = [["Base.Dirtbag", 2 if kg >= 10 else 1], ["Base.Sapling", 1]]
            tools, action = [], "BuildLowNoTool"
    elif main in ("Brick", "Stone"):
        skills = [["Masonry", level(pick, kg, tiles_n)]]
        inputs = inputs_for(mats, kg)
        tools, action = ["Trowel"], "Make_With_Brick"
    elif metalish:
        skills = [["MetalWelding", level(pick, kg, tiles_n)]]
        inputs = inputs_for(mats, kg)
        if kg >= 5:
            tools, action = ["BlowTorch", "WeldingRods", "WeldingMask"], "BuildMetalStructureMedium"
        else:
            tools, action = ["Screwdriver"], "BuildWoodenStructureSmall"
    else:
        skills = [["Woodwork", level(pick, kg, tiles_n)]]
        inputs = inputs_for(mats, kg)
        tools = ["Hammer"] + (["Saw"] if kg >= 15 else [])
        action = "BuildWoodenStructureMedium" if kg >= 10 else "BuildWoodenStructureSmall"

    if kind in ("appliances", "lighting"):
        # the Electrical level vanilla asks to pick it up
        skills.append(["Electricity", max(1, pick)])
        if "Screwdriver" not in tools:
            tools.append("Screwdriver")
        have = {i for i, _ in inputs}
        if "Base.ElectronicsScrap" not in have:
            inputs.append(["Base.ElectronicsScrap", 2])
        if "Base.ElectricWire" not in have:
            inputs.append(["Base.ElectricWire", 1])
        if kind == "lighting":
            extra.append(["Base.LightBulb", 1])

    top = max(l for _, l in skills)
    return {
        "skills": skills,
        "tools": tools,
        "inputs": inputs + extra,
        "xp": int(round(10 * top + kg / 2)),
        "time": int(min(400, 50 + kg * 2)),
        "action": action,
        "kg": kg,
    }


# ---------------------------------------------------------------------------
# grouping tiles into objects
# ---------------------------------------------------------------------------

def category_of(name, p):
    if p.get("MoveType") == "Window":
        return "windows"
    if name.startswith("vegetation_"):
        return "plants"
    if name.startswith("lighting_"):
        return "lighting"
    mats = materials(p)
    if any(m in ELECTRIC for m in mats) or p.get("PickUpTool") == "Electrician" \
            or "IsFridge" in p or p.get("IsoType") in (
                "IsoStove", "IsoRadio", "IsoTelevision", "IsoClothingWasher",
                "IsoClothingDryer", "IsoCombinationWasherDryer"):
        return "appliances"
    if mats[0] in METAL or (p.get("MaterialType") or "").startswith("Metal"):
        return "metal"
    if any(k in p for k in ("container", "bed", "BedType", "IsTable", "IsTableTop", "chairN",
                            "chairS", "chairE", "chairW")) or \
            re.search(r"(?i)chair|couch|sofa|bed|table|desk|dresser|wardrobe|cabinet|shel|bench|"
                      r"stool|counter|drawer|bookcase|crate|locker|armchair|nightstand|toilet|"
                      r"sink|bath|shower", p.get("CustomName") or ""):
        return "furniture"
    return "other"


# The church, metal, white and wood window sets share one layout of 16 shapes, several
# of which are pieces of a wider window. Checked by eye, rendering the pieces side by
# side: on a west wall, listed north to south, these join into one window; on a north
# wall the same pieces run east to west. 5, 8 and 14 are middle pieces.
WIDE_SETS = ("fixtures_windows_church", "fixtures_windows_metal",
             "fixtures_windows_white", "fixtures_windows_wood")
WIDE = [("arched", [2, 1]), ("tall arched", [4, 3]), ("tall", [12, 11]),
        ("", [7, 6]), ("", [7, 5, 6]), ("grid", [15, 13]), ("grid", [15, 14, 13])]
HALVES = {1, 2, 3, 4, 6, 7, 11, 12, 13, 15}   # never a whole window on their own


def build(tiles=None):
    """-> list of objects:
    {id, name, set, cat, faces: {face: [[[x, y], sprite], ...]}, tiles, kg, mats,
     recipe, pickup, kind}"""
    tiles = tiles or load_tiles()
    vanilla = vanilla_entity_sprites()

    groups = collections.OrderedDict()
    for name in sorted((k for k, v in tiles.items() if "IsMoveAble" in v),
                       key=lambda n: (tileset(n), idx(n))):
        p = tiles[name]
        if p.get("MoveType") in ("Vegitation", "FloorTile"):
            continue
        if p.get("MoveType") == "Window" and "IsClosedState" not in p:
            continue  # the open, smashed and glassless states of the same window
        key = (tileset(name), p.get("GroupName") or "", p.get("CustomName") or "")
        if p.get("MoveType") == "Window" and p.get("WindowShape"):
            # the west and north pieces of one window share a shape; the group name
            # does not always match (fixtures_windows_wood_19 says "White Window")
            key = (tileset(name), "#" + p["WindowShape"], p.get("CustomName") or "")
        pos = tuple(int(x) for x in (p.get("SpriteGridPos") or "0,0").split(","))
        slot = (p.get("Facing") or "-", pos)
        insts = groups.setdefault(key, [])
        for inst in insts:
            if slot not in inst:
                inst[slot] = name
                break
        else:
            insts.append({slot: name})

    objects = []
    for (ts, _, _), insts in groups.items():
        for inst in insts:
            sprites = list(inst.values())
            if any(s in vanilla for s in sprites):
                continue
            first = dict(tiles[sprites[0]], _set=ts)
            cat = category_of(sprites[0], first)
            faces = collections.OrderedDict()
            for (face, pos), s in sorted(inst.items()):
                faces.setdefault(face, []).append([list(pos), s])
            tiles_n = max(len(v) for v in faces.values())
            kg = round(int(first.get("PickUpWeight") or 100) / 10 * tiles_n, 1)
            label = " ".join(x for x in (first.get("GroupName"), first.get("CustomName")) if x) or ts
            vkey = label
            if first.get("MoveType") == "Window":
                label += " (opens)" if "OpenTileOffset" in first else " (fixed pane)"
            objects.append({
                "id": f"{ts}_{min(idx(s) for s in sprites)}", "name": label, "vkey": vkey,
                "set": ts, "cat": cat, "faces": faces, "tiles": tiles_n, "kg": kg,
                "mats": materials(first), "pickup": [first.get("PickUpTool"),
                                                     int(first.get("PickUpLevel") or 0)],
                "recipe": price(first, kg, tiles_n, cat, label),
            })

    for ts in WIDE_SETS:
        objects = [o for o in objects if not (o["set"] == ts and idx(o["id"]) // 2 + 1 in HALVES)]
        for style, shapes in WIDE:
            w = [f"{ts}_{(n - 1) * 2}" for n in shapes]
            nn = [f"{ts}_{(n - 1) * 2 + 1}" for n in reversed(shapes)]
            first = dict(tiles[w[0]], _set=ts)
            n = len(shapes)
            kg = round(int(first.get("PickUpWeight") or 100) / 10 * n, 1)
            vkey = " ".join(x for x in (first.get("GroupName"), "Window") if x)
            objects.append({
                "id": f"{ts}_wide_" + "-".join(map(str, shapes)),
                "name": vkey + (", " + style if style else "") + f", {n} walls wide",
                "vkey": vkey, "wide": [style, n], "set": ts, "cat": "windows",
                "faces": {"W": [[[0, i], s] for i, s in enumerate(w)],
                          "N": [[[i, 0], s] for i, s in enumerate(nn)]},
                "tiles": n, "kg": kg, "mats": materials(first),
                "pickup": [first.get("PickUpTool"), int(first.get("PickUpLevel") or 0)],
                "recipe": price(first, kg, n, "windows"),
            })

    # window frames: wall tiles with a window opening; not moveables at all
    frames = collections.OrderedDict()
    for name in sorted((k for k, v in tiles.items()
                        if "wall" in v and ("WindowW" in v or "WindowN" in v)),
                       key=lambda n: (tileset(n), idx(n))):
        frames.setdefault(tileset(name), []).append(name)
    for ts, names in frames.items():
        ws = [n for n in names if "WindowW" in tiles[n]]
        ns = [n for n in names if "WindowN" in tiles[n]]
        for i in range(max(len(ws), len(ns))):
            sprites = [s for s in (ws[i] if i < len(ws) else None,
                                   ns[i] if i < len(ns) else None) if s]
            if any(s in vanilla for s in sprites):
                continue
            mt = (tiles[sprites[0]].get("MaterialType") or "Wood").split("_")[0]
            faces = collections.OrderedDict(
                ("W" if "WindowW" in tiles[s] else "N", [[[0, 0], s]]) for s in sprites)
            objects.append({
                "id": f"{ts}_{idx(sprites[0])}", "name": f"Window frame ({mt.lower()})",
                "frame": mt.lower(), "set": ts, "cat": "frames", "faces": faces,
                "tiles": 1, "kg": 30, "mats": ["Wood"], "pickup": [None, 0],
                "recipe": price({"PickUpLevel": "2"}, 30, 1, "frames"),
            })
    # plain walls: wall tiles with WallW/WallN and no opening, from the walls_* sets
    # (roofs, burnt and damaged sets left out). A west piece is paired with the north
    # piece right after it, which is how most wall sets lay them out; leftovers are
    # paired in order, as the frames are. The WallSE pillar within the next two tiles
    # becomes the entity's corner, as in vanilla's walls.
    WALL_MAT = {"Wood": "wood", "Brick": "masonry", "Cinderblock": "masonry",
                "Stone": "masonry", "Concrete": "masonry", "Ceramic": "masonry",
                "Metal": "metal", "Glass": "glass"}
    def plain_wall(k):
        v = tiles.get(k) or {}
        return "wall" in v and not any(x in v for x in ("WindowW", "WindowN", "DoorWallW", "DoorWallN"))
    candidates = sorted((k for k in tiles if k.startswith("walls_")
                         and not any(x in k for x in ("roofs", "burnt", "damaged"))
                         and plain_wall(k) and ("WallW" in tiles[k] or "WallN" in tiles[k])),
                        key=lambda n: (tileset(n), idx(n)))
    pairs, taken = [], set()
    for name in candidates:                          # a W piece and the N right after it
        north = f"{tileset(name)}_{idx(name) + 1}"
        if "WallW" in tiles[name] and north in candidates and "WallN" in tiles[north]:
            pairs.append([name, north])
            taken.update((name, north))
    by_set = collections.OrderedDict()
    for name in candidates:                          # the rest, in order, W with N
        if name not in taken:
            by_set.setdefault(tileset(name), []).append(name)
    for ts, names in by_set.items():
        ws = [n for n in names if "WallW" in tiles[n]]
        ns = [n for n in names if "WallN" in tiles[n]]
        for i in range(max(len(ws), len(ns))):
            pairs.append([x for x in (ws[i] if i < len(ws) else None,
                                      ns[i] if i < len(ns) else None) if x])
    for sprites in pairs:
        if any(s in vanilla for s in sprites):
            continue
        name = sprites[0]
        ts, i = tileset(name), idx(name)
        corner = next((f"{ts}_{j}" for j in (i + 2, i + 3)
                       if "WallSE" in (tiles.get(f"{ts}_{j}") or {})), None)
        mt = (tiles[name].get("MaterialType") or "Plaster").split("_")[0]
        faces = collections.OrderedDict(
            ("W" if "WallW" in tiles[s] else "N", [[[0, 0], s]]) for s in sprites)
        objects.append({
            "id": name, "name": f"Wall ({mt.lower()})", "wall": mt.lower(), "corner": corner,
            "set": ts, "cat": "walls", "faces": faces, "tiles": 1, "kg": 30,
            "mats": [mt], "pickup": [None, 0],
            "recipe": price({"_wallmat": WALL_MAT.get(mt, "wood")}, 30, 1, "walls"),
        })
    # door frames: DoorWallW/N wall tiles from the walls_* sets, a W piece with the N
    # piece right after it; a door is hung in them the same as in vanilla's frames
    for name in candidates_door(tiles):
        north = f"{tileset(name)}_{idx(name) + 1}"
        sprites = [name, north]
        if any(s in vanilla for s in sprites):
            continue
        mt = (tiles[name].get("Material") or "Wood")
        objects.append({
            "id": name, "name": "Door frame", "doorframe": True, "set": tileset(name),
            "cat": "walls", "wall": mt.lower(),
            "faces": collections.OrderedDict((("W", [[[0, 0], name]]), ("N", [[[0, 0], north]]))),
            "tiles": 1, "kg": 30, "mats": [mt], "pickup": [None, 0],
            "recipe": price({"_wallmat": WALL_MAT.get(mt, "wood")}, 30, 1, "walls"),
        })
    # The log walls draw their log ends at the north/west end only (walls_logs_4/5), so
    # corner wall - doorway - corner wall comes out lopsided. The end post walls_logs_12/13
    # is the same log ends on their own: built on the square past the south/east end of a
    # plain log wall, where vanilla's corner pillar goes, it gives that end the ends too.
    # (A wall-plus-post entity cannot reuse walls_logs_0/1: a sprite has one entity.)
    objects.append({
        "id": "walls_logs_12", "name": "Wall (logs), log ends", "set": "walls_logs",
        "cat": "walls", "wall": "wood", "endpost": True,
        "names": ("Log wall end", "Торец бревенчатой стены", "Торець зрубної стіни"),
        "faces": collections.OrderedDict((("W", [[[0, 0], "walls_logs_12"]]),
                                          ("N", [[[0, 0], "walls_logs_13"]]))),
        "tiles": 1, "kg": 10, "mats": ["Log"], "pickup": [None, 0],
        "recipe": dict(price({"_wallmat": "wood"}, 10, 1, "walls"),
                       inputs=[["Base.Plank", 1], ["Base.Nails", 2]], time=60, xp=20),
    })
    return objects


def candidates_door(tiles):
    """W door-frame pieces of the walls_* sets whose N piece is the next tile."""
    out = []
    for k in sorted((k for k in tiles if k.startswith("walls_")
                     and not any(x in k for x in ("roofs", "burnt", "damaged"))),
                    key=lambda n: (tileset(n), idx(n))):
        north = f"{tileset(k)}_{idx(k) + 1}"
        if "DoorWallW" in tiles[k] and "DoorWallN" in (tiles.get(north) or {}):
            out.append(k)
    return out


if __name__ == "__main__":
    import sys
    objs = build()
    json.dump({"objects": objs}, open(sys.argv[1] if len(sys.argv) > 1 else "catalog.json", "w"))
    print(len(objs), "objects;", collections.Counter(o["cat"] for o in objs))
