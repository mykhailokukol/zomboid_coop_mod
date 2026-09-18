import struct, zlib
def read(path):
    d=open(path,"rb").read(); assert d[:8]==b"\x89PNG\r\n\x1a\n"
    p=8; idat=b""; w=h=ct=bd=None; plte=None
    while p<len(d):
        n,t=struct.unpack(">I4s",d[p:p+8]); c=d[p+8:p+8+n]; p+=12+n
        if t==b"IHDR": w,h,bd,ct,_,_,il=struct.unpack(">IIBBBBB",c); assert bd==8 and il==0
        elif t==b"PLTE": plte=c
        elif t==b"IDAT": idat+=c
        elif t==b"IEND": break
    ch={0:1,2:3,3:1,4:2,6:4}[ct]; stride=w*ch; raw=zlib.decompress(idat)
    rows=[]; prev=bytearray(stride); i=0
    for y in range(h):
        f=raw[i]; line=bytearray(raw[i+1:i+1+stride]); i+=1+stride
        for x in range(stride):
            a=line[x-ch] if x>=ch else 0; b=prev[x]; c=prev[x-ch] if x>=ch else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+((a+b)>>1))&255
            elif f==4:
                pa,pb,pc=abs(b-c),abs(a-c),abs(a+b-2*c)
                pr=a if pa<=pb and pa<=pc else (b if pb<=pc else c); line[x]=(line[x]+pr)&255
        rows.append(line); prev=line
    px=[]
    for y in range(h):
        r=rows[y]; row=[]
        for x in range(w):
            if ct==0: g=r[x]; row.append((g,g,g,255))
            elif ct==2: row.append((r[3*x],r[3*x+1],r[3*x+2],255))
            elif ct==4: g=r[2*x]; row.append((g,g,g,r[2*x+1]))
            elif ct==6: row.append(tuple(r[4*x:4*x+4]))
            elif ct==3: k=r[x]; row.append((plte[3*k],plte[3*k+1],plte[3*k+2],255))
        px.append(row)
    return w,h,px
def write(path,w,h,px):
    raw=b"".join(b"\x00"+bytes(c for p in px[y] for c in p) for y in range(h))
    def chunk(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
    open(path,"wb").write(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(raw,9))+chunk(b"IEND",b""))
