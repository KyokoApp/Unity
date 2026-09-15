"""Port Python dari Locomotion.SamplePose + RigMapping.Resolve.
Tujuannya: memeriksa angka golden di RigMappingTests.cs tanpa NUnit,
karena sandbox ini tidak punya dotnet/Unity."""
import math

def sample_pose(phase=0,time=0,move=0,run=0,dash=0,airborne=False,falling=False,attack=None,combo=0):
    p={}
    def put(n,x=0.0,y=0.0,z=0.0): p[n]=(x,y,z)
    breath=math.sin(time*1.8)*.022
    put("PELVIS", .10*run+.36*dash, math.sin(phase)*.055*move, math.sin(phase)*.035*move)
    put("BELLY", breath-.04*run, 0, -math.sin(phase)*.022*move)
    put("CHEST", breath*.6, -math.sin(phase)*.13*move, 0)
    put("NECK", -.045*run)
    put("HEAD", -.025*run, math.sin(time*.55)*.035*(1-move))
    for side,offset,sign in (("R",0,1),("L",math.pi,-1)):
        swing=math.sin(phase+offset); lift=max(0.0,-swing)
        put("THIGH"+side, swing*(.40+.27*run+.15*dash)*move, 0, sign*.018*move)
        put("KNEE"+side, (.10+.78*lift*lift)*move)
        put("LOWLEG"+side, -.08*lift*move)
        put("FOOT"+side, (-swing*.20-lift*.15)*move)
        put("TOE"+side, max(0.0,swing)*.16*move)
        put("SHOULDER"+side, -swing*.09*move, 0, sign*.035*move)
        put("ARM"+side, -swing*(.30+.15*run)*move, 0, sign*.06)
        put("FOREARM"+side, .12+.35*run+.10*lift*move)
        put("HAND"+side, 0,0, sign*.04)
        put("KNUCLE"+side, .48 if side=="R" else .12)
        if airborne:
            put("THIGH"+side, .14 if falling else .38+offset*.035)
            put("KNEE"+side, .26 if falling else .68)
            put("FOOT"+side, -.18); put("TOE"+side, .05)
            put("ARM"+side, -.20,0,sign*.20); put("FOREARM"+side, .35)
    ax,ay,az=p["ARMR"]; p["ARMR"]=(ax-.12,ay,az)
    fx,fy,fz=p["FOREARMR"]; p["FOREARMR"]=(fx+.18,fy,fz)
    if attack is not None:
        t=max(0.0,min(1.0,attack))
        sm=lambda x:(x:=max(0.0,min(1.0,x)))*x*(3-2*x)
        wind=sm(t/.26); cut=sm((t-.26)/.22); recover=sm((t-.60)/.40)
        arc=(wind-2*cut)*(1-recover); direction=1 if combo%2==0 else -1; vertical=(combo==2)
        put("PELVIS",.07,arc*.32*direction); put("BELLY",.04,arc*.18*direction); put("CHEST",.10,arc*.55*direction)
        put("SHOULDERR",-.18,arc*.25*direction,-.12)
        put("ARMR", (-1.25*arc if vertical else -.35-.65*cut*(1-recover)), arc*.9*direction, -.22-arc*.55)
        put("FOREARMR",.4+.55*wind*(1-cut)); put("HANDR",-.12,arc*.22,0)
        put("ARML",.10,0,.18); put("FOREARML",.30)
        put("THIGHR",-.12*(1-recover)); put("THIGHL",.16*(1-recover))
        put("KNEER",.18*(1-recover)); put("KNEEL",.23*(1-recover))
    return p

SH_W=1.0; KN_W=1.0; SPLIT=0.5
def resolve(p):
    g=lambda k:(p.get(k) or (0.0,0.0,0.0))
    add=lambda a,b,w=1.0:(a[0]+b[0]*w, a[1]+b[1]*w, a[2]+b[2]*w)
    sc=lambda a,k:(a[0]*k,a[1]*k,a[2]*k)
    o={"Hips":g("PELVIS"),"Spine":g("BELLY"),"Chest":g("CHEST"),"Neck":g("NECK"),"Head":g("HEAD")}
    for side,pre in (("L","Left"),("R","Right")):
        o[pre+"UpperLeg"]=g("THIGH"+side); o[pre+"LowerLeg"]=g("KNEE"+side)
        o[pre+"ShinTwistA"]=sc(g("LOWLEG"+side),SPLIT); o[pre+"ShinTwistB"]=sc(g("LOWLEG"+side),1-SPLIT)
        o[pre+"Foot"]=g("FOOT"+side); o[pre+"Toes"]=g("TOE"+side)
        o[pre+"UpperArm"]=add(g("ARM"+side),g("SHOULDER"+side),SH_W)
        o[pre+"LowerArm"]=g("FOREARM"+side)
        o[pre+"Hand"]=add(g("HAND"+side),g("KNUCLE"+side),KN_W)
    return o

ok=True
def chk(c,msg):
    global ok
    print(("  [OK]    " if c else "  [GAGAL] ")+msg); ok = ok and c

E=1e-12
print("=== 1. PoseKeys == kunci SamplePose (7 keadaan) ===")
cases=[sample_pose(), sample_pose(.4,2.7,1,0,0), sample_pose(.4,1.1,1,1,.5),
       sample_pose(.4,1.1,1,0,0,True,False), sample_pose(.4,1.1,1,0,0,True,True),
       sample_pose(.4,1.1,1,0,0,False,False,.37,0), sample_pose(.4,1.1,1,0,0,False,False,.81,2)]
PK={"PELVIS","BELLY","CHEST","NECK","HEAD"}|{f"{b}{s}" for s in "LR" for b in
    ("THIGH","KNEE","LOWLEG","FOOT","TOE","SHOULDER","ARM","FOREARM","HAND","KNUCLE")}
for i,c in enumerate(cases):
    chk(set(c.keys())==PK and len(c)==25, f"keadaan {i}: {len(c)} kunci, cocok={set(c.keys())==PK}")

print("\n=== 2. Resolve mengisi 23 slot ===")
r=resolve(sample_pose(1.3,2.7,1,0,0))
chk(len(r)==23, f"jumlah slot = {len(r)} (harus 23)")

print("\n=== 3. Golden idle pose ===")
r=resolve(sample_pose())
exp={"Hips":(0,0,0),"Spine":(0,0,0),"Chest":(0,0,0),"Neck":(0,0,0),"Head":(0,0,0),
 "LeftUpperLeg":(0,0,0),"LeftLowerLeg":(0,0,0),"LeftFoot":(0,0,0),"LeftToes":(0,0,0),
 "RightUpperLeg":(0,0,0),"RightLowerLeg":(0,0,0),"RightFoot":(0,0,0),"RightToes":(0,0,0),
 "LeftShinTwistA":(0,0,0),"LeftShinTwistB":(0,0,0),"RightShinTwistA":(0,0,0),"RightShinTwistB":(0,0,0),
 "LeftUpperArm":(0,0,-.06),"RightUpperArm":(-.12,0,.06),
 "LeftLowerArm":(.12,0,0),"RightLowerArm":(.30,0,0),
 "LeftHand":(.12,0,-.04),"RightHand":(.48,0,.04)}
chk(set(exp)==set(r), "daftar slot cocok")
for k,v in exp.items():
    for i,ax in enumerate("XYZ"):
        chk(abs(r[k][i]-v[i])<E, f"{k}.{ax} = {r[k][i]!r} (tes mengharapkan {v[i]!r})") if abs(r[k][i]-v[i])>=E else None
bad=[(k,ax,r[k][i],v[i]) for k,v in exp.items() for i,ax in enumerate("XYZ") if abs(r[k][i]-v[i])>=E]
chk(not bad, f"semua 69 komponen idle cocok" if not bad else f"{len(bad)} beda: {bad[:4]}")

print("\n=== 4. Lipatan SHOULDER -> lengan atas ===")
ph,mv,rn=1.3,1,.6
p=sample_pose(ph,0,mv,rn,0); r=resolve(p)
for side,joint,sign,offset in (("L","LeftUpperArm",-1,math.pi),("R","RightUpperArm",1,0)):
    swing=math.sin(ph+offset)
    shx=-swing*.09*mv; shz=sign*.035*mv
    chk(abs(p["SHOULDER"+side][0]-shx)<E, f"SHOULDER{side}.X = {shx:.6f} (bukan nol)")
    chk(abs(r[joint][0]-(p["ARM"+side][0]+shx))<E, f"{joint}.X = ARM.X + SHOULDER.X")
    chk(abs(r[joint][2]-(p["ARM"+side][2]+shz))<E, f"{joint}.Z = ARM.Z + SHOULDER.Z")

print("\n=== 5. Lipatan KNUCLE -> pergelangan ===")
p=sample_pose(.9,.2,1,0,0); r=resolve(p)
chk(abs(r["LeftHand"][0]-(p["HANDL"][0]+.12))<E, "LeftHand.X = HAND.X + .12")
chk(abs(r["RightHand"][0]-(p["HANDR"][0]+.48))<E, "RightHand.X = HAND.X + .48")

print("\n=== 6. LOWLEG dibagi 0.5/0.5 ke tulang twist ===")
p=sample_pose(math.pi/2,0,1,0,0); r=resolve(p)
chk(abs(p["LOWLEGL"][0])>1e-6, f"prekondisi: LOWLEGL.X = {p['LOWLEGL'][0]:.6f} != 0")
chk(abs(r["LeftShinTwistA"][0]-p["LOWLEGL"][0]*.5)<E, "ShinTwistA = 0.5 x LOWLEG")
chk(abs(r["LeftShinTwistB"][0]-p["LOWLEGL"][0]*.5)<E, "ShinTwistB = 0.5 x LOWLEG")
chk(abs(r["LeftShinTwistA"][0]+r["LeftShinTwistB"][0]-p["LOWLEGL"][0])<E, "jumlahnya mengembalikan LOWLEG utuh")

print("\n=== 7. Kaki kiri/kanan berlawanan saat jalan ===")
r=resolve(sample_pose(.7,0,1,0,0))
chk(r["LeftUpperLeg"][0]*r["RightUpperLeg"][0]<0, "tanda X paha berlawanan")
chk(abs(r["LeftUpperLeg"][0]+r["RightUpperLeg"][0])<1e-12, "besar X paha sama")
chk(abs(r["LeftUpperLeg"][2]+r["RightUpperLeg"][2])<1e-12, "besar Z paha sama")

print("\n=== 8. Airborne menimpa ===")
air=resolve(sample_pose(.7,1,1,0,0,True,False)); fall=resolve(sample_pose(.7,1,1,0,0,True,True))
chk(abs(air["LeftUpperLeg"][0]-(.38+math.pi*.035))<E, f"LeftUpperLeg.X = .38+PI*.035 = {air['LeftUpperLeg'][0]:.10f}")
chk(abs(air["RightUpperLeg"][0]-.38)<E, "RightUpperLeg.X = .38")
chk(abs(air["LeftLowerLeg"][0]-.68)<E and abs(fall["LeftLowerLeg"][0]-.26)<E, "LowerLeg .68 (naik) / .26 (jatuh)")
chk(abs(air["LeftFoot"][0]+.18)<E and abs(air["LeftLowerArm"][0]-.35)<E, "Foot -.18, LowerArm .35")

print("\n=== 9. Attack memberi komponen Y pada lengan kanan ===")
p=sample_pose(.2,1,1,0,0,False,False,.35,0); r=resolve(p)
chk(abs(p["ARMR"][1])>1e-6, f"prekondisi: ARMR.Y = {p['ARMR'][1]:.6f} != 0")
chk(abs(r["RightUpperArm"][1]-(p["ARMR"][1]+p["SHOULDERR"][1]))<E, "RightUpperArm.Y = ARM.Y + SHOULDER.Y")

print("\n=== 10. Deterministik & tahan pose parsial ===")
p=sample_pose(2.1,.3,.8,.4,0)
chk(resolve(p)==resolve(p), "dua panggilan menghasilkan hasil identik")
rp=resolve({"PELVIS":(.1,.2,.3)})
chk(abs(rp["Hips"][0]-.1)<E and len(rp)==23, "pose parsial -> 23 slot, sisanya nol")

print("\n=== "+("SEMUA ANGKA GOLDEN DI TES TERBUKTI BENAR" if ok else "ADA YANG SALAH — perbaiki tesnya")+" ===")
