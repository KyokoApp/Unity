using System;
using System.Collections.Generic;

namespace RPG.Core
{
    /* ============================================================
       WORLD SCATTER — port dari game/world-stream.mjs bagian
       build() (baris 95-111) dan penempatan orb di index.html
       (baris 469-476) + pengambilan orb (baris 1456-1464).

       Yang diport HANYA keputusannya: apa yang ditaruh, di mana,
       seberapa besar, menghadap ke mana, dan collider-nya. Semua
       pembuatan mesh / InstancedMesh / THREE.Color ditinggal di
       sisi Runtime, karena itu tugas engine.

       Hasilnya: daftar transform siap pakai. Di Unity tinggal
       Instantiate prefab di posisi ini (tahap 4).

       CATATAN FIDELITAS — BACA SEBELUM MENGUBAH APA PUN:

       1. URUTAN KONSUMSI RNG ADALAH KONTRAK. world-stream.mjs
          mengambil angka acak dalam urutan tetap: x, z, scale,
          lalu (rock? yaw : yaw-daun). Kalau satu saja geser,
          SEMUA properti setelahnya pindah tempat dan tidak ada
          yang akan kelihatan salah kecuali tes paritas ini.

       2. `random()<.22 || region.id==='amber'` — di JS operator
          || mengevaluasi operand KIRI lebih dulu, jadi random()
          SELALU dikonsumsi meski region-nya amber. Port ini
          melakukan hal yang sama dengan sengaja.

       3. Cabang `continue` (terlalu rendah / terlalu dekat jalan /
          terlalu dekat waypoint) terjadi SETELAH x, z, scale
          diambil tapi SEBELUM yaw. Jadi iterasi yang dilewati
          tetap menghabiskan 3 angka acak.

       4. Math.hypot JS -> Math.Sqrt; Math.floor -> Math.Floor
          (bukan casting ke int, yang memotong ke arah nol).
       ============================================================ */
    public enum PropKind { Trunk, Leaf, Pine, Rock }

    public readonly struct PropPlacement
    {
        public readonly PropKind Kind;
        /* Koordinat LOKAL terhadap chunk, persis seperti JS yang
           menggambar relatif ke group.position. */
        public readonly double X, Y, Z;
        public readonly double Sx, Sy, Sz;
        public readonly double Yaw;
        /* Warna dedaunan dari region.foliage (0xRRGGBB). Batu tidak
           punya warna — diisi 0 dan harus diabaikan. */
        public readonly uint Foliage;
        public readonly bool HasFoliage;

        public PropPlacement(PropKind kind, double x, double y, double z,
                             double sx, double sy, double sz, double yaw,
                             uint foliage, bool hasFoliage)
        {
            Kind = kind; X = x; Y = y; Z = z;
            Sx = sx; Sy = sy; Sz = sz; Yaw = yaw;
            Foliage = foliage; HasFoliage = hasFoliage;
        }
    }

    public readonly struct ColliderCircle
    {
        /* Collider pakai koordinat DUNIA, bukan lokal — sama seperti
           JS yang mendorong {x:wx, z:wz, r:...}. */
        public readonly double X, Z, R;
        public ColliderCircle(double x, double z, double r) { X = x; Z = z; R = r; }
    }

    public readonly struct OrbPlacement
    {
        public readonly double X, Y, Z;   // Y sudah termasuk +1.1
        public readonly double BaseY;     // sama dengan Y, disimpan seperti userData.baseY
        public OrbPlacement(double x, double y, double z)
        { X = x; Y = y; Z = z; BaseY = y; }
    }

    public static class WorldScatter
    {
        public const double OrbCount = 12;
        /* Radius ambil orb. Di JS: `mode==='car' ? 4.0 : 2.4`.
           Game ini tanpa mobil, jadi yang dipakai selalu 2.4. */
        public const double OrbPickupRadius = 2.4;
        public const double OrbPickupHeight = 3.8;
        public const double OrbBobAmount = 0.22;
        public const double OrbBobSpeed = 1.6;

        public readonly struct ScatterResult
        {
            public readonly List<PropPlacement> Props;
            public readonly List<ColliderCircle> Colliders;
            public ScatterResult(List<PropPlacement> p, List<ColliderCircle> c)
            { Props = p; Colliders = c; }
        }

        /* Port setia dari loop sebar properti di world-stream.mjs. */
        public static ScatterResult Build(int cx, int cz, bool near, int propsNear, int propsFar)
        {
            var props = new List<PropPlacement>();
            var colliders = new List<ColliderCircle>();

            var random = WorldData.RandomForChunk(cx, cz);
            var ox = cx * WorldData.ChunkSize;
            var oz = cz * WorldData.ChunkSize;
            var count = near ? propsNear : propsFar;

            for (var i = 0; i < count; i++)
            {
                var x = random() * WorldData.ChunkSize;
                var z = random() * WorldData.ChunkSize;
                var wx = x + ox;
                var wz = z + oz;
                var y = WorldData.TerrainH(wx, wz);
                var scale = .65 + random() * 1.05;
                var region = WorldData.RegionAt(wx, wz);

                /* Urutan tiga syarat ini tidak mempengaruhi hasil, tapi
                   disimpan sama seperti aslinya supaya mudah dibedakan. */
                if (y < 2 || WorldData.RoadInfo(wx, wz).Edge < 10 || AnyWaypointWithin(wx, wz, 70))
                    continue;

                /* PENTING: random() dikonsumsi LEBIH DULU, selalu.
                   Lihat catatan fidelitas #2 di atas. */
                if (random() < .22 || region.Id == "amber")
                {
                    var yaw = random() * 6.28;
                    props.Add(new PropPlacement(PropKind.Rock, x, y + scale, z,
                                                scale * 2, scale * 1.5, scale * 1.7, yaw, 0, false));
                    if (near) colliders.Add(new ColliderCircle(wx, wz, scale * 1.7));
                    continue;
                }

                props.Add(new PropPlacement(PropKind.Trunk, x, y + 3.5 * scale, z,
                                            scale, scale, scale, 0, 0, false));

                var pine = region.Id == "frost" || region.Id == "highlands";
                var typeYaw = random() * 6.28;
                var sy = pine ? scale : .85 * scale;
                props.Add(new PropPlacement(pine ? PropKind.Pine : PropKind.Leaf,
                                            x, y + 8 * scale, z,
                                            scale, sy, scale, typeYaw,
                                            region.Foliage, true));
                if (near) colliders.Add(new ColliderCircle(wx, wz, .65 * scale));
            }

            return new ScatterResult(props, colliders);
        }

        /* WAYPOINTS.some(w => Math.hypot(wx-w.x, wz-w.z) < r) */
        static bool AnyWaypointWithin(double wx, double wz, double r)
        {
            foreach (var w in WorldData.Waypoints)
            {
                var d = Math.Sqrt((wx - w.X) * (wx - w.X) + (wz - w.Z) * (wz - w.Z));
                if (d < r) return true;
            }
            return false;
        }

        /* Penempatan 12 orb dari index.html:469-476. Murni deterministik:
           waypoint[i % 7], geser +-18 di x, mundur 25 + 55 per putaran. */
        public static List<OrbPlacement> PlaceOrbs()
        {
            var list = new List<OrbPlacement>();
            var waypoints = WorldData.Waypoints;
            for (var i = 0; i < (int)OrbCount; i++)
            {
                var w = waypoints[i % waypoints.Length];
                var x = w.X + (i % 2 == 1 ? 18 : -18);
                var z = w.Z - 25 - Math.Floor(i / (double)waypoints.Length) * 55;
                var y = WorldData.TerrainH(x, z);
                list.Add(new OrbPlacement(x, y + 1.1, z));
            }
            return list;
        }

        /* Gerakan naik-turun orb: baseY + sin(t*1.6 + position.x)*0.22.
           Catatan: JS memakai o.position.x yang SUDAH berupa koordinat
           dunia, jadi pemanggil harus mengoper x dunia. */
        public static double OrbY(double baseY, double worldX, double t)
            => baseY + Math.Sin(t * OrbBobSpeed + worldX) * OrbBobAmount;

        /* Syarat pengambilan, index.html:1461-1462 (cabang non-mobil). */
        public static bool OrbCollectible(double orbX, double orbY, double orbZ,
                                          double playerX, double playerZ, double groundY)
        {
            var d = Math.Sqrt((orbX - playerX) * (orbX - playerX) + (orbZ - playerZ) * (orbZ - playerZ));
            return d < OrbPickupRadius && Math.Abs(orbY - (groundY + 1.0)) < OrbPickupHeight;
        }
    }
}
