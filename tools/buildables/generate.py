"""Writes the build recipes for the picked objects.

    python3 tools/buildables/generate.py

Reads picks.txt (one object id per line, as the browse page lists them) and writes:

  mods/CO-OP/42/media/scripts/entity_coop_buildables.txt      one entity per object
  mods/CO-OP/42/media/lua/shared/Translate/{EN,RU,UA}/Recipes.json   the names
  mods/CO-OP/42/media/lua/shared/Translate/{EN,RU,UA}/IG_UI.json     the categories

Only keys starting with COOPB_ / IGUI_CraftingCategories_COOP are touched in the
translation files, so the rest of each file is left as it was.

How an entry is built (see COOP_Build.lua for the Lua half):
- isProp = true. ISBuildIsoEntity:setInfo then places the tile through
  ISMoveableSpriteProps:placeMoveableInternal - the code that puts a picked-up
  moveable back down - instead of making an IsoThumpable. That is what turns a built
  oven into an IsoStove, a lamp into an IsoLightSwitch, a TV into an IsoTelevision, a
  window into an IsoWindow, and what gives a fridge its containers. Picking it up and
  scrapping it afterwards are therefore vanilla's too.
- OnIsValid = COOP_BuildIsValid asks the moveable rules where it may stand (on a table,
  against a wall, in a window frame), instead of the thumpable ones.
- Faces are keyed by the tile's own Facing; rows run along y, columns along x, the
  same layout as vanilla's piano and bookcases.
- Window frames are wall tiles, not moveables: ordinary thumpables, standalone like
  vanilla's brick window frame.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import catalog  # noqa: E402

MOD = os.path.join(HERE, "..", "..", "mods", "CO-OP", "42", "media")
SCRIPT = os.path.join(MOD, "scripts", "entity_coop_buildables.txt")
TRANSLATE = os.path.join(MOD, "lua", "shared", "Translate")
LANGS = ("EN", "RU", "UA")
GAME_TRANSLATE = catalog.GAME + "/lua/shared/Translate"

CATEGORY = {
    "windows": "COOPWindows", "frames": "COOPWindowFrames", "furniture": "COOPFurniture",
    "metal": "COOPMetal", "appliances": "COOPAppliances", "lighting": "COOPLighting",
    "plants": "COOPPlants", "other": "COOPDecor", "walls": "COOPWalls",
}
CATEGORY_NAME = {
    "COOPWindows": ("Windows", "Окна", "Вікна"),
    "COOPWindowFrames": ("Window Frames", "Оконные рамы", "Віконні рами"),
    "COOPFurniture": ("Furniture", "Мебель", "Меблі"),
    "COOPMetal": ("Metal", "Металл", "Метал"),
    "COOPAppliances": ("Appliances", "Техника", "Техніка"),
    "COOPLighting": ("Lighting", "Освещение", "Освітлення"),
    "COOPPlants": ("Plants", "Растения", "Рослини"),
    "COOPDecor": ("Decor", "Декор", "Декор"),
    "COOPWalls": ("Walls", "Стены", "Стіни"),
}
TAGS = {"Woodwork": "Carpentry", "MetalWelding": "Welding", "Masonry": "Masonry",
        "Glassmaking": "Carpentry", "Farming": "Outdoors", "Electricity": "Carpentry"}

TOOL_INPUT = {
    "Hammer": "item 1 tags[base:hammer] mode:keep flags[Prop1;MayDegradeVeryLight]",
    "Saw": "item 1 tags[base:saw] mode:keep flags[MayDegradeLight]",
    "Screwdriver": "item 1 tags[base:screwdriver] mode:keep flags[MayDegradeLight]",
    "Trowel": "item 1 tags[base:masonstrowel] mode:keep flags[Prop1;MayDegradeLight]",
    "WeldingMask": "item 1 tags[base:weldingmask] mode:keep",
}

WIDE_STYLE = {
    "": ("", "", ""), "arched": ("arched", "арочное", "аркове"),
    "tall": ("tall", "высокое", "високе"), "tall arched": ("tall arched", "высокое арочное", "високе аркове"),
    "grid": ("grid", "решётчатое", "ґратчасте"),
}
WIDE_WIDTH = ("{n} walls wide", "на {n} стены", "на {n} стіни")
WALL_MAT_NAME = {
    "wood": ("wood", "дерево", "дерево"), "plaster": ("plaster", "штукатурка", "штукатурка"),
    "brick": ("brick", "кирпич", "цегла"), "cinderblock": ("cinder block", "шлакоблок", "шлакоблок"),
    "stone": ("stone", "камень", "камінь"), "concrete": ("concrete", "бетон", "бетон"),
    "ceramic": ("tile", "плитка", "плитка"), "metal": ("metal", "металл", "метал"),
    "glass": ("glass", "стекло", "скло"),
    "logs": ("logs", "брёвна", "колоди"),
}
FRAME_NAME = {
    "wood": ("Window frame (wood)", "Оконная рама (дерево)", "Віконна рама (дерево)"),
    "glass": ("Window frame (shopfront)", "Оконная рама (витрина)", "Віконна рама (вітрина)"),
}


def entity_name(oid):
    return "COOPB_" + oid.replace("-", "_")


def load_json(path):
    if not os.path.exists(path):
        return {}
    return json.load(open(path, encoding="utf-8"))


def save_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        f.write("\n")


def names_for(o, moveables):
    """(EN, RU, UA). Vanilla's own moveable names, from Moveables.json, so a built
    object is called what the same object is called when you pick it up."""
    if "names" in o:
        return o["names"]
    if o["cat"] == "frames":
        return FRAME_NAME.get(o.get("frame"), FRAME_NAME["wood"])
    if o["cat"] == "walls":
        what = ("Door frame", "Дверная рама", "Дверна рама") if o.get("doorframe")             else ("Wall", "Стена", "Стіна")
        return tuple(f"{w} ({m})" for w, m in zip(what,
                                                  WALL_MAT_NAME.get("logs" if o["set"] == "walls_logs" else o["wall"],
                                                                WALL_MAT_NAME["wood"])))
    key = o.get("vkey", o["name"]).replace(" ", "_")
    out = []
    for i, lang in enumerate(LANGS):
        base = moveables[lang].get(key) or moveables["EN"].get(key) or o.get("vkey", o["name"])
        if "wide" in o:
            style, n = o["wide"]
            extra = ", ".join(x for x in (WIDE_STYLE[style][i], WIDE_WIDTH[i].format(n=n)) if x)
            base = f"{base}, {extra}"
        out.append(base.replace(" 's", "'s"))   # vanilla's "Greene 's Grocery"
    return tuple(out)


def faces_block(o):
    lines = []
    for face, cells in o["faces"].items():
        face = "S" if face == "-" else face
        width = max(p[0] for p, _ in cells) + 1
        height = max(p[1] for p, _ in cells) + 1
        grid = {(p[0], p[1]): s for p, s in cells}
        if len(grid) != width * height:
            raise SystemExit(f"{o['id']}: face {face} has holes in its grid, cannot write rows")
        lines.append(f"            face {face}")
        lines.append("            {")
        lines.append("                layer")
        lines.append("                {")
        for y in range(height):
            lines.append("                    row = " + " ".join(grid[(x, y)] for x in range(width)) + ",")
        lines.append("                }")
        lines.append("            }")
    return lines


def entity(o):
    r = o["recipe"]
    name = entity_name(o["id"])
    kg = r["kg"]
    inputs = []
    for tool in r["tools"]:
        if tool == "BlowTorch":
            inputs.append(f"item {max(1, min(10, -(-int(kg) // 10)))} [Base.BlowTorch] flags[DontRecordInput]")
        elif tool == "WeldingRods":
            inputs.append(f"item {max(1, min(6, -(-int(kg) // 15)))} [Base.WeldingRods] flags[DontRecordInput]")
        else:
            inputs.append(TOOL_INPUT[tool])
    inputs += [f"item {n} [{item}]" for item, n in r["inputs"]]

    skills = ";".join(f"{s}:{l}" for s, l in r["skills"])
    xp_skill = r["skills"][0][0]
    tags = TAGS.get(xp_skill, "Carpentry")
    is_frame = o["cat"] in ("frames", "walls")   # wall tiles: thumpables, not props

    # No UiConfig on purpose: the Build window then draws the first face's sprite as the
    # recipe icon ("missing UiConfigScript - falling back to SpriteConfigScript first
    # world object face", as vanilla's Piano logs). An xuiSkin Icon naming a tile sprite
    # is not found - every one logged "Could not find icon".
    out = [f"    entity {name}", "    {",
           "        component SpriteConfig", "        {"]
    if is_frame:
        # standalone, like vanilla's brick window frame: a wall piece built on any
        # edge. (previousStage = WoodenWallFrame would demand a built wall frame first.)
        out += ["            skillBaseHealth = 20,",
                "            health = 450,"]
        if o.get("doorframe"):
            # as vanilla's door frames: zombies go for the door, not the frame
            out.append("            isThumpable = false,")
    else:
        out += ["            isProp = true,",
                "            OnIsValid = COOP_BuildIsValid,"]
        if o["cat"] == "windows":
            out.append("            needWindowFrame = true,")
    out += faces_block(o)
    if o.get("corner"):
        out.append(f"            corner = {o['corner']},")
    out += ["        }",
            "        component CraftRecipe", "        {",
            f"            timedAction = {r['action']},",
            f"            time = {r['time']},",
            f"            category = {CATEGORY[o['cat']]},",
            f"            Tags = {tags},",
            f"            SkillRequired = {skills},",
            f"            xpAward = {xp_skill}:{r['xp']},",
            "            OnAddToMenu = COOP_BuildInMenu,"]
    if o["cat"] == "windows":
        out.append("            Tooltip = Tooltip_COOPB_Window,")
    if o.get("endpost"):
        out.append("            Tooltip = Tooltip_COOPB_LogWallEnd,")
    out += ["            inputs", "            {"]
    out += [f"                {line}," for line in inputs]
    out += ["            }", "        }", "    }", ""]
    return out, name


def main():
    picks = [line.split()[0] for line in open(os.path.join(HERE, "picks.txt"), encoding="utf-8")
             if line.strip() and not line.startswith("#")]
    objects = {o["id"]: o for o in catalog.build()}
    missing = [p for p in picks if p not in objects]
    if missing:
        raise SystemExit("not in the catalog: " + ", ".join(missing))

    used = {}
    for p in picks:
        for cells in objects[p]["faces"].values():
            for _, s in cells:
                if s in used:
                    raise SystemExit(f"{s} is in both {used[s]} and {p}: a sprite may belong to one entity")
                used[s] = p

    moveables = {lang: load_json(f"{GAME_TRANSLATE}/{lang}/Moveables.json") for lang in LANGS}

    body, names, seen = [], {lang: {} for lang in LANGS}, {}
    for p in picks:
        o = objects[p]
        lines, name = entity(o)
        body += lines
        triple = names_for(o, moveables)
        # many picks share a name (twelve Mannequins, four Grey Lamps): number them
        seen[triple[0]] = seen.get(triple[0], 0) + 1
        for i, lang in enumerate(LANGS):
            names[lang][name] = triple[i]
    counter = {}
    for p in picks:
        name = entity_name(p)
        en = names["EN"][name]
        if seen[en] > 1:
            counter[en] = counter.get(en, 0) + 1
            for lang in LANGS:
                names[lang][name] = f"{names[lang][name]} {counter[en]}"

    header = [
        "module Base",
        "{",
        "    /* GENERATED by tools/buildables/generate.py from tools/buildables/picks.txt -",
        "       edit those, not this file. Vanilla objects the Build menu cannot make,",
        "       placed through the moveables code (isProp) so each one is the real object.",
        "       COOP_Build.lua holds the two Lua hooks every entry names. */",
        "",
    ]
    footer = ["}", ""]
    with open(SCRIPT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(header + body + footer))

    for i, lang in enumerate(LANGS):
        path = os.path.join(TRANSLATE, lang, "Recipes.json")
        data = {k: v for k, v in load_json(path).items() if not k.startswith("COOPB_")}
        data.update(names[lang])
        save_json(path, data)

        path = os.path.join(TRANSLATE, lang, "IG_UI.json")
        data = {k: v for k, v in load_json(path).items()
                if not k.startswith("IGUI_CraftingCategories_COOP")}
        for cat in sorted({CATEGORY[objects[p]["cat"]] for p in picks}):
            data[f"IGUI_CraftingCategories_{cat}"] = "[mod] " + CATEGORY_NAME[cat][i]
        save_json(path, data)

    by_cat = {}
    for p in picks:
        by_cat[objects[p]["cat"]] = by_cat.get(objects[p]["cat"], 0) + 1
    print(f"{len(picks)} entities -> {os.path.relpath(SCRIPT)}  {by_cat}")


if __name__ == "__main__":
    main()
