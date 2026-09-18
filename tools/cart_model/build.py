"""
Builds the cart's model out of vanilla Project Zomboid files:

    media/models_X/COOPCart.glb     the utility trailer shell + two vehicle wheels
    media/textures/COOPCart_Tex.png trailer (left half), wheel, crate wood (right quarters)

    python tools/cart_model/build.py [path to ProjectZomboid/media]

Why it exists: the vanilla trailer mesh is only the shell - vehicles draw their wheels as
separate models with their own texture - and an item gets exactly one mesh and one texture.

What it does, and what was learned doing it:
  * vehicles/vehicle_utilitytrailer.fbx is read with the small binary FBX reader in fbx.py.
    Its node carries PreRotation -90 about X, which the game bakes in (it applies node
    transforms and ignores UnitScaleFactor - WorldItems/Wheel.fbx is only the right size
    with its 1/36 node scale applied), so the same rotation is baked here: (x,y,z)->(x,z,-y).
    Units stay the FBX's centimetres; the model scripts scale them.
  * models/Vehicles_Wheel.txt is the game's own text mesh format (pzmesh.py reads it). The
    output is NOT written in that format: an item model's mesh is loaded with the character
    skeleton as "skinned to", and ModelLoader.applyToMesh then writes into the static .txt
    mesh's (null) skinning data - a NullPointerException, no model. It is a .glb instead,
    which goes through Assimp like the FBX (see write_glb).
  * FBX UVs count V from the bottom, the text format's from the top (checked by drawing
    both UV layouts over the textures); both are brought to image-row order here.
  * The wheels sit centred in the fender boxes of the shell (x +-31..43, z 1..40) with their
    centres at the fenders' underside, at 100x the vehicle wheel mesh (15.8 cm radius).
  * The whole mesh is lifted so the bottom of the wheels is y = 0: a parked cart stands on
    the floor, and the pulled model's attachment offset is measured to the ground.
"""
import fbx, pzmesh, png, math, os, sys
M=(sys.argv[1] if len(sys.argv)>1 else os.environ.get("PZ_MEDIA","D:/Steam/steamapps/common/ProjectZomboid/media")).rstrip("/")+"/"
def trailer():
    r,_=fbx.read(M+"models_X/vehicles/vehicle_utilitytrailer.fbx")
    g=r.first("Objects").first("Geometry")
    V=g.first("Vertices").props[0]; pvi=g.first("PolygonVertexIndex").props[0]
    uvl=g.first("LayerElementUV"); UV=uvl.first("UV").props[0]; UI=uvl.first("UVIndex").props[0]
    N=g.first("LayerElementNormal").first("Normals").props[0]
    rot=lambda x,y,z:(x,z,-y)            # PreRotation -90 about X
    verts=[]; tris=[]; poly=[]
    for k,idx in enumerate(pvi):
        vi=idx if idx>=0 else ~idx
        p=rot(*V[3*vi:3*vi+3]); n=rot(*N[3*k:3*k+3]); u,v=UV[2*UI[k]],UV[2*UI[k]+1]
        verts.append([p,n,(u,1.0-v),"body"]); poly.append(len(verts)-1)
        if idx<0:
            for i in range(1,len(poly)-1): tris.append((poly[0],poly[i],poly[i+1]))
            poly=[]
    return verts,tris
def wheel():
    v,f=pzmesh.read_txt(M+"models/Vehicles_Wheel.txt")
    return [[tuple(p),tuple(n),tuple(uv),"wheel"] for p,n,uv in v], f
def render(verts,tris,axes,W=900,H=450,path="view.png",flipx=False):
    a,b=axes
    xs=[v[0][a] for v in verts]; ys=[v[0][b] for v in verts]
    x0,x1,y0,y1=min(xs),max(xs),min(ys),max(ys); s=min((W-20)/(x1-x0),(H-20)/(y1-y0))
    px=[[(255,255,255,255)]*W for _ in range(H)]
    def P(v):
        x=(v[0][a]-x0)*s+10; y=H-10-(v[0][b]-y0)*s
        return (W-x if flipx else x),y
    for t in tris:
        (ax,ay),(bx,by),(cx,cy)=(P(verts[i]) for i in t)
        col=(40,40,40,255) if verts[t[0]][3]=="wheel" else (150,160,200,255)
        mnx,mxx=int(max(0,min(ax,bx,cx))),int(min(W-1,max(ax,bx,cx))); mny,mxy=int(max(0,min(ay,by,cy))),int(min(H-1,max(ay,by,cy)))
        d=(bx-ax)*(cy-ay)-(by-ay)*(cx-ax)
        if abs(d)<1e-9: continue
        for y in range(mny,mxy+1):
            for x in range(mnx,mxx+1):
                w0=((bx-x)*(cy-y)-(by-y)*(cx-x))/d; w1=((cx-x)*(ay-y)-(cy-y)*(ax-x))/d
                if w0>=0 and w1>=0 and w0+w1<=1: px[y][x]=col
    # axis ticks every 10 units
    for gx in range(int(x0//10)*10,int(x1)+1,10):
        X=int((gx-x0)*s+10); X=W-X if flipx else X
        for y in range(H-8,H): 
            if 0<=X<W: px[y][X]=(255,0,0,255) if gx==0 else (0,0,0,255)
    for gy in range(int(y0//10)*10,int(y1)+1,10):
        Y=int(H-10-(gy-y0)*s)
        for x in range(0,8):
            if 0<=Y<H: px[Y][x]=(255,0,0,255) if gy==0 else (0,0,0,255)
    png.write(path,W,H,px); return (x0,x1,y0,y1)

WHEEL_SCALE = 100.0        # vanilla wheel mesh (radius 0.158) -> 15.8 cm
WHEEL_X = 37.1             # centre of the fender boxes (x 31..43.2)
WHEEL_Z = 20.8             # centre of the fender boxes (z 1.4..40.2)
WHEEL_Y = -12.3            # underside of the fender boxes

# The wooden part: the box - floor, walls, rim, the underside of the bed. Everything
# else keeps the trailer's own steel texture: the tongue and hitch (z < -15.2), the
# fenders (|x| >= 33.7), the rear light bar (z > 78.4) and the axle bracket and frame
# under the bed (below y -7.5). Worked out from the shell's coordinates: the walls run
# y -7.4..14 with their outer faces at |x| 32.0, the floor sits at -4.8, the rim at 14.
# (FBX space, before the lift.)
BOX_X = 32.1
BOX_Z = (-15.2, 78.4)
BOX_Y = -7.5
WOOD_CROP = (0.09, 0.91)            # CrateBasic without its frame boards, both axes

def is_wood(points):
    return all(abs(p[0]) <= BOX_X and BOX_Z[0] <= p[2] <= BOX_Z[1] and p[1] >= BOX_Y
               for p in points)

def wood_uv(p, n):
    """Box projection onto the crate planks, which run along the texture's v. Boards go
    along the cart's length on the floor and the side walls, across it on the end walls."""
    ax = max(range(3), key=lambda k: abs(n[k]))
    length = (p[2] - BOX_Z[0]) / (BOX_Z[1] - BOX_Z[0])
    width = (p[0] + BOX_X) / (2 * BOX_X)
    height = (p[1] - BOX_Y) / (14.0 - BOX_Y)
    if ax == 1:
        u, v = width, length
    elif ax == 0:
        u, v = height, length
    else:
        u, v = height, width
    clamp = lambda f: min(max(f, 0.0), 1.0)
    return clamp(u), clamp(v)

def cart():
    bv, bt = trailer()
    wv, wt = wheel()
    verts = [[p, n, (u * 0.5, v), k] for p, n, (u, v), k in bv]
    wood = 0
    for tri in bt:
        if is_wood([bv[i][0] for i in tri]):
            wood += 1
            for i in tri:
                u, v = wood_uv(bv[i][0], bv[i][1])
                verts[i][2] = (0.75 + 0.25 * (0.02 + 0.96 * u), 0.5 * (0.02 + 0.96 * v))
    print("wooden triangles: %d of %d" % (wood, len(bt)))
    tris = list(bt)
    for side in (1, -1):
        base = len(verts)
        for p, n, (u, v), k in wv:
            q = (p[0] * WHEEL_SCALE + side * WHEEL_X, p[1] * WHEEL_SCALE + WHEEL_Y, p[2] * WHEEL_SCALE + WHEEL_Z)
            verts.append([q, n, (0.5 + u * 0.25, v * 0.5), k])
        tris += [(a + base, b + base, c + base) for a, b, c in wt]
    ground = min(p[0][1] for p in verts)
    for vv in verts:
        p = vv[0]; vv[0] = (p[0], p[1] - ground, p[2])
    return verts, tris, ground

def atlas(path):
    T = M + "textures/Vehicles/"
    tw, th, tp = png.read(T + "vehicle_utilitytrailershell.png")
    ww, wh, wp = png.read(T + "vehicle_wheel.png")
    W, H = 512, 256
    px = [[(0, 0, 0, 255)] * W for _ in range(H)]
    for y in range(256):
        for x in range(256): px[y][x] = tp[y * th // 256][x * tw // 256]
    for y in range(128):
        for x in range(128):
            c = wp[y * wh // 128][x * ww // 128]
            px[y][256 + x] = c; px[128 + y][256 + x] = c
    # the wood, right quarter: vanilla's basic crate without its frame boards
    cw, ch, cp = png.read(M + "textures/WorldItems/CrateBasic.png")
    lo, hi = WOOD_CROP
    for y in range(128):
        for x in range(128):
            sx = int((lo + (hi - lo) * x / 128) * cw); sy = int((lo + (hi - lo) * y / 128) * ch)
            c = cp[sy][sx]
            px[y][384 + x] = c; px[128 + y][384 + x] = c
    png.write(path, W, H, px)

def write_txt(path, verts, tris, name):
    out = ["# Project Zomboid Mesh", "# File Version:", "1.00000000", "# Model Name:", name,
           "# Vertex Stride Element Count:", "3", "# Vertex Stride Size (in bytes):", "76",
           "# Vertex Stride Data:", "# (Int)    Offset", "# (String) Type",
           "0", "VertexArray", "12", "NormalArray", "24", "TextureCoordArray",
           "# Vertex Count:", str(len(verts)), "# Vertex Buffer:"]
    for p, n, uv, _ in verts:
        out.append("%.8f, %.8f, %.8f" % p)
        out.append("%.8f, %.8f, %.8f" % n)
        out.append("%.8f, %.8f" % uv)
    out += ["# Number of Faces:", str(len(tris)), "# Face Data:"]
    out += ["%d, %d, %d" % t for t in tris]
    open(path, "w", newline="\n").write("\n".join(out) + "\n")


def write_glb(path, verts, tris, double_sided_kinds=("wheel",)):
    """One-mesh binary glTF. The game loads .glb through Assimp exactly like .fbx
    (FileTask_LoadMesh.loadGLTF), so the same MAKE_LEFT_HANDED pass runs on both and the
    FBX-space positions baked in trailer() come out where the FBX put them.

    UVs are written image-row first (v counted from the top), glTF's own convention;
    Assimp's glTF importer flips them to the bottom-up V the FBX path produces.

    The wheel triangles come from the game's text format, which is already past the
    handedness flip, so after MAKE_LEFT_HANDED their winding could face inward. They are
    written both ways round rather than guessed."""
    import json, struct
    idx = []
    for a, b, c in tris:
        idx += [a, b, c]
        if verts[a][3] in double_sided_kinds:
            idx += [a, c, b]
    pos = b"".join(struct.pack("<3f", *v[0]) for v in verts)
    nrm = b"".join(struct.pack("<3f", *v[1]) for v in verts)
    uv = b"".join(struct.pack("<2f", *v[2]) for v in verts)
    ind = struct.pack("<%dI" % len(idx), *idx)
    views, blob = [], b""
    for data, target in ((pos, 34962), (nrm, 34962), (uv, 34962), (ind, 34963)):
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob += data
        blob += b"\0" * ((4 - len(blob) % 4) % 4)
    xs = [[v[0][i] for v in verts] for i in range(3)]
    n = len(verts)
    gltf = {
        "asset": {"version": "2.0", "generator": "CO-OP tools/cart_model/build.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "COOPCart", "mesh": 0}],
        "meshes": [{"name": "COOPCart", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "mode": 4}]}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3",
             "min": [min(a) for a in xs], "max": [max(a) for a in xs]},
            {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(blob), b"BIN\0") + blob
    open(path, "wb").write(out)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    media = os.path.normpath(os.path.join(here, "..", "..", "mods", "CO-OP", "42", "media"))
    verts, tris, ground = cart()
    write_glb(os.path.join(media, "models_X", "COOPCart.glb"), verts, tris)
    atlas(os.path.join(media, "textures", "COOPCart_Tex.png"))
    print("COOPCart: %d vertices, %d triangles, lifted %.1f cm" % (len(verts), len(tris), -ground))
