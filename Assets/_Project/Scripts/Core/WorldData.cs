using System;
using System.Collections.Generic;
using System.Linq;

namespace RPG.Core
{
    /* ============================================================
       WORLD DATA — port 1:1 dari game/world-data.mjs (80 baris).

       Satu unit dunia = satu meter. Semua terrain/jalan deterministik
       dan di-sample di ruang dunia, jadi hasilnya identik di editor
       maupun di build, dan bisa dites headless tanpa scene.

       CATATAN FIDELITAS:
       - Math.imul / >>> di JS dipetakan ke aritmetika uint C# (unchecked),
         yang membungkus mod 2^32 persis seperti JS.
       - Math.hypot JS digantikan Math.Sqrt; selisihnya hanya muncul pada
         magnitudo ekstrem yang tidak terjadi di dunia 3 km ini.
       - Math.Sin/Cos .NET bisa beda beberapa ULP dari JS. Tes memakai
         toleransi, bukan kesamaan bit.
       ============================================================ */
    public static class WorldData
    {
        public const double WorldSize = 3000;    // 24 km -> 12 km -> 6 km -> 3 km
        public const double WorldLimit = WorldSize / 2 - 32;
        public const double ChunkSize = 256;
        public const double WaterLevel = 0;
        public const double RoadSpacing = 750;   // 1500 hanya menyisakan lajur 0 & 1 di dunia 3 km

        static double Clamp(double v, double a = 0, double b = 1) => Math.Max(a, Math.Min(b, v));

        static double Smooth(double a, double b, double v)
        {
            var t = Clamp((v - a) / (b - a));
            return t * t * (3 - 2 * t);
        }

        /* imul JS: perkalian 32-bit yang membuang bit tinggi. */
        static uint IMul(uint a, uint b) => unchecked(a * b);

        public static double RoadX(double z, int lane = 0)
            => lane * RoadSpacing + 70 * Math.Sin(z / 850);

        public static double RoadZ(double x, int lane = 0)
            => lane * RoadSpacing + 60 * Math.Sin(x / 600);

        public readonly struct RoadSample
        {
            public readonly double Edge;
            public readonly double Distance;
            public readonly double HalfWidth;
            public readonly double Along;
            public readonly int Lane;
            public readonly char Axis;   // 'x' atau 'z', sama seperti string di JS

            public RoadSample(double edge, double distance, double halfWidth,
                              double along, int lane, char axis)
            {
                Edge = edge; Distance = distance; HalfWidth = halfWidth;
                Along = along; Lane = lane; Axis = axis;
            }
        }

        public static RoadSample RoadInfo(double x, double z)
        {
            var laneX = JsMath.RoundToInt((x - RoadX(z)) / RoadSpacing);
            var laneZ = JsMath.RoundToInt((z - RoadZ(x)) / RoadSpacing);
            var dx = Math.Abs(x - RoadX(z, laneX));
            var dz = Math.Abs(z - RoadZ(x, laneZ));
            var wx = Math.Abs(laneX) % 2 == 0 ? 8 : 4;
            var wz = Math.Abs(laneZ) % 2 == 0 ? 8 : 4;
            return dx - wx < dz - wz
                ? new RoadSample(dx - wx, dx, wx, z, laneX, 'z')
                : new RoadSample(dz - wz, dz, wz, x, laneZ, 'x');
        }

        public static double RoadHeight(double x, double z)
            => 28 + 14 * Math.Sin(x * .0014) * Math.Cos(z * .0012) + 6 * Math.Sin((x + z) * .002);

        public static double TerrainH(double x, double z)
        {
            var baseH = RoadHeight(x, z);
            var north = Smooth(250, 1750, -z);   // diskala: dunia 1/16 luasnya
            var ridge = Math.Sin(x * .0028 + Math.Cos(z * .002)) * .5 + .5;
            var h = baseH + 12 * Math.Sin(x * .012) * Math.Cos(z * .01) + 7 * Math.Sin((x - z) * .004);
            h += north * (45 + 180 * ridge * ridge) + 18 * Math.Sin(x * .0024) * Math.Sin(z * .0034);

            /* Sungai menerus + dua danau lebar. Tanggul jalan tetap di atas air. */
            var river = Math.Abs(x - (400 + 70 * Math.Sin(z * .002)));
            var lakeA = Math.Sqrt(Math.Pow((x + 1150) * .8, 2) + Math.Pow(z - 1150, 2));
            var lakeB = Math.Sqrt(Math.Pow(x - 1150, 2) + Math.Pow((z + 1150) * .8, 2));
            var wet = 1 - Smooth(30, 65, Math.Min(river, Math.Min(lakeA - 145, lakeB - 162.5)));
            h = h * (1 - wet) - 5 * wet;

            var road = 1 - Smooth(4, 42, RoadInfo(x, z).Edge);
            return h * (1 - road) + baseH * road;
        }

        public sealed class Region
        {
            public string Id;
            public string Name;
            public string Subtitle;
            public double X, Z;
            public double[] Color;    // rgb 0..1, sama seperti array di JS
            public uint Foliage;      // 0xRRGGBB
        }

        public static readonly Region[] Regions =
        {
            new Region { Id="heartlands", Name="Aurelia Heartlands", Subtitle="Padang hijau & gerbang kerajaan", X=0,     Z=0,     Color=new[]{.42,.56,.28}, Foliage=0x729b53 },
            new Region { Id="frost",      Name="Frostspire Reach",   Subtitle="Puncak es & menara penjaga",      X=-750,  Z=-750, Color=new[]{.68,.76,.77}, Foliage=0x8eafb0 },
            new Region { Id="highlands",  Name="Crownfall Highlands",Subtitle="Pegunungan & reruntuhan kuno",    X=0,     Z=-750, Color=new[]{.43,.49,.42}, Foliage=0x58705b },
            new Region { Id="amber",      Name="Amber Wastes",       Subtitle="Bukit keemasan & kuil matahari",  X=750,   Z=-750, Color=new[]{.72,.56,.33}, Foliage=0xb88d4b },
            new Region { Id="forest",     Name="Elderwood Wilds",    Subtitle="Hutan tua & batu bercahaya",      X=-750,  Z=750,   Color=new[]{.25,.43,.33}, Foliage=0x3c7963 },
            new Region { Id="bloom",      Name="Roseveil Expanse",   Subtitle="Dataran bunga & pohon merah muda",X=0,     Z=750,   Color=new[]{.49,.48,.39}, Foliage=0xba7993 },
            new Region { Id="coast",      Name="Azure Coast",        Subtitle="Lembah sungai & kristal biru",    X=750,   Z=750,   Color=new[]{.46,.60,.47}, Foliage=0x6faca1 },
        };

        public static Region RegionAt(double x, double z)
        {
            var result = Regions[0];
            var best = double.PositiveInfinity;
            foreach (var r in Regions)
            {
                var d = (x - r.X) * (x - r.X) + (z - r.Z) * (z - r.Z);
                if (d < best) { best = d; result = r; }
            }
            return result;
        }

        public static double[] TerrainColor(double x, double z)
        {
            Region first = null, second = null;
            var d1 = double.PositiveInfinity;
            var d2 = double.PositiveInfinity;
            foreach (var r in Regions)
            {
                var d = Math.Sqrt(Math.Pow(x - r.X, 2) + Math.Pow(z - r.Z, 2));
                if (d < d1) { second = first; d2 = d1; first = r; d1 = d; }
                else if (d < d2) { second = r; d2 = d; }
            }
            var blend = .5 * (1 - Smooth(0, 450, d2 - d1));
            var outc = new double[3];
            for (var i = 0; i < 3; i++)
                outc[i] = first.Color[i] * (1 - blend) + second.Color[i] * blend;
            return outc;
        }

        /* Titik persimpangan: diiterasi 12 kali supaya konvergen, sama seperti JS. */
        public static (double x, double z) Intersection(int laneX, int laneZ)
        {
            double x = laneX * RoadSpacing, z = laneZ * RoadSpacing;
            for (var i = 0; i < 12; i++) { x = RoadX(z, laneX); z = RoadZ(x, laneZ); }
            return (x, z);
        }

        public sealed class Waypoint
        {
            public Region Region;
            public double X, Z;
        }

        public static readonly Waypoint[] Waypoints = BuildWaypoints();

        static Waypoint[] BuildWaypoints()
        {
            var list = new Waypoint[Regions.Length];
            for (var i = 0; i < Regions.Length; i++)
            {
                var r = Regions[i];
                var p = Intersection(JsMath.RoundToInt(r.X / RoadSpacing),
                                     JsMath.RoundToInt(r.Z / RoadSpacing));
                list[i] = new Waypoint { Region = r, X = p.x, Z = p.z };
            }
            return list;
        }

        /* RNG deterministik per chunk (xorshift dengan imul), port persis. */
        public static Func<double> RandomForChunk(int cx, int cz)
        {
            unchecked
            {
                var n = IMul((uint)cx, 73856093u) ^ IMul((uint)cz, 19349663u) ^ 0x51f15eu;
                return () =>
                {
                    n += 0x6D2B79F5u;
                    var t = n;
                    t = IMul(t ^ (t >> 15), t | 1u);
                    t ^= t + IMul(t ^ (t >> 7), t | 61u);
                    return (double)((t ^ (t >> 14))) / 4294967296.0;
                };
            }
        }

        public readonly struct ChunkRef
        {
            public readonly int Cx, Cz;
            public readonly string Key;
            public readonly bool Near;
            public readonly int Distance;

            public ChunkRef(int cx, int cz, bool near, int distance)
            {
                Cx = cx; Cz = cz; Key = cx + "," + cz; Near = near; Distance = distance;
            }
        }

        /* Chunk mana yang harus dimuat, urut dari yang terdekat.

           PENTING — urutan untuk jarak yang SAMA harus mengikuti urutan
           penyisipan (dz luar, dx dalam), karena itulah yang dihasilkan
           JS: sejak V8 7.0 Array.prototype.sort DIJAMIN stabil, dan kode
           aslinya hanya membandingkan `a.distance - b.distance`.
           List.Sort di .NET justru TIDAK stabil, jadi di sini dipakai
           LINQ OrderBy yang stabilitasnya dijamin dokumentasi .NET.
           Kalau suatu saat diganti ke List.Sort, urutannya akan berubah
           dan chunk akan termuat dalam urutan berbeda. */
        public static List<ChunkRef> ChunkPlan(double x, double z, int radius = 3)
        {
            var cx = (int)Math.Floor(x / ChunkSize);
            var cz = (int)Math.Floor(z / ChunkSize);
            var list = new List<ChunkRef>();
            for (var dz = -radius; dz <= radius; dz++)
            for (var dx = -radius; dx <= radius; dx++)
            {
                var tx = cx + dx;
                var tz = cz + dz;
                if (tx * ChunkSize >= WorldSize / 2 || (tx + 1) * ChunkSize <= -WorldSize / 2 ||
                    tz * ChunkSize >= WorldSize / 2 || (tz + 1) * ChunkSize <= -WorldSize / 2) continue;
                list.Add(new ChunkRef(tx, tz,
                    Math.Max(Math.Abs(dx), Math.Abs(dz)) <= 1,
                    dx * dx + dz * dz));
            }
            /* OrderBy LINQ = stable sort: jarak sama tetap mengikuti urutan
               penyisipan, persis seperti Array.prototype.sort di V8. */
            return list.OrderBy(c => c.Distance).ToList();
        }

        /* GLSL terrain (TERRAIN_GLSL di JS) TIDAK di-port ke string.
           Di Unity ia menjadi shader HLSL/Shader Graph di Fase 2/6.
           Persamaannya harus tetap identik dengan TerrainH() di atas —
           itu sebabnya angka-angkanya dipusatkan di kelas ini. */
    }
}
