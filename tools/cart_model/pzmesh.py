def read_txt(path):
    L=[l.strip() for l in open(path) if l.strip()!=""]
    i=L.index("# Vertex Count:"); n=int(L[i+1]); i=L.index("# Vertex Buffer:")+1
    verts=[]
    for k in range(n):
        p=[float(x) for x in L[i].split(",")]; nm=[float(x) for x in L[i+1].split(",")]; uv=[float(x) for x in L[i+2].split(",")]
        verts.append((p,nm,uv)); i+=3
    j=L.index("# Number of Faces:"); f=int(L[j+1]); j=L.index("# Face Data:")+1
    faces=[tuple(int(x) for x in L[j+k].split(",")) for k in range(f)]
    return verts,faces
