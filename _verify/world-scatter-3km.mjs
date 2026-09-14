/* Keputusan sebar properti per chunk — DIEKSTRAK dari world-stream.mjs.

   Alasan ekstraksi: loop ini murni deterministik (RNG chunk + terrainH +
   regionAt + roadInfo + WAYPOINTS) dan tidak butuh three.js sama sekali,
   tapi tadinya terkubur di dalam build() yang membuat InstancedMesh.
   Sekarang world-stream.mjs memakai fungsi ini, dan tes bisa membandingkan
   port C# terhadap kode yang BENAR-BENAR dijalankan game — bukan salinan.

   KONTRAK: urutan pengambilan angka acak tidak boleh diubah. x, z, scale
   selalu dikonsumsi; yaw hanya di cabang yang mencapai ujung. Menggeser
   satu saja memindahkan semua properti setelahnya tanpa error apa pun. */
import { CHUNK_SIZE, terrainH, roadInfo, regionAt, WAYPOINTS, randomForChunk } from './world-3km.mjs';

export function scatterChunk(cx, cz, near, propsNear, propsFar) {
  const ox = cx * CHUNK_SIZE, oz = cz * CHUNK_SIZE;
  const random = randomForChunk(cx, cz);
  const props = [], colliders = [];
  const count = near ? propsNear : propsFar;
  for (let i = 0; i < count; i++) {
    const x = random() * CHUNK_SIZE, z = random() * CHUNK_SIZE;
    const wx = x + ox, wz = z + oz, y = terrainH(wx, wz);
    const scale = .65 + random() * 1.05, region = regionAt(wx, wz);
    if (y < 2 || roadInfo(wx, wz).edge < 10 || WAYPOINTS.some(w => Math.hypot(wx - w.x, wz - w.z) < 70)) continue;
    // random() dievaluasi lebih dulu (operand kiri ||), jadi selalu terpakai.
    if (random() < .22 || region.id === 'amber') {
      props.push({ kind: 'rock', x, y: y + scale, z, sx: scale * 2, sy: scale * 1.5, sz: scale * 1.7, yaw: random() * 6.28, foliage: null });
      if (near) colliders.push({ x: wx, z: wz, r: scale * 1.7 });
      continue;
    }
    props.push({ kind: 'trunk', x, y: y + 3.5 * scale, z, sx: scale, sy: scale, sz: scale, yaw: 0, foliage: null });
    const type = ['frost', 'highlands'].includes(region.id) ? 'pine' : 'leaf';
    props.push({ kind: type, x, y: y + 8 * scale, z, sx: scale, sy: type === 'leaf' ? .85 * scale : scale, sz: scale, yaw: random() * 6.28, foliage: region.foliage });
    if (near) colliders.push({ x: wx, z: wz, r: .65 * scale });
  }
  return { props, colliders };
}

/* Penempatan 12 orb — diekstrak dari index.html:469-476. */
export const ORB_COUNT = 12;
export function placeOrbs() {
  const out = [];
  for (let i = 0; i < ORB_COUNT; i++) {
    const waypoint = WAYPOINTS[i % WAYPOINTS.length];
    const x = waypoint.x + (i % 2 ? 18 : -18);
    const z = waypoint.z - 25 - Math.floor(i / WAYPOINTS.length) * 55;
    const y = terrainH(x, z);
    out.push({ x, y: y + 1.1, z, baseY: y + 1.1 });
  }
  return out;
}
