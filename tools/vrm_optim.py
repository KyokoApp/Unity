#!/usr/bin/env python3
"""
vrm_optim.py -- Optimasi VRM tanpa mengubah tampilan model.

Transformasi yang dilakukan semuanya LOSSLESS secara visual:
  1. Buang morph target yang tidak dirujuk VRM blendShapeMaster
     (118 -> 18 per primitive; sisanya tidak pernah diaktifkan apa pun)
  2. Remap vertex per-primitive: tiap primitive hanya mendeklarasikan verteks
     yang benar-benar dipakai indeksnya (+ morph target ikut di-remap agar tetap selaras)
  3. Ganti tekstur yang isinya 1 warna datar / sepenuhnya transparan dengan 4x4
  4. Buang accessor/bufferView yatim + dedup berdasarkan isi, pack ulang BIN rapat

TIDAK disentuh: jumlah segitiga, material, tekstur detail, tulang, spring bone,
               blendshape preset, hierarki node, VRM meta/lisensi.
"""
import struct, json, array, io, sys, os, hashlib, collections
import numpy as np
from PIL import Image

TS  = {5120:1, 5121:1, 5122:2, 5123:2, 5125:4, 5126:4}
CP  = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4, 'MAT4':16}
FMT = {5120:'b', 5121:'B', 5122:'h', 5123:'H', 5125:'I', 5126:'f'}
CT  = {'b':5120,'B':5121,'h':5122,'H':5123,'I':5125,'f':5126,'i':5120,'L':5125}

# ------------------------------------------------------------------ baca
def read_glb(path):
    data = open(path,'rb').read()
    magic, ver, total = struct.unpack('<4sII', data[:12])
    assert magic == b'glTF', 'bukan glTF/GLB/VRM'
    off, js, BIN = 12, None, None
    while off < total:
        clen, ctype = struct.unpack('<I4s', data[off:off+8])
        s = off+8; off = s+clen
        if   ctype == b'JSON':    js  = json.loads(data[s:s+clen])
        elif ctype == b'BIN\x00': BIN = bytearray(data[s:s+clen])
    assert js and BIN is not None
    return js, BIN, data

def acc_array(js, BIN, ai):
    a = js['accessors'][ai]
    assert 'bufferView' in a, f'accessor {ai} tanpa bufferView'
    assert not a.get('byteStride'), 'byteStride tidak didukung'
    b  = js['bufferViews'][a['bufferView']]
    st = b.get('byteOffset',0) + a.get('byteOffset',0)
    n  = a['count']*CP[a['type']]
    arr = array.array(FMT[a['componentType']])
    arr.frombytes(bytes(BIN[st:st+n*arr.itemsize]))
    return arr

def _remap_idx(ia, lut, pool):
    """indeks lama -> indeks baru, vektorisasi"""
    NP = {'B':np.uint8,'H':np.uint16,'I':np.uint32}
    lut_arr = np.zeros(pool, dtype=np.int64)
    for o, n in lut.items(): lut_arr[o] = n
    out = lut_arr[np.asarray(ia.tolist(), dtype=np.int64)].astype(NP[ia.typecode], copy=False)
    r = array.array(ia.typecode); r.frombytes(out.tobytes()); return r


def _select(src_arr, uniq, stride):
    """ambil baris-baris `uniq` dari array ber-stride, pakai numpy (cepat)"""
    npa = np.asarray(src_arr)
    out = npa.reshape(-1, stride)[np.asarray(uniq, dtype=np.int64)].ravel()
    r = array.array(src_arr.typecode)
    r.frombytes(out.astype(npa.dtype, copy=False).tobytes())
    return r

def raw_accessor(js, BIN, ai):
    """byte mentah sebuah accessor + metadata"""
    a = js['accessors'][ai]
    b = js['bufferViews'][a['bufferView']]
    st = b.get('byteOffset',0) + a.get('byteOffset',0)
    n  = a['count']*CP[a['type']]*TS[a['componentType']]
    return bytes(BIN[st:st+n])

# ------------------------------------------------------------------ rakit
class Packer:
    def __init__(self):
        self.BIN = bytearray()
        self.bvs = []
        self.accs = []
        self.cache = {}          # hash(isi,target,align) -> (bv_idx)
        self.acc_cache = {}      # hash -> acc_idx

    def add_bv(self, payload, target=None, align=4):
        key = (hashlib.sha1(payload).digest(), target, align)
        if key in self.cache: return self.cache[key]
        while len(self.BIN) % align: self.BIN.append(0)
        off = len(self.BIN); self.BIN.extend(payload)
        self.bvs.append({'buffer':0,'byteOffset':off,'byteLength':len(payload),
                         **({'target':target} if target else {})})
        self.cache[key] = len(self.bvs)-1
        return len(self.bvs)-1

    def add_acc(self, payload, atype, ctype, count, tmin=None, tmax=None, target=None):
        key = (hashlib.sha1(payload).digest(), atype, ctype, count, target,
               json.dumps(tmin), json.dumps(tmax))
        if key in self.acc_cache: return self.acc_cache[key]
        align = max(4, TS[ctype])
        bvi = self.add_bv(payload, target, align)
        a = {'bufferView':bvi,'componentType':ctype,'count':count,'type':atype,'byteOffset':0}
        if tmin is not None: a['min']=tmin
        if tmax is not None: a['max']=tmax
        self.accs.append(a)
        self.acc_cache[key] = len(self.accs)-1
        return len(self.accs)-1

    def clone(self, js, BIN, old_ai):
        o = js['accessors'][old_ai]
        tgt = js['bufferViews'][o['bufferView']].get('target')
        return self.add_acc(raw_accessor(js,BIN,old_ai), o['type'], o['componentType'],
                            o['count'], o.get('min'), o.get('max'), tgt)

def write_glb(path, js, BIN):
    js['buffers'] = [{'byteLength': len(BIN)}]
    txt = json.dumps(js, separators=(',',':')).encode()
    while len(txt) % 4: txt += b' '
    while len(BIN) % 4: BIN.append(0)
    out = bytearray(struct.pack('<4sII', b'glTF', 2, 12+8+len(txt)+8+len(BIN)))
    out += struct.pack('<I4s', len(txt), b'JSON') + txt
    out += struct.pack('<I4s', len(BIN), b'BIN\x00') + bytes(BIN)
    open(path,'wb').write(bytes(out))

# ================================================================== main
def optimise(src, dst):
    js, BIN, raw = read_glb(src)
    vrm = js['extensions']['VRM']
    log = []
    n_acc0, n_bv0 = len(js['accessors']), len(js['bufferViews'])

    # --- 1. morph target yang dirujuk --------------------------------
    used = collections.defaultdict(set)
    for g in vrm['blendShapeMaster']['blendShapeGroups']:
        for b in g.get('binds', []):
            used[b['mesh']].add(b['index'])

    before_mt = sum(len(p.get('targets',[])) for m in js['meshes'] for p in m['primitives'])
    keep_map = {}
    for mi, m in enumerate(js['meshes']):
        n_all = max((len(p.get('targets',[])) for p in m['primitives']), default=0)
        if n_all:
            keep_map[mi] = sorted(used.get(mi, set()))
    for g in vrm['blendShapeMaster']['blendShapeGroups']:
        for b in g.get('binds', []):
            b['index'] = keep_map[b['mesh']].index(b['index'])

    # --- 3. tekstur datar --------------------------------------------
    flat = []
    new_img_bytes = {}
    for i, im in enumerate(js['images']):
        b = js['bufferViews'][im['bufferView']]
        blob = bytes(BIN[b.get('byteOffset',0):][:b['byteLength']])
        try: p = Image.open(io.BytesIO(blob)).convert('RGBA')
        except Exception: continue
        if max(p.size) <= 8: continue
        u = np.unique(np.asarray(p).reshape(-1,4), axis=0)
        repl = None
        if len(u) == 1:
            repl = (tuple(int(x) for x in u[0]), f'satu warna {u[0].tolist()}')
        elif u[:,3].max() == 0:
            repl = ((0,0,0,0), 'sepenuhnya transparan (alpha=0)')
        if repl:
            buf = io.BytesIO(); Image.new('RGBA',(4,4),repl[0]).save(buf,'PNG')
            new_img_bytes[i] = buf.getvalue()
            flat.append((im.get('name'), p.size, repl[1], b['byteLength']))

    # --- 2 + 4. rakit ulang ------------------------------------------
    P = Packer()

    # images
    imgs = []
    for i, im in enumerate(js['images']):
        b = js['bufferViews'][im['bufferView']]
        payload = new_img_bytes.get(i) or bytes(BIN[b.get('byteOffset',0):][:b['byteLength']])
        imgs.append({'bufferView': P.add_bv(payload, None, 4),
                     'mimeType': 'image/png' if i in new_img_bytes else im['mimeType'],
                     **({'name':im['name']} if im.get('name') else {})})

    # meshes
    verts_before = verts_after = 0
    meshes = []
    for mi, m in enumerate(js['meshes']):
        keep = keep_map.get(mi, [])
        prims = []
        for pi, p in enumerate(m['primitives']):
            attrs = p['attributes']
            pos_ai = attrs['POSITION']
            pool   = js['accessors'][pos_ai]['count']
            verts_before += pool

            ia  = acc_array(js, BIN, p['indices'])
            tgt = p.get('targets', [])

            if len(m['primitives']) > 1 and not tgt:
                # partisi bersih -> remap penuh
                uniq = sorted(set(ia.tolist())); lut = {o:i for i,o in enumerate(uniq)}
                na = {}
                un = np.asarray(uniq, dtype=np.int64)
                for k, ai in attrs.items():
                    sarr = acc_array(js, BIN, ai); st = CP[js['accessors'][ai]['type']]
                    sel = _select(sarr, uniq, st)
                    mn = mx = None
                    if k == 'POSITION':
                        npa = np.asarray(sel, dtype=np.float32).reshape(-1,3)
                        mn, mx = npa.min(0).tolist(), npa.max(0).tolist()
                    na[k] = P.add_acc(sel.tobytes(), js['accessors'][ai]['type'],
                                      js['accessors'][ai]['componentType'], len(sel)//st, mn, mx, 34962)
                nia = _remap_idx(ia, lut, pool)
                oa = js['accessors'][p['indices']]
                idx = P.add_acc(nia.tobytes(), 'SCALAR', CT[ia.typecode], len(nia),
                                (min(nia) if 'min' in oa else None),
                                (max(nia) if 'max' in oa else None), 34963)
                verts_after += len(uniq)
                pr = {'attributes':na,'indices':idx,'material':p['material'],'mode':p.get('mode',4)}

            elif len(m['primitives']) > 1 and tgt:
                # ada morph target: remap vertex DAN delta-nya secara bersamaan
                uniq = sorted(set(ia.tolist())); lut = {o:i for i,o in enumerate(uniq)}
                na = {}
                for k, ai in attrs.items():
                    sarr = acc_array(js, BIN, ai); st = CP[js['accessors'][ai]['type']]
                    sel = _select(sarr, uniq, st)
                    mn = mx = None
                    if k == 'POSITION':
                        npa = np.asarray(sel, dtype=np.float32).reshape(-1,3)
                        mn, mx = npa.min(0).tolist(), npa.max(0).tolist()
                    na[k] = P.add_acc(sel.tobytes(), js['accessors'][ai]['type'],
                                      js['accessors'][ai]['componentType'], len(sel)//st, mn, mx, 34962)
                newt = []
                for oi in keep:
                    t = tgt[oi]; nt = {}
                    for k, ai in t.items():
                        if k not in attrs:            # delta utk atribut yang tidak ada -> lewati
                            continue
                        sarr = acc_array(js, BIN, ai); st = CP[js['accessors'][ai]['type']]
                        sel = _select(sarr, uniq, st)
                        nt[k] = P.add_acc(sel.tobytes(), js['accessors'][ai]['type'],
                                          js['accessors'][ai]['componentType'], len(sel)//st,
                                          None, None, 34962)
                    if t.get('name'): nt['name'] = t['name']
                    newt.append(nt)
                nia = _remap_idx(ia, lut, pool)
                oa = js['accessors'][p['indices']]
                idx = P.add_acc(nia.tobytes(), 'SCALAR', CT[ia.typecode], len(nia),
                                (min(nia) if 'min' in oa else None),
                                (max(nia) if 'max' in oa else None), 34963)
                verts_after += len(uniq)
                pr = {'attributes':na,'indices':idx,'material':p['material'],'mode':p.get('mode',4),
                      'targets':newt}

            else:
                na = {k: P.clone(js, BIN, ai) for k, ai in attrs.items()}
                idx = P.clone(js, BIN, p['indices'])
                pr = {'attributes':na,'indices':idx,'material':p['material'],'mode':p.get('mode',4)}
                if tgt:
                    pr['targets'] = [ {k: P.clone(js,BIN,ai) for k,ai in tgt[oi].items() if k!='name'}
                                      | ({'name':tgt[oi]['name']} if tgt[oi].get('name') else {})
                                      for oi in keep ]
                verts_after += pool

            if p.get('extras'): pr['extras'] = p['extras']
            prims.append(pr)
        nm = {'primitives':prims}
        if m.get('name'): nm['name'] = m['name']
        if m.get('weights') and keep: nm['weights'] = [m['weights'][o] for o in keep]
        elif m.get('weights'): nm['weights'] = m['weights']
        if m.get('extras'): nm['extras'] = m['extras']
        meshes.append(nm)

    skins = []
    for s in js.get('skins', []):
        ns = {'joints': s['joints']}
        if 'inverseBindMatrices' in s: ns['inverseBindMatrices'] = P.clone(js, BIN, s['inverseBindMatrices'])
        if s.get('skeleton') is not None: ns['skeleton'] = s['skeleton']
        if s.get('name'): ns['name'] = s['name']
        skins.append(ns)

    after_mt = sum(len(p.get('targets',[])) for m in meshes for p in m['primitives'])
    js['images'], js['meshes'], js['skins'] = imgs, meshes, skins
    js['accessors'], js['bufferViews'] = P.accs, P.bvs

    log.append(('morph target',      f'{before_mt:,} -> {after_mt:,}  (buang {before_mt-after_mt:,} yang tidak pernah dipakai)'))
    log.append(('verteks impor Unity', f'{verts_before:,} -> {verts_after:,}  ({verts_before/max(verts_after,1):.1f}x lebih ringan)'))
    log.append(('tekstur datar',     f'{len(flat)} diganti 4x4'))
    log.append(('accessor',          f'{n_acc0} -> {len(P.accs)}'))
    log.append(('bufferView',        f'{n_bv0} -> {len(P.bvs)}'))
    log.append(('ukuran file',       f'{len(raw)/1024/1024:.2f} MB -> '))
    write_glb(dst, js, P.BIN)
    sz = os.path.getsize(dst)/1024/1024
    log[-1] = ('ukuran file', f'{len(raw)/1024/1024:.2f} MB -> {sz:.2f} MB  (hemat {(1-sz/(len(raw)/1024/1024))*100:.0f}%)')
    return log, flat

# ================================================================== verifikasi
def _pos_set(js, BIN, meshname, pi):
    m = [x for x in js['meshes'] if x['name']==meshname][0]
    p = m['primitives'][pi]
    arr = acc_array(js, BIN, p['attributes']['POSITION'])
    ia  = acc_array(js, BIN, p['indices'])
    return frozenset(arr[o*3:(o+1)*3].tobytes() for o in set(ia.tolist()))

def verify(src, dst, flat):
    jsA, BINa, _ = read_glb(src); jsB, BINb, _ = read_glb(dst)
    ok = True
    def chk(c, msg):
        nonlocal ok
        print(('   [OK]    ' if c else '   [GAGAL] ') + msg)
        if not c: ok = False
    print('\n=== VERIFIKASI LOSSLESS ===')

    def tris(js):
        d = {}
        for m in js['meshes']:
            for p in m['primitives']:
                d[(m['name'], p['material'])] = js['accessors'][p['indices']]['count']//3
        return d
    tA, tB = tris(jsA), tris(jsB)
    chk(tA==tB, f'segitiga per material identik: {sum(tA.values()):,} segitiga / {len(tA)} material-slot')

    bad = sum(1 for m in jsA['meshes'] for pi in range(len(m['primitives']))
              if _pos_set(jsA,BINa,m['name'],pi) != _pos_set(jsB,BINb,m['name'],pi))
    tot_p = sum(len(m['primitives']) for m in jsA['meshes'])
    chk(bad==0, f'himpunan posisi verteks identik di {tot_p-bad}/{tot_p} primitive')

    # urutan segitiga juga harus sama (bukan cuma himpunan verteks)
    def trilist(js, BIN, mn, pi):
        m=[x for x in js['meshes'] if x['name']==mn][0]; p=m['primitives'][pi]
        pos=np.asarray(acc_array(js,BIN,p['attributes']['POSITION']),dtype=np.float32).reshape(-1,3)
        ia=np.asarray(acc_array(js,BIN,p['indices']))
        return pos[ia].tobytes()
    bad2 = sum(1 for m in jsA['meshes'] for pi in range(len(m['primitives']))
               if trilist(jsA,BINa,m['name'],pi) != trilist(jsB,BINb,m['name'],pi))
    chk(bad2==0, f'urutan & indeks segitiga identik di {tot_p-bad2}/{tot_p} primitive (geometri bit-sama)')

    chk([n['name'] for n in jsA['nodes']]==[n['name'] for n in jsB['nodes']],
        f'{len(jsA["nodes"])} node/tulang: nama & urutan identik')
    chk(all(a['joints']==b['joints'] for a,b in zip(jsA['skins'],jsB['skins'])) and
        len(jsA['skins'])==len(jsB['skins']), f'{len(jsA["skins"])} skin, joints identik')
    chk([m['name'] for m in jsA['materials']]==[m['name'] for m in jsB['materials']],
        f'{len(jsA["materials"])} material identik')
    chk(jsA['materials'][:0] or all(
        {k:v for k,v in a.items() if k!='name'}=={k:v for k,v in b.items() if k!='name'}
        for a,b in zip(jsA['materials'],jsB['materials'])), 'parameter material (warna/alpha/doubleSided) identik')

    va, vb = jsA['extensions']['VRM'], jsB['extensions']['VRM']
    chk(va['meta']==vb['meta'], 'VRM meta / lisensi tidak berubah')
    chk([b['bone'] for b in va['humanoid']['humanBones']]==[b['bone'] for b in vb['humanoid']['humanBones']],
        f'{len(va["humanoid"]["humanBones"])} humanoid bone identik')
    sa=sum(len(g['bones']) for g in va['secondaryAnimation']['boneGroups'])
    sb=sum(len(g['bones']) for g in vb['secondaryAnimation']['boneGroups'])
    chk(sa==sb, f'{sa} spring bone identik')
    pa=[g.get('presetName') for g in va['blendShapeMaster']['blendShapeGroups']]
    pb=[g.get('presetName') for g in vb['blendShapeMaster']['blendShapeGroups']]
    chk(pa==pb, f'blendshape preset identik ({len(pa)}): ' + ', '.join(x for x in pa if x))

    # Morph target: cek delta tetap MELEKAT pada verteks yang benar.
    # Urutan vertex berubah karena remap, jadi pembandingnya adalah urutan segitiga:
    # untuk tiap sudut segitiga -> (posisi dasar, delta morph). Harus identik.
    keep = collections.defaultdict(set)
    for g in va['blendShapeMaster']['blendShapeGroups']:
        for b in g.get('binds',[]): keep[b['mesh']].add(b['index'])
    diff = ncmp = 0
    for mi, idxs in keep.items():
        mA, mB = jsA['meshes'][mi], jsB['meshes'][mi]
        k = sorted(idxs)
        for pi in range(len(mA['primitives'])):
            pa, pb = mA['primitives'][pi], mB['primitives'][pi]
            baseA = acc_array(jsA,BINa,pa['attributes']['POSITION'])
            baseB = acc_array(jsB,BINb,pb['attributes']['POSITION'])
            idxA  = acc_array(jsA,BINa,pa['indices']).tolist()
            idxB  = acc_array(jsB,BINb,pb['indices']).tolist()
            if len(idxA) != len(idxB): diff += 1; continue
            for newi, oldi in enumerate(k):
                for key in ('POSITION','NORMAL'):
                    ta = pa['targets'][oldi].get(key); tb = pb['targets'][newi].get(key)
                    if (ta is None) != (tb is None): diff += 1; continue
                    if ta is None: continue
                    dA = acc_array(jsA,BINa,ta); dB = acc_array(jsB,BINb,tb)
                    st = CP[jsA['accessors'][ta]['type']]
                    nA = np.asarray(dA).reshape(-1, st)[np.asarray(idxA)]
                    nB = np.asarray(dB).reshape(-1, st)[np.asarray(idxB)]
                    pA = np.asarray(baseA).reshape(-1,3)[np.asarray(idxA)]
                    pB = np.asarray(baseB).reshape(-1,3)[np.asarray(idxB)]
                    ncmp += len(idxA)
                    if not (np.array_equal(nA, nB) and np.array_equal(pA, pB)):
                        diff += 1
    chk(diff==0, f'delta morph target tetap melekat di verteks yang benar ({ncmp:,} pasang dibandingkan)')

    flat_names = {x[0] for x in flat}
    same = changed = 0
    for a,b in zip(jsA['images'], jsB['images']):
        ba = jsA['bufferViews'][a['bufferView']]; bb = jsB['bufferViews'][b['bufferView']]
        pa = bytes(BINa[ba.get('byteOffset',0):][:ba['byteLength']])
        pb = bytes(BINb[bb.get('byteOffset',0):][:bb['byteLength']])
        if a.get('name') in flat_names:
            if Image.open(io.BytesIO(pb)).size == (4,4): same += 1
            else: changed += 1
        else:
            if pa==pb: same += 1
            else: changed += 1
    chk(changed==0, f'{same}/{len(jsA["images"])} tekstur benar (detail bit-identik, datar -> 4x4), 0 tak terduga')
    return ok

if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv)>1 else 'char.bin'
    dst = sys.argv[2] if len(sys.argv)>2 else 'char_optim.vrm'
    log, flat = optimise(src, dst)
    print('\n=== HASIL OPTIMASI ===')
    for k,v in log: print(f'  {k:<20} {v}')
    print('\n  tekstur datar -> 4x4 (nol perubahan visual):')
    for nm, sz, why, bl in flat:
        print(f'    {str(nm)[:42]:44s} {sz[0]}x{sz[1]} -> 4x4  |  {why:<28} hemat {bl/1024:>6.0f} KB')
    ok = verify(src, dst, flat)
    print('\n=== ' + ('SEMUA LOLOS: model secara visual IDENTIK dengan aslinya'
                      if ok else 'ADA YANG GAGAL -- jangan pakai hasilnya') + ' ===')
    sys.exit(0 if ok else 1)
