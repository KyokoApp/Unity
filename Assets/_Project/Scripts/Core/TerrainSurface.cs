using System;

namespace RPG.Core
{
    /* ============================================================
       TERRAIN SURFACE — warna permukaan tanah, murni dari posisi.

       Kenapa kelas ini ada terpisah dari TerrainMesh: pewarnaan adalah
       keputusan VISUAL yang angkanya harus berasal dari pengukuran, dan
       ia harus bisa dites tanpa Unity. Jadi ambangnya ditaruh di sini
       sebagai konstanta bernama dengan asal-usulnya dicatat.

       SEMUA AMBANG DI BAWAH DIUKUR, bukan dikira.
       Sumber angka: _verify/terrain (menjalankan WorldData.cs asli
       pada 361.201 titik sampel tiap 5 m di seluruh dunia 3 km):

           tinggi   min -10,0 | maks 249,3 | rata-rata 40,6
                    p1=-5,0  p25=17,5  p50=33,3  p75=48,0  p95=131,9  p99=215,0
           di bawah permukaan air (y<0)     7,41%
           gradien  p50=0,113  p75=0,192  p90=0,420  p95=0,960  p99=3,801

       Konsekuensi yang dipakai:
         - p5 = -5,0 dan air menutupi 7,41% -> dasar air datar di -5,
           jadi garis pantai ada di sekitar y=0 dan jalur pasir tipis
           saja sudah cukup. Tidak perlu jalur pasir puluhan meter.
         - p95 = 131,9 tapi maks = 249,3 -> salju yang dimulai di 150 m
           hanya menutupi ~1-2% dunia, dan itu memang yang mau dilihat:
           puncak pegunungan utara (ramp `north` ada di -z).
         - gradien p90 = 0,42 -> kalau batu mulai di 0,35 maka ~10%
           dunia berbatu, terkonsentrasi di lereng. Itu proporsi yang
           tepat: batu terlihat sebagai fitur, bukan sebagai default.
       ============================================================ */
    public static class TerrainSurface
    {
        /* ---- jalur pasir / garis pantai ---- */
        public const double ShoreBottom = -3.0;   // di bawah ini: lumpur dasar air
        public const double ShoreTop    =  3.5;   // di atas ini: tidak ada pasir
        public const double SiltTop     = -1.5;   // batas lumpur -> pasir basah

        /* ---- batu (dipicu kemiringan, bukan ketinggian) ---- */
        public const double RockStart = 0.35;     // ~19 derajat
        public const double RockFull  = 0.95;     // ~43 derajat, = p95 terukur

        /* ---- salju ---- */
        public const double SnowStart    = 150.0; // antara p95 (131,9) dan p99 (215,0)
        public const double SnowFull     = 200.0;
        public const double SnowSlopeOff = 1.10;  // lereng terjal tidak menahan salju
        public const double SnowSlopeOn  = 0.45;

        /* ---- jalan ---- */
        public const double RoadCoreEdge = 0.0;   // RoadInfo.Edge <= 0 = badan jalan
        public const double RoadFadeEdge = 24.0;  // bahu jalan memudar sampai sini
        /* CATATAN: TerrainH() meratakan tanah pakai `1 - Smooth(4, 42, Edge)`.
           Jalur warna sengaja lebih sempit (0..24) daripada jalur perataan
           (4..42) supaya warna jalan selalu berada DI DALAM area yang sudah
           datar — tidak ada jalan berwarna yang menggantung di tebing. */

        /* ---- palet ---- */
        public static readonly double[] Sand   = { 0.76, 0.70, 0.52 };
        public static readonly double[] WetSand= { 0.44, 0.40, 0.32 };
        public static readonly double[] Silt   = { 0.22, 0.25, 0.22 };
        public static readonly double[] Rock   = { 0.42, 0.41, 0.40 };
        public static readonly double[] Snow   = { 0.93, 0.95, 0.98 };
        public static readonly double[] Road   = { 0.47, 0.42, 0.34 };
        public static readonly double[] RoadEdge = { 0.38, 0.36, 0.29 };

        static double Clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

        static double Smooth(double a, double b, double v)
        {
            var t = Clamp01((v - a) / (b - a));
            return t * t * (3 - 2 * t);
        }

        /* Gradien magnitudo |∇h| lewat selisih terhingga pusat.
           Epsilon 0,5 m: cukup kecil untuk menangkap kemiringan nyata,
           cukup besar agar tidak dikuasai noise floating point. */
        public const double GradientEpsilon = 0.5;

        public static double GradientAt(double x, double z)
        {
            var e = GradientEpsilon;
            var dx = (WorldData.TerrainH(x + e, z) - WorldData.TerrainH(x - e, z)) / (2 * e);
            var dz = (WorldData.TerrainH(x, z + e) - WorldData.TerrainH(x, z - e)) / (2 * e);
            return Math.Sqrt(dx * dx + dz * dz);
        }

        /* Berapa banyak "batu" yang terlihat di titik ini (0..1). */
        public static double RockAmount(double gradient)
            => Smooth(RockStart, RockFull, gradient);

        /* Berapa banyak salju (0..1). Butuh ketinggian DAN lereng yang
           landai — salju di tebing 75 derajat tidak masuk akal. */
        public static double SnowAmount(double height, double gradient)
        {
            var byHeight = Smooth(SnowStart, SnowFull, height);
            if (byHeight <= 0) return 0;
            var bySlope = 1 - Smooth(SnowSlopeOn, SnowSlopeOff, gradient);
            return byHeight * bySlope;
        }

        /* Berapa kuat warna jalan (0..1). Memakai RoadInfo yang sama dengan
           TerrainH, jadi badan jalan yang terlihat = badan jalan yang datar. */
        public static double RoadAmount(double x, double z)
            => 1 - Smooth(RoadCoreEdge, RoadFadeEdge, WorldData.RoadInfo(x, z).Edge);

        /* Warna akhir. `baseColor` biasanya WorldData.TerrainColor(x,z) —
           campuran warna dua region terdekat. Diterima sebagai parameter
           (bukan dipanggil sendiri) supaya fungsi ini tetap murah untuk
           ribuan verteks dan supaya tes bisa memberi masukan tertentu. */
        public static double[] ColorAt(double x, double z, double height, double gradient,
                                       double[] baseColor)
        {
            var c = new double[3];
            for (var i = 0; i < 3; i++) c[i] = baseColor[i];

            // 1. dasar air / garis pantai
            if (height < ShoreTop)
            {
                var t = Smooth(ShoreBottom, ShoreTop, height);
                var low = height < SiltTop ? Silt : WetSand;
                for (var i = 0; i < 3; i++)
                    c[i] = low[i] * (1 - t) + c[i] * t;

                var sandT = Smooth(SiltTop, ShoreTop, height) * (1 - Smooth(ShoreTop - 1.2, ShoreTop, height));
                for (var i = 0; i < 3; i++)
                    c[i] = c[i] * (1 - sandT) + Sand[i] * sandT;
            }

            // 2. batu di lereng
            var rock = RockAmount(gradient);
            if (rock > 0)
                for (var i = 0; i < 3; i++) c[i] = c[i] * (1 - rock) + Rock[i] * rock;

            // 3. salju di puncak
            var snow = SnowAmount(height, gradient);
            if (snow > 0)
                for (var i = 0; i < 3; i++) c[i] = c[i] * (1 - snow) + Snow[i] * snow;

            // 4. jalan — ditumpuk terakhir supaya tidak ditutupi yang lain
            var road = RoadAmount(x, z);
            if (road > 0)
            {
                // badan jalan lebih terang, bahunya lebih gelap & kehijauan
                var core = Smooth(RoadCoreEdge, RoadCoreEdge + 6.0, WorldData.RoadInfo(x, z).Edge);
                for (var i = 0; i < 3; i++)
                {
                    var roadCol = Road[i] * (1 - core) + RoadEdge[i] * core;
                    c[i] = c[i] * (1 - road) + roadCol * road;
                }
            }

            for (var i = 0; i < 3; i++) c[i] = Clamp01(c[i]);
            return c;
        }

        /* Bentuk ringkas: hitung gradien sendiri. Lebih lambat (4 sampel
           TerrainH ekstra) tapi praktis untuk preview & tes. */
        public static double[] ColorAt(double x, double z)
        {
            var h = WorldData.TerrainH(x, z);
            return ColorAt(x, z, h, GradientAt(x, z), WorldData.TerrainColor(x, z));
        }
    }
}
