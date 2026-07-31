"""Head-to-head: the two WL.2 heading models, identical kinematics otherwise.

  A = claude/witchlight-authoring          (deviation: wrap(phi_fast - phi_slow), k per-track)
  B = claude/witchlight-preset-authoring   (single-EMA rate: d/dt phi_bar, k fixed 1.10)

Each runs with ITS OWN branch's constants, because the constants are part of the
proposal. Metrics include headingMonotonicity (|net| / travel) — B's branch
introduced it and it is the sharper diagnostic for this exact failure:
 ~1 = the pen turned one way the whole time (saturated clamp -> a circle)
 ~0 = it reversed (a figure)
"""
import csv, math, os, sys, colorsys

BASE = os.path.expanduser("~/Documents/phosphene_sessions")
W, H = 960, 540
TRAIL, EMIT = 30.0, 34.0

CONST = {
    # mine: speed/radius in frame-heights; omega_max = 1.5 rad/s
    "A_deviation": dict(tau_fast=0.8, tau_slow=8.0, speed=0.12, rmin=0.08,
                        gain=None, speedmod=0.25, relax_per_s=None, relax_k=0.30),
    # theirs: world units (frame height = 2.0); omega_max = 0.625 rad/s
    "B_single_ema": dict(tau_fast=1.5, tau_slow=None, speed=0.10, rmin=0.16,
                         gain=1.10, speedmod=0.25, relax_per_s=1.2, relax_k=None),
}

def wrap(d): return (d + math.pi) % (2*math.pi) - math.pi
def pct(xs,q):
    s=sorted(xs); return s[min(len(s)-1,max(0,int(round(q*(len(s)-1)))))]

def load(cap, secs):
    t=[];p=[];a=[]
    with open(f"{BASE}/{cap}/features.csv",newline="") as fh:
        for r in csv.DictReader(fh):
            try:
                ti=float(r["wallclock_s"])
                if t and ti-t[0]>secs: break
                t.append(ti); p.append(float(r["tonal_phase_fifths"])); a.append(float(r["arousal"]))
            except (ValueError,KeyError): pass
    return t,p,a

def cema(t,p,tau):
    c,s=math.cos(p[0]),math.sin(p[0]); out=[]; prev=t[0]
    for ti,v in zip(t,p):
        dt=max(1e-4,ti-prev); prev=ti; al=1-math.exp(-dt/tau)
        c+=al*(math.cos(v)-c); s+=al*(math.sin(v)-s); out.append(math.atan2(s,c))
    return out

def run(cap, model, secs=40.0):
    K=CONST[model]; t,ph,ar = load(cap,secs)
    fast=cema(t,ph,K["tau_fast"])
    if model=="A_deviation":
        slow=cema(t,ph,K["tau_slow"])
        signal=[wrap(f-s) for f,s in zip(fast,slow)]
        gain=(0.85*(K["speed"]/K["rmin"]))/max(1e-6,pct([abs(x) for x in signal],0.95))
    else:
        signal=[0.0]+[wrap(b-a)/max(1e-4,tb-ta) for a,b,ta,tb in zip(fast,fast[1:],t,t[1:])]
        gain=K["gain"]

    th=x=y=0.0; beads=[]; clamped=0; steps=0; travel=0.0; net=0.0; since=0.0; prev=t[0]
    aslow=ar[0]; aspread=0.15
    for ti,sig,a_,f in zip(t,signal,ar,fast):
        dt=max(1e-4,ti-prev); prev=ti
        sa=dt/(20.0+dt); aslow+=(a_-aslow)*sa; aspread+=(abs(a_-aslow)-aspread)*sa
        an=max(-1,min(1,(a_-aslow)/(2*max(aspread,0.05))))
        speed=K["speed"]*(1+K["speedmod"]*an)
        omax=speed/max(K["rmin"],1e-4)
        des=gain*sig; w=max(-omax,min(omax,des))
        if abs(des)>=omax: clamped+=1
        steps+=1; th+=w*dt; travel+=abs(w)*dt; net+=w*dt
        x+=speed*math.cos(th)*dt; y+=speed*math.sin(th)*dt
        since+=dt
        if since>=1.0/EMIT:
            since=0.0; beads.append([x,y,0.0,(f+math.pi)/(2*math.pi)])
        for b in beads: b[2]+=dt
        while beads and beads[0][2]>TRAIL: beads.pop(0)
        for i in range(1,len(beads)-1):
            age=beads[i][2]
            if age>=4.0: break
            base = K["relax_per_s"]*dt if K["relax_per_s"] else K["relax_k"]
            wg=base*(1.0 if age<=1.0 else (4.0-age)/3.0)
            wg=min(wg,0.5)
            mx=0.5*(beads[i-1][0]+beads[i+1][0]); my=0.5*(beads[i-1][1]+beads[i+1][1])
            beads[i][0]+=wg*(mx-beads[i][0]); beads[i][1]+=wg*(my-beads[i][1])
    mono = abs(net)/travel if travel>1e-4 else 0.0
    return beads, clamped/max(1,steps), travel/(2*math.pi), mono

def raster(beads,path):
    if not beads: return
    xs=[b[0] for b in beads]; ys=[b[1] for b in beads]
    cx,cy=(min(xs)+max(xs))/2,(min(ys)+max(ys))/2
    ext=max(max(xs)-min(xs),max(ys)-min(ys),1e-3); sc=0.80*H/ext
    buf=[[0.0,0.0,0.0] for _ in range(W*H)]
    def put(i,j,r,g,b):
        if 0<=i<W and 0<=j<H:
            p=buf[j*W+i]; p[0]+=r;p[1]+=g;p[2]+=b
    for idx,(bx,by,age,hue) in enumerate(beads):
        al=max(0.0,1-age/TRAIL)**1.6
        if al<=0: continue
        r,g,bl=colorsys.hsv_to_rgb(hue%1.0,0.72,1.0)
        i=int(W/2+(bx-cx)*sc); j=int(H/2-(by-cy)*sc)
        rad=max(1,int(2.6*(1-0.65*age/TRAIL)))
        for dj in range(-rad,rad+1):
            for di in range(-rad,rad+1):
                d2=di*di+dj*dj
                if d2<=rad*rad:
                    f=al*(1-math.sqrt(d2)/(rad+.5)); put(i+di,j+dj,r*f,g*f,bl*f)
        if idx+1<len(beads):
            nx,ny=beads[idx+1][0],beads[idx+1][1]
            i2=int(W/2+(nx-cx)*sc); j2=int(H/2-(ny-cy)*sc)
            n=max(abs(i2-i),abs(j2-j),1)
            for s_ in range(n):
                put(int(i+(i2-i)*s_/n),int(j+(j2-j)*s_/n),r*al*.35,g*al*.35,bl*al*.35)
    with open(path,"wb") as fh:
        fh.write(b"P6\n%d %d\n255\n"%(W,H))
        fh.write(bytes(min(255,int(255*(1-math.exp(-1.7*max(0.0,c))))) for p in buf for c in p))

out=sys.argv[1]; os.makedirs(out,exist_ok=True)
print(f"{'capture':26}{'model':>14}{'clamp%':>9}{'turns':>8}{'monotonicity':>14}  (mono ~1 = circle, ~0 = figure)")
for cap in ["fixturegen-so_what","fixturegen-there_there","fixturegen-love_rehab","beat-match-test-session"]:
    for m in ["A_deviation","B_single_ema"]:
        b,cf,tv,mo=run(cap,m); raster(b,f"{out}/{cap}_{m}.ppm")
        print(f"{cap:26}{m:>14}{100*cf:>8.1f}%{tv:>8.2f}{mo:>14.3f}")
