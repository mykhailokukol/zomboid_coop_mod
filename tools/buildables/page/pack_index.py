import struct,sys,json,os
def rd(f,n): return f.read(n)
def ri(f): return struct.unpack('<i',f.read(4))[0]
def rs(f): n=ri(f); return f.read(n).decode('latin1')
def parse(path, outdir=None, keep=None):
    f=open(path,'rb'); assert f.read(4)==b'PZPK'; ver=ri(f); npages=ri(f)
    idx={}; pages=[]
    for p in range(npages):
        name=rs(f); n=ri(f); alpha=ri(f)
        for i in range(n):
            en=rs(f); vals=struct.unpack('<8i',f.read(32)); idx[en]=(p,)+vals
        if ver>=1:
            ln=ri(f); off=f.tell(); f.seek(ln,1)
        else:
            raise SystemExit('v0')
        pages.append((name,off,ln))
    return idx,pages
if __name__=='__main__':
    idx,pages=parse(sys.argv[1])
    print(len(idx),len(pages),pages[:3], list(idx.items())[:2])
    json.dump({'idx':idx,'pages':pages},open(sys.argv[2],'w'))
