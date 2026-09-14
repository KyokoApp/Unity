/* Dump kanonik dari modul JS ASLI. Dipakai sebagai acuan untuk
   membandingkan hasil port C# — baris per baris, format identik. */
import * as Q from '../rpg/game/quality.mjs';
import * as W from './world-3km.mjs';
import * as L from '../rpg/game/locomotion.mjs';

const out = [];
/* 17 digit signifikan = round-trip penuh, jadi tidak ada kasus "tepat di
   tengah" yang bisa dibulatkan berbeda oleh toFixed JS vs F9 .NET.
   -0 dinormalkan karena IEEE -0 === 0 (murni artefak format). */
const num = v => (Number(v) === 0 ? 0 : Number(v)).toPrecision(17);
const push = (k, v) => out.push(`${k}=${v}`);

/* ---------- world-data ---------- */
const pts = [[0,0],[617,-2839],[1500,1500],[-1500,-1500],[800,1050],[-1850,1050],[1400,-1350],[150,750],[1468,1468],[-1400,300]];
for (const [x,z] of pts) {
  push(`wd.terrainH(${x},${z})`, num(W.terrainH(x,z)));
  push(`wd.roadHeight(${x},${z})`, num(W.roadHeight(x,z)));
  const ri = W.roadInfo(x,z);
  push(`wd.roadInfo(${x},${z}).edge`, num(ri.edge));
  push(`wd.roadInfo(${x},${z}).distance`, num(ri.distance));
  push(`wd.roadInfo(${x},${z}).halfWidth`, num(ri.halfWidth));
  push(`wd.roadInfo(${x},${z}).along`, num(ri.along));
  push(`wd.roadInfo(${x},${z}).lane`, String(ri.lane));
  push(`wd.roadInfo(${x},${z}).axis`, ri.axis);
  push(`wd.regionAt(${x},${z})`, W.regionAt(x,z).id);
  const tc = W.terrainColor(x,z);
  push(`wd.terrainColor(${x},${z})`, tc.map(num).join(','));
}
for (const [lx,lz] of [[0,0],[2,-2],[1,1]]) {
  const it = W.intersection(lx,lz);
  push(`wd.intersection(${lx},${lz})`, `${num(it.x)},${num(it.z)}`);
}
W.WAYPOINTS.forEach((w,i) => push(`wd.waypoint[${i}]`, `${w.id}:${num(w.x)},${num(w.z)}`));
W.chunkPlan(100,-200,3).slice(0,8).forEach((c,i) =>
  push(`wd.chunkPlan[${i}]`, `${c.key}:${c.near}:${c.distance}`));
push('wd.chunkPlan.count', String(W.chunkPlan(100,-200,3).length));
const rnd = W.randomForChunk(7,-3);
for (let i=0;i<5;i++) push(`wd.randomForChunk(7,-3)[${i}]`, num(rnd()));
push('wd.REGION_COUNT', String(W.REGIONS.length));
push('wd.WORLD_LIMIT', num(W.WORLD_LIMIT));

/* ---------- locomotion ---------- */
const poses = [
  {phase:0.7,time:1.3,move:1,run:0,dash:0,airborne:false,falling:false,attack:null,combo:0},
  {phase:2.1,time:5.5,move:1,run:1,dash:0,airborne:false,falling:false,attack:null,combo:0},
  {phase:3.3,time:9.1,move:1,run:0,dash:1,airborne:true,falling:true,attack:null,combo:0},
  {phase:0.4,time:2.2,move:1,run:0,dash:0,airborne:false,falling:false,attack:0.31,combo:0},
  {phase:0.4,time:2.2,move:1,run:0,dash:0,airborne:false,falling:false,attack:0.85,combo:1},
  {phase:0.4,time:2.2,move:1,run:0,dash:0,airborne:false,falling:false,attack:0.50,combo:2},
];
poses.forEach((inp,i) => {
  const pose = L.samplePose(inp);
  Object.keys(pose).sort().forEach(k => {
    const [x,y,z] = pose[k];
    push(`lo.pose[${i}].${k}`, `${num(x)},${num(y)},${num(z)}`);
  });
  push(`lo.pose[${i}].__count`, String(Object.keys(pose).length));
});
for (const [c,t,r,dt] of [[0,1,8,0.016],[5,-2,3,0.033]])
  push(`lo.damp(${c},${t},${r},${dt})`, num(L.damp(c,t,r,dt)));
for (const [x,y] of [[0,0],[10,5],[40,-30],[0,55],[100,100],[3,4]])
  push(`lo.joystick(${x},${y})`, (()=>{const a=L.joystickAxis(x,y);return `${num(a.x)},${num(a.y)}`;})());

/* ---------- quality ---------- */
const legacy = {sensitivity:1.4,cameraDistance:6,quality:'high',shadows:false,sound:true};
const cases = {
  legacy,
  empty: {},
  nullish: null,
  junkgfx: {gfx:null},
  oob: {sensitivity:99,cameraDistance:-5,quality:'ngawur',fps:999,gfx:{renderScale:9,shadows:9,texture:9,bloom:-3}},
  nan: {fps:NaN,gfx:{renderScale:NaN}},
  partial: {quality:'ultra',gfx:{shadows:2}},
  layout: {layout:{a:{x:1.5,y:-0.2},b:{x:0.3,y:0.4},c:null}},
};
for (const [name,raw] of Object.entries(cases)) {
  const s = Q.normalizeSettings(raw);
  push(`q.norm[${name}].sensitivity`, num(s.sensitivity));
  push(`q.norm[${name}].cameraDistance`, num(s.cameraDistance));
  push(`q.norm[${name}].quality`, s.quality);
  push(`q.norm[${name}].shadows`, String(s.shadows));
  push(`q.norm[${name}].sound`, String(s.sound));
  push(`q.norm[${name}].fps`, String(s.fps));
  push(`q.norm[${name}].custom`, String(s.custom));
  push(`q.norm[${name}].showFps`, String(s.showFps));
  push(`q.norm[${name}].stickShape`, s.stickShape);
  push(`q.norm[${name}].buttonTheme`, s.buttonTheme);
  push(`q.norm[${name}].buttonScale`, num(s.buttonScale));
  push(`q.norm[${name}].gfx`, [s.gfx.renderScale,s.gfx.shadows,s.gfx.grass,s.gfx.particles,s.gfx.water,
    s.gfx.view,s.gfx.detail,s.gfx.texture,s.gfx.bloom,s.gfx.motionBlur,s.gfx.volumetric,s.gfx.adaptive]
    .map(v => typeof v === 'boolean' ? String(v) : num(v)).join(','));
  push(`q.norm[${name}].layout`, Object.keys(s.layout).sort()
    .map(k => `${k}:${num(s.layout[k].x)},${num(s.layout[k].y)}`).join('|') || '(kosong)');
}

let s0 = Q.normalizeSettings({});
for (const id of Q.PRESET_IDS) {
  const s = Q.applyPreset(s0, id);
  push(`q.applyPreset(${id})`, `${s.quality}:${s.fps}:${s.custom}:${s.shadows}:${num(s.gfx.renderScale)}:${s.gfx.shadows}:${s.gfx.motionBlur}:${s.gfx.adaptive}`);
  push(`q.detectPreset(${id})`, Q.detectPreset(s.gfx));
  const r1 = Q.resolveGfx(s,false), r2 = Q.resolveGfx(s,true);
  const keys = ['dprCap','renderScale','adaptive','shadowsEnabled','shadowMapSize','shadowRefreshFrames',
    'grassCount','grassEnabled','dustCount','butterflyCount','birdCount','particlesEnabled','waterSegments',
    'waterWaves','waterOpacity','fogNear','fogFar','orbCullDistance','streamRadius','terrainSegmentsNear',
    'propsNear','propsFar','roadProps','roadPropSpacing','textureSize','anisotropy','bloomLevel',
    'motionBlurLevel','volumetricLevel','postEnabled'];
  keys.forEach(k => {
    const f = v => typeof v === 'boolean' ? String(v) : num(v);
    push(`q.resolve[${id}].desk.${k}`, f(r1[k]));
    push(`q.resolve[${id}].touch.${k}`, f(r2[k]));
  });
}
const mixed = Q.setGfx(Q.applyPreset(s0,'high'),'shadows',0);
push('q.setGfx(shadows,0)', `${mixed.quality}:${mixed.custom}:${mixed.gfx.shadows}:${Q.detectPreset(mixed.gfx)}`);
const scaled = Q.setGfx(Q.applyPreset(s0,'low'),'renderScale',0.93);
push('q.setGfx(renderScale,0.93)', `${scaled.quality}:${num(scaled.gfx.renderScale)}`);
const clamped = Q.setGfx(Q.applyPreset(s0,'low'),'bloom',99);
push('q.setGfx(bloom,99)', String(clamped.gfx.bloom));
const adaptive = Q.setGfx(Q.applyPreset(s0,'low'),'adaptive',false);
push('q.setGfx(adaptive,false)', `${adaptive.gfx.adaptive}:${adaptive.quality}`);
const unknown = Q.setGfx(s0,'ngawur',3);
push('q.setGfx(unknown)', `${unknown.quality}:${unknown.custom}`);
Q.FPS_CHOICES.forEach(f => push(`q.frameInterval(${f})`, num(Q.frameInterval(f))));
push('q.frameInterval(50)', num(Q.frameInterval(50)));
push('q.frameInterval(0)', num(Q.frameInterval(0)));

const ar = Q.createAdaptiveResolution({min:0.6,max:1,start:1});
for (let i=0;i<25;i++) push(`q.adaptive.bad[${i}]`, num(ar.update(40, 1000/45)));
for (let i=0;i<160;i++) push(`q.adaptive.good[${i}]`, num(ar.update(5, 1000/45)));
push('q.adaptive.invalid', num(ar.update(NaN, 1000/45)));
push('q.adaptive.zerotarget', num(ar.update(40, 0)));


/* ---------- world-scatter (keputusan sebar properti + orb) ---------- */
const S = await import('./world-scatter-3km.mjs');
const sum = a => a.reduce((t, v) => t + v, 0);
for (const [cx, cz, near] of [[0,0,true],[0,0,false],[2,-3,true],[-4,5,true],[5,5,false],[-2,-2,true]]) {
  const r = S.scatterChunk(cx, cz, near, 40, 8);
  const tag = `sc[${cx},${cz},${near ? 'near' : 'far'}]`;
  push(`${tag}.count`, num(r.props.length));
  push(`${tag}.sumX`, num(sum(r.props.map(p => p.x))));
  push(`${tag}.sumY`, num(sum(r.props.map(p => p.y))));
  push(`${tag}.sumZ`, num(sum(r.props.map(p => p.z))));
  push(`${tag}.sumYaw`, num(sum(r.props.map(p => p.yaw))));
  push(`${tag}.colliders`, num(r.colliders.length));
  push(`${tag}.sumR`, num(sum(r.colliders.map(c => c.r))));
  for (let i = 0; i < Math.min(3, r.props.length); i++) {
    const p = r.props[i];
    push(`${tag}.p${i}`, [p.kind, num(p.x), num(p.y), num(p.z), num(p.sx), num(p.sy), num(p.sz), num(p.yaw), p.foliage].join('|'));
  }
}
/* Sapuan seluruh dunia: 12x12 chunk menutup [-1536,1536] m, lebih lebar dari
   WORLD_LIMIT=1468. Enam chunk di atas terlalu sedikit — mutasi ambang .22->.23
   pernah LOLOS karena dari 140 undian tidak ada satu pun jatuh di pita 1% itu.
   Grid ini membuat ~5.760 undian, jadi pita 1% pasti kena. */
for (let gx = -6; gx <= 5; gx++) for (let gz = -6; gz <= 5; gz++) {
  const r = S.scatterChunk(gx, gz, true, 40, 8);
  const tag = `grid[${gx},${gz}]`;
  push(`${tag}.count`, num(r.props.length));
  push(`${tag}.sumY`, num(sum(r.props.map(p => p.y))));
  push(`${tag}.sumYaw`, num(sum(r.props.map(p => p.yaw))));
  push(`${tag}.colliders`, num(r.colliders.length));
  push(`${tag}.sumR`, num(sum(r.colliders.map(c => c.r))));
  const kinds = { trunk: 0, leaf: 0, pine: 0, rock: 0 };
  for (const p of r.props) kinds[p.kind]++;
  push(`${tag}.kinds`, `${kinds.trunk},${kinds.leaf},${kinds.pine},${kinds.rock}`);
}

const orbs = S.placeOrbs();
push('orb.count', num(orbs.length));
for (let i = 0; i < orbs.length; i++) push(`orb[${i}]`, [num(orbs[i].x), num(orbs[i].y), num(orbs[i].z)].join(','));
push('orb.bob.t0.7.x123.4', num(orbs[0].baseY + Math.sin(0.7 * 1.6 + 123.4) * 0.22));
push('orb.bob.t12.5.x-900', num(orbs[5].baseY + Math.sin(12.5 * 1.6 + -900) * 0.22));

console.log(out.join('\n'));
