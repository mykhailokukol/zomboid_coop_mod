"""Rebuilds the browse page the picks were made on (the "CO-OP Build Picker" artifact).

    python3 tools/buildables/page/make_page.py OUT_DIR

Steps, all writing into OUT_DIR:
  1. catalog.json   - catalog.build(), every candidate object
  2. pack2x.json    - the sprite index of Tiles2x.pack (pack_index.py)
  3. sheet<N>.webp  - one thumbnail per object, cut from Tiles2x.pack by thumbs.py.
                      That step needs Pillow, which this WSL has not got, so it runs
                      under the Windows Python 3.11 install that has it.
  4. site/build_picker.html + site/sheets/ - the page, ready to publish

A thumbnail composes all the tiles of an object's first facing at their isometric
offsets (a tile at grid x,y sits (x-y)*64, (x+y)*32 pixels from the first at 2x).
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import catalog  # noqa: E402

WIN_PYTHON = "/mnt/c/Users/mykha/AppData/Local/Programs/Python/Python311/python.exe"
PACK = catalog.GAME + "/texturepacks/Tiles2x.pack"


def main(out):
    os.makedirs(out, exist_ok=True)
    objects = catalog.build()
    json.dump({"objects": objects}, open(os.path.join(out, "catalog.json"), "w"))
    subprocess.check_call([sys.executable, os.path.join(HERE, "pack_index.py"), PACK,
                           os.path.join(out, "pack2x.json")])
    shutil.copy(os.path.join(HERE, "thumbs.py"), out)
    win_out = subprocess.check_output(["wslpath", "-w", out], text=True).strip()
    subprocess.check_call([WIN_PYTHON, "thumbs.py"], cwd=out)
    thumbs = json.load(open(os.path.join(out, "thumbs.json")))

    rows = [[o["id"], o["name"], o["set"], o["cat"], o["faces"], o["tiles"], o["kg"], o["mats"],
             o["recipe"]["skills"], o["recipe"]["tools"], o["recipe"]["inputs"],
             o["recipe"]["xp"], o["recipe"]["time"], thumbs.get(o["id"]), o["pickup"]]
            for o in objects]
    data = json.dumps(rows, separators=(",", ":")).replace("</", "<\\/")
    site = os.path.join(out, "site")
    os.makedirs(os.path.join(site, "sheets"), exist_ok=True)
    html = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
    open(os.path.join(site, "build_picker.html"), "w", encoding="utf-8").write(
        html.replace("__DATA__", data))
    for f in os.listdir(out):
        if f.startswith("sheet") and f.endswith(".webp"):
            shutil.copy(os.path.join(out, f), os.path.join(site, "sheets", f))
    print(len(objects), "objects ->", site, "(Windows path", win_out + ")")


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1]))
