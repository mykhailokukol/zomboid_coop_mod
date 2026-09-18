import struct, zlib
class Node:
    def __init__(s, name, props, children): s.name, s.props, s.children = name, props, children
    def find(s, name): return [c for c in s.children if c.name == name]
    def first(s, name):
        r = s.find(name); return r[0] if r else None
def read(path):
    d = open(path, "rb").read()
    assert d[:20] == b"Kaydara FBX Binary  ", "not binary fbx"
    ver = struct.unpack_from("<I", d, 23)[0]
    wide = ver >= 7500
    pos = 27
    def prop(p):
        t = chr(d[p]); p += 1
        if t == "Y": return struct.unpack_from("<h", d, p)[0], p + 2
        if t == "C": return bool(d[p]), p + 1
        if t == "I": return struct.unpack_from("<i", d, p)[0], p + 4
        if t == "F": return struct.unpack_from("<f", d, p)[0], p + 4
        if t == "D": return struct.unpack_from("<d", d, p)[0], p + 8
        if t == "L": return struct.unpack_from("<q", d, p)[0], p + 8
        if t in "SR":
            n = struct.unpack_from("<I", d, p)[0]; p += 4; v = d[p:p+n]
            return (v.decode("utf-8", "replace") if t == "S" else v), p + n
        if t in "fdlib":
            n, enc, clen = struct.unpack_from("<III", d, p); p += 12
            raw = d[p:p+clen]; p += clen
            if enc == 1: raw = zlib.decompress(raw)
            fmt = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "B"}[t]
            return list(struct.unpack("<%d%s" % (n, fmt), raw)), p
        raise ValueError("prop type " + t)
    def node(p):
        if wide:
            end, nprops, plen = struct.unpack_from("<QQQ", d, p); p += 24
        else:
            end, nprops, plen = struct.unpack_from("<III", d, p); p += 12
        nlen = d[p]; p += 1
        name = d[p:p+nlen].decode(); p += nlen
        if end == 0: return None, p
        props = []
        for _ in range(nprops):
            v, p = prop(p); props.append(v)
        children = []
        null = 25 if wide else 13
        while p < end - null or (p < end and end - p > null):
            c, p = node(p)
            if c is None: break
            children.append(c)
        return Node(name, props, children), end
    root = []
    while pos < len(d) - 200:
        n, pos = node(pos)
        if n is None: break
        root.append(n)
    return Node("root", [], root), ver
def props70(n):
    out = {}
    p = n.first("Properties70")
    if p:
        for c in p.find("P"): out[c.props[0]] = c.props[4:]
    return out
