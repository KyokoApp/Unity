using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using NUnit.Framework;
using RPG.Core;

namespace RPG.Tests
{
    /* ============================================================
       TES PARITAS — mengunci port C# agar tetap IDENTIK dengan game
       three.js aslinya (KyokoApp/rpg).

       Semua nilai di Golden diambil dari MENJALANKAN modul JS asli
       (game/world-data.mjs, game/locomotion.mjs, game/quality.mjs),
       bukan ditulis tangan. Verifikasi penuh 1.779 baris / 2.650 nilai
       numerik sudah dijalankan di luar Unity dengan selisih maksimum
       7,1e-15 (dari perbedaan Math.Sin V8 vs .NET). Nilai di bawah
       diambil pada konstanta dunia 3 km.

       Kalau tes ini merah, port-nya MELIPAT dari aslinya — jangan
       perbarui angkanya tanpa memeriksa kenapa berubah.
       ============================================================ */
    [TestFixture]
    public class CoreParityTests
    {
        const double Tol = 1e-9;
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

        static string Num(double v) => (v == 0 ? 0.0 : v).ToString("G17", Inv);
        static string Bool(bool v) => v ? "true" : "false";

        static (string key, string expected)[] Golden => new (string, string)[]
        {
            ("wd.terrainH(617,-2839)", "177.67557748394194"),
            ("wd.terrainH(-1500,-1500)", "163.92125517255519"),
            ("wd.terrainH(800,1050)", "27.281483641887039"),
            ("wd.roadHeight(150,750)", "35.657216309475729"),
            ("wd.roadInfo(617,-2839).edge", "101.61361395091262"),
            ("wd.roadInfo(617,-2839).lane", "-4"),
            ("wd.roadInfo(617,-2839).axis", "x"),
            ("wd.terrainColor(617,-2839)", "0.58856092055678100,0.52827332565163676,0.37079143844789553"),
            ("wd.WORLD_LIMIT", "1468"),
            ("wd.chunkPlan[0]", "0,-1:true:0"),
            ("wd.chunkPlan[4]", "0,0:true:1"),
            ("wd.chunkPlan.count", "49"),
            ("wd.randomForChunk(7,-3)[0]", "0.37886407412588596"),
            ("wd.randomForChunk(7,-3)[4]", "0.64732959703542292"),
            ("wd.waypoint[1]", "frost:-806.98583254598111,-808.47665074536644"),
            ("wd.intersection(2,-2)", "1430.7389634948333,-1458.7941608676585"),
            ("lo.damp(0,1,8,0.016)", "0.12014662085535621"),
            ("lo.joystick(40,-30)", "0.71543340380549680,-0.53657505285412255"),
            ("lo.pose[4].ARMR", "-0.55566406250000000,0.28476562500000002,-0.045976562499999984"),
            ("lo.pose[5].CHEST", "0.10000000000000001,-0.55000000000000004,0"),
            ("lo.pose[2].KNEEL", "0.26000000000000001,0.0000000000000000,0"),
            ("lo.pose[0].__count", "25"),
            ("q.norm[legacy].gfx", "0.84999999999999998,1.0000000000000000,1.0000000000000000,1.0000000000000000,2.0000000000000000,2.0000000000000000,1.0000000000000000,1.0000000000000000,1.0000000000000000,0.0000000000000000,0.0000000000000000,true"),
            ("q.norm[legacy].fps", "60"),
            ("q.norm[legacy].quality", "high"),
            ("q.norm[legacy].shadows", "false"),
            ("q.norm[nullish].gfx", "0.84999999999999998,1.0000000000000000,1.0000000000000000,1.0000000000000000,2.0000000000000000,2.0000000000000000,1.0000000000000000,1.0000000000000000,1.0000000000000000,0.0000000000000000,0.0000000000000000,true"),
            ("q.norm[oob].gfx", "1.5000000000000000,3.0000000000000000,1.0000000000000000,1.0000000000000000,2.0000000000000000,2.0000000000000000,1.0000000000000000,2.0000000000000000,0.0000000000000000,0.0000000000000000,0.0000000000000000,true"),
            ("q.norm[nan].fps", "60"),
            ("q.norm[layout].layout", "a:1.0000000000000000,0.0000000000000000|b:0.29999999999999999,0.40000000000000002"),
            ("q.applyPreset(ultra)", "ultra:60:false:true:1.2500000000000000:3:2:false"),
            ("q.applyPreset(low)", "low:30:false:false:0.69999999999999996:0:0:true"),
            ("q.detectPreset(high)", "high"),
            ("q.resolve[balanced].desk.dustCount", "48"),
            ("q.resolve[balanced].touch.dustCount", "23"),
            ("q.resolve[balanced].desk.birdCount", "9"),
            ("q.resolve[high].desk.fogFar", "1283"),
            ("q.resolve[ultra].desk.shadowMapSize", "2048"),
            ("q.resolve[low].touch.grassCount", "0"),
            ("q.setGfx(shadows,0)", "custom:true:0:custom"),
            ("q.setGfx(bloom,99)", "3"),
            ("q.frameInterval(45)", "22.222222222222221"),
            ("q.frameInterval(50)", "0"),
            ("q.adaptive.bad[20]", "0.90000000000000002"),
            ("q.adaptive.good[150]", "0.95000000000000007"),
            ("sc[0,0,near].count", "45"),
            ("sc[0,0,near].sumYaw", "66.43292048395611"),
            ("sc[0,0,near].colliders", "25"),
            ("sc[0,0,near].p0", "trunk|131.96983689069748|47.143383892287567|83.703787922859192|0.89240424070740121|0.89240424070740121|0.89240424070740121|0.0000000000000000|"),
            ("sc[0,0,near].p1", "leaf|131.96983689069748|51.159202975470876|83.703787922859192|0.89240424070740121|0.75854360460129100|0.89240424070740121|1.4869230561144651|7510867"),
            ("sc[0,0,far].count", "8"),
            ("sc[2,-3,near].count", "31"),
            ("sc[2,-3,near].p0", "rock|97.390284717082977|43.399361792193332|210.72636044025421|2.4672167093958706|1.8504125320469029|2.0971342029864899|2.3694954543095084|"),
            ("sc[2,-3,near].p1", "rock|41.077250421047211|78.272678055208488|8.9996978640556335|1.5637773974332960|1.1728330480749720|1.3292107878183015|4.8339899713173509|"),
            ("sc[-4,5,near].count", "54"),
            ("sc[-4,5,near].colliders", "32"),
            ("orb.count", "12"),
            ("orb[0]", "-18.000000000000000,28.165035704991304,-25"),
            ("orb[7]", "18.000000000000000,29.799635677847569,-80"),
            ("orb[11]", "-680.93933510670649,12.963284106869203,614.87509474666626"),
            ("orb.bob.t0.7.x123.4", "27.964797223139769"),
            ("orb.bob.t12.5.x-900", "36.24343056704403"),
            ("grid[0,0].count", "45"),
            ("grid[0,0].kinds", "20,20,0,5"),
            ("grid[-6,5].kinds", "24,24,0,4"),
            ("grid[-6,5].count", "52"),
            ("grid[-5,-3].count", "73"),
            ("grid[3,-6].sumY", "6629.240209557146"),
            ("grid[5,5].kinds", "26,26,0,13"),
            ("grid[-2,-2].colliders", "40"),
            ("grid[4,1].sumYaw", "141.72804334382528"),
        };

        static readonly Locomotion.PoseInput[] Poses =
        {
            new Locomotion.PoseInput(0.7, 1.3, 1, 0, 0, false, false, null, 0),
            new Locomotion.PoseInput(2.1, 5.5, 1, 1, 0, false, false, null, 0),
            new Locomotion.PoseInput(3.3, 9.1, 1, 0, 1, true, true, null, 0),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.31, 0),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.85, 1),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.50, 2),
        };

        static string GfxStr(GfxSettings g) => string.Join(",", new[]
        {
            Num(g.RenderScale), Num(g.Shadows), Num(g.Grass), Num(g.Particles), Num(g.Water),
            Num(g.View), Num(g.Detail), Num(g.Texture), Num(g.Bloom), Num(g.MotionBlur),
            Num(g.Volumetric), Bool(g.Adaptive),
        });

        /* Menghitung ulang semua kunci Golden dari kode C# yang dikirim. */
        static Dictionary<string, string> Compute()
        {
            var d = new Dictionary<string, string>();

            d["wd.terrainH(617,-2839)"] = Num(WorldData.TerrainH(617, -2839));
            d["wd.terrainH(-1500,-1500)"] = Num(WorldData.TerrainH(-1500, -1500));
            d["wd.terrainH(800,1050)"] = Num(WorldData.TerrainH(800, 1050));
            d["wd.roadHeight(150,750)"] = Num(WorldData.RoadHeight(150, 750));
            var ri = WorldData.RoadInfo(617, -2839);
            d["wd.roadInfo(617,-2839).edge"] = Num(ri.Edge);
            d["wd.roadInfo(617,-2839).lane"] = ri.Lane.ToString(Inv);
            d["wd.roadInfo(617,-2839).axis"] = ri.Axis.ToString();
            d["wd.terrainColor(617,-2839)"] = string.Join(",", WorldData.TerrainColor(617, -2839).Select(Num));
            d["wd.WORLD_LIMIT"] = Num(WorldData.WorldLimit);

            /* world-scatter: keputusan sebar properti per chunk + orb.
               Urutan konsumsi RNG adalah kontrak — lihat WorldScatter.cs.
               Kalau angka di bawah berubah, hampir pasti urutannya geser. */
            foreach (var scCase in new (int cx, int cz, bool near)[] { (0, 0, true), (0, 0, false), (2, -3, true), (-4, 5, true) })
            {
                var sc = WorldScatter.Build(scCase.cx, scCase.cz, scCase.near, 40, 8);
                var tag = $"sc[{scCase.cx},{scCase.cz},{(scCase.near ? "near" : "far")}]";
                d[$"{tag}.count"] = Num(sc.Props.Count);
                double syaw = 0;
                foreach (var p in sc.Props) syaw += p.Yaw;
                d[$"{tag}.sumYaw"] = Num(syaw);
                d[$"{tag}.colliders"] = Num(sc.Colliders.Count);
                for (var i = 0; i < 2 && i < sc.Props.Count; i++)
                {
                    var p = sc.Props[i];
                    d[$"{tag}.p{i}"] = string.Join("|", p.Kind.ToString().ToLower(Inv),
                        Num(p.X), Num(p.Y), Num(p.Z), Num(p.Sx), Num(p.Sy), Num(p.Sz), Num(p.Yaw),
                        p.HasFoliage ? p.Foliage.ToString(Inv) : "");
                }
            }
            /* Sapuan grid 12x12 seluruh dunia. Enam chunk saja TIDAK CUKUP:
               mutasi ambang .22->.23 pernah lolos karena dari 140 undian tidak
               ada satu pun jatuh di pita 1% itu. Grid ini ~5.760 undian. */
            for (var gx = -6; gx <= 5; gx++)
            for (var gz = -6; gz <= 5; gz++)
            {
                var gr = WorldScatter.Build(gx, gz, true, 40, 8);
                var gtag = $"grid[{gx},{gz}]";
                d[$"{gtag}.count"] = Num(gr.Props.Count);
                double gsy = 0, gsyaw = 0;
                foreach (var p in gr.Props) { gsy += p.Y; gsyaw += p.Yaw; }
                d[$"{gtag}.sumY"] = Num(gsy);
                d[$"{gtag}.sumYaw"] = Num(gsyaw);
                d[$"{gtag}.colliders"] = Num(gr.Colliders.Count);
                double gsr = 0;
                foreach (var c in gr.Colliders) gsr += c.R;
                d[$"{gtag}.sumR"] = Num(gsr);
                int kT = 0, kL = 0, kP = 0, kR = 0;
                foreach (var p in gr.Props)
                {
                    if (p.Kind == PropKind.Trunk) kT++;
                    else if (p.Kind == PropKind.Leaf) kL++;
                    else if (p.Kind == PropKind.Pine) kP++;
                    else kR++;
                }
                d[$"{gtag}.kinds"] = $"{kT},{kL},{kP},{kR}";
            }
            var orbs = WorldScatter.PlaceOrbs();
            d["orb.count"] = Num(orbs.Count);
            foreach (var oi in new[] { 0, 7, 11 })
                d[$"orb[{oi}]"] = string.Join(",", Num(orbs[oi].X), Num(orbs[oi].Y), Num(orbs[oi].Z));
            d["orb.bob.t0.7.x123.4"] = Num(WorldScatter.OrbY(orbs[0].BaseY, 123.4, 0.7));
            d["orb.bob.t12.5.x-900"] = Num(WorldScatter.OrbY(orbs[5].BaseY, -900, 12.5));

            var plan = WorldData.ChunkPlan(100, -200, 3);
            d["wd.chunkPlan[0]"] = $"{plan[0].Key}:{Bool(plan[0].Near)}:{plan[0].Distance}";
            d["wd.chunkPlan[4]"] = $"{plan[4].Key}:{Bool(plan[4].Near)}:{plan[4].Distance}";
            d["wd.chunkPlan.count"] = plan.Count.ToString(Inv);

            var rnd = WorldData.RandomForChunk(7, -3);
            var rvals = Enumerable.Range(0, 5).Select(_ => rnd()).ToArray();
            d["wd.randomForChunk(7,-3)[0]"] = Num(rvals[0]);
            d["wd.randomForChunk(7,-3)[4]"] = Num(rvals[4]);

            var w1 = WorldData.Waypoints[1];
            d["wd.waypoint[1]"] = $"{w1.Region.Id}:{Num(w1.X)},{Num(w1.Z)}";
            var it = WorldData.Intersection(2, -2);
            d["wd.intersection(2,-2)"] = $"{Num(it.x)},{Num(it.z)}";

            d["lo.damp(0,1,8,0.016)"] = Num(Locomotion.Damp(0, 1, 8, 0.016));
            var ax = Locomotion.JoystickAxis(40, -30);
            d["lo.joystick(40,-30)"] = $"{Num(ax.X)},{Num(ax.Y)}";
            var p4 = Locomotion.SamplePose(Poses[4]);
            var p5 = Locomotion.SamplePose(Poses[5]);
            var p2 = Locomotion.SamplePose(Poses[2]);
            var p0 = Locomotion.SamplePose(Poses[0]);
            d["lo.pose[4].ARMR"] = $"{Num(p4["ARMR"].X)},{Num(p4["ARMR"].Y)},{Num(p4["ARMR"].Z)}";
            d["lo.pose[5].CHEST"] = $"{Num(p5["CHEST"].X)},{Num(p5["CHEST"].Y)},{Num(p5["CHEST"].Z)}";
            d["lo.pose[2].KNEEL"] = $"{Num(p2["KNEEL"].X)},{Num(p2["KNEEL"].Y)},{Num(p2["KNEEL"].Z)}";
            d["lo.pose[0].__count"] = p0.Count.ToString(Inv);

            var legacy = SettingsNormalizer.Normalize(new RawSettings
            { Sensitivity = 1.4, CameraDistance = 6, Quality = "high", Shadows = false, Sound = true });
            d["q.norm[legacy].gfx"] = GfxStr(legacy.Gfx);
            d["q.norm[legacy].fps"] = legacy.Fps.ToString(Inv);
            d["q.norm[legacy].quality"] = legacy.Quality;
            d["q.norm[legacy].shadows"] = Bool(legacy.Shadows);
            d["q.norm[nullish].gfx"] = GfxStr(SettingsNormalizer.Normalize(null).Gfx);
            d["q.norm[oob].gfx"] = GfxStr(SettingsNormalizer.Normalize(new RawSettings
            {
                Sensitivity = 99, CameraDistance = -5, Quality = "ngawur", Fps = 999,
                Gfx = new RawGfx { RenderScale = 9, Shadows = 9, Texture = 9, Bloom = -3 },
            }).Gfx);
            d["q.norm[nan].fps"] = SettingsNormalizer.Normalize(new RawSettings
            { Fps = double.NaN, Gfx = new RawGfx { RenderScale = double.NaN } }).Fps.ToString(Inv);
            var lay = SettingsNormalizer.Normalize(new RawSettings
            {
                Layout = new Dictionary<string, RawPoint>
                {
                    ["a"] = new RawPoint { X = 1.5, Y = -0.2 },
                    ["b"] = new RawPoint { X = 0.3, Y = 0.4 },
                    ["c"] = null,
                },
            });
            d["q.norm[layout].layout"] = string.Join("|", lay.Layout.Keys
                .OrderBy(k => k, StringComparer.Ordinal)
                .Select(k => $"{k}:{Num(lay.Layout[k].x)},{Num(lay.Layout[k].y)}"));

            var s0 = SettingsNormalizer.Normalize(new RawSettings());
            var ultra = QualityPresets.ApplyPreset(s0, "ultra");
            var low = QualityPresets.ApplyPreset(s0, "low");
            var high = QualityPresets.ApplyPreset(s0, "high");
            var bal = QualityPresets.ApplyPreset(s0, "balanced");
            d["q.applyPreset(ultra)"] =
                $"{ultra.Quality}:{ultra.Fps.ToString(Inv)}:{Bool(ultra.Custom)}:{Bool(ultra.Shadows)}:" +
                $"{Num(ultra.Gfx.RenderScale)}:{ultra.Gfx.Shadows}:{ultra.Gfx.MotionBlur}:{Bool(ultra.Gfx.Adaptive)}";
            d["q.applyPreset(low)"] =
                $"{low.Quality}:{low.Fps.ToString(Inv)}:{Bool(low.Custom)}:{Bool(low.Shadows)}:" +
                $"{Num(low.Gfx.RenderScale)}:{low.Gfx.Shadows}:{low.Gfx.MotionBlur}:{Bool(low.Gfx.Adaptive)}";
            d["q.detectPreset(high)"] = QualityPresets.DetectPreset(high.Gfx);

            var balDesk = GfxResolver.Resolve(bal, false);
            var balTouch = GfxResolver.Resolve(bal, true);
            var highDesk = GfxResolver.Resolve(high, false);
            var ultraDesk = GfxResolver.Resolve(ultra, false);
            var lowTouch = GfxResolver.Resolve(low, true);
            d["q.resolve[balanced].desk.dustCount"] = Num(balDesk.DustCount);
            d["q.resolve[balanced].touch.dustCount"] = Num(balTouch.DustCount);
            d["q.resolve[balanced].desk.birdCount"] = Num(balDesk.BirdCount);
            d["q.resolve[high].desk.fogFar"] = Num(highDesk.FogFar);
            d["q.resolve[ultra].desk.shadowMapSize"] = Num(ultraDesk.ShadowMapSize);
            d["q.resolve[low].touch.grassCount"] = Num(lowTouch.GrassCount);

            var mixed = QualityPresets.SetGfx(high, "shadows", 0);
            d["q.setGfx(shadows,0)"] =
                $"{mixed.Quality}:{Bool(mixed.Custom)}:{mixed.Gfx.Shadows}:{QualityPresets.DetectPreset(mixed.Gfx)}";
            d["q.setGfx(bloom,99)"] = QualityPresets.SetGfx(low, "bloom", 99).Gfx.Bloom.ToString(Inv);
            d["q.frameInterval(45)"] = Num(QualityPresets.FrameInterval(45));
            d["q.frameInterval(50)"] = Num(QualityPresets.FrameInterval(50));

            var ar = new AdaptiveResolution(0.6, 1, 1);
            var bad = Enumerable.Range(0, 25).Select(_ => ar.Update(40, 1000.0 / 45)).ToArray();
            var good = Enumerable.Range(0, 160).Select(_ => ar.Update(5, 1000.0 / 45)).ToArray();
            d["q.adaptive.bad[20]"] = Num(bad[20]);
            d["q.adaptive.good[150]"] = Num(good[150]);

            return d;
        }

        [Test]
        public void PortSetaraDenganVersiThreeJs()
        {
            var actual = Compute();
            var gagal = new List<string>();
            foreach (var (key, expected) in Golden)
            {
                if (!actual.TryGetValue(key, out var got))
                {
                    gagal.Add($"{key}: tidak dihitung");
                    continue;
                }
                if (got == expected) continue;

                /* Bandingkan numerik per token supaya selisih format
                   (mis. -0 vs 0) tidak jadi kegagalan palsu. */
                var te = expected.Split(',', '|', ':');
                var tg = got.Split(',', '|', ':');
                if (te.Length != tg.Length) { gagal.Add($"{key}\n      JS = {expected}\n      C# = {got}"); continue; }
                for (int i = 0; i < te.Length; i++)
                {
                    if (double.TryParse(te[i], NumberStyles.Float, Inv, out var a) &&
                        double.TryParse(tg[i], NumberStyles.Float, Inv, out var b))
                    {
                        if (Math.Abs(a - b) > Tol) { gagal.Add($"{key}\n      JS = {expected}\n      C# = {got}"); break; }
                    }
                    else if (te[i] != tg[i]) { gagal.Add($"{key}\n      JS = {expected}\n      C# = {got}"); break; }
                }
            }
            Assert.IsEmpty(gagal, "Port C# menyimpang dari versi three.js:\n  - " + string.Join("\n  - ", gagal));
        }

        /* ============================================================
           INVARIAN — dipertahankan dari tests/quality.test.cjs &
           tests/settings.test.mjs di repo asli, termasuk tes untuk
           insiden produksi 2026-09-15.
           ============================================================ */

        [Test]
        public void SettingLamaTanpaGfxDinormalisasiLengkap()
        {
            /* Bentuk persis yang dikembalikan readSettings versi lama:
               tidak ada gfx/fps/stickShape/buttonTheme/layout. */
            var legacy = SettingsNormalizer.Normalize(new RawSettings
            { Sensitivity = 1.4, CameraDistance = 6, Quality = "high", Shadows = false, Sound = true });

            Assert.IsNotNull(legacy.Gfx, "gfx harus diisi walau masukan tidak punya gfx");
            Assert.IsInstanceOf<double>(legacy.Gfx.RenderScale);
            Assert.AreEqual("high", legacy.Quality);
            Assert.IsFalse(legacy.Shadows);
            /* ekspresi persis yang crash di produksi tidak boleh melempar */
            Assert.DoesNotThrow(() => { var _ = Math.Round((legacy.Gfx.RenderScale == 0 ? 1 : legacy.Gfx.RenderScale) * 100); });
        }

        [Test]
        public void NormalisasiIdempotenDanTahanMasukanRusak()
        {
            var legacy = SettingsNormalizer.Normalize(new RawSettings { Quality = "high" });
            /* idempoten: hasil normalisasi yang dinormalisasi lagi harus sama */
            var lagi = SettingsNormalizer.Normalize(NormalizeBack(legacy));
            Assert.IsTrue(lagi.Gfx.SameValues(legacy.Gfx), "harus idempoten");
            Assert.AreEqual(legacy.Quality, lagi.Quality);
            Assert.AreEqual(legacy.Fps, lagi.Fps);
            foreach (var raw in new RawSettings[] { null, new RawSettings(), new RawSettings { Gfx = null } })
                Assert.IsNotNull(SettingsNormalizer.Normalize(raw).Gfx);
        }

        static RawSettings NormalizeBack(GameSettings s) => new RawSettings
        {
            Sensitivity = s.Sensitivity, CameraDistance = s.CameraDistance, Quality = s.Quality,
            Shadows = s.Shadows, Sound = s.Sound, Fps = s.Fps, Custom = s.Custom, ShowFps = s.ShowFps,
            StickShape = s.StickShape, ButtonTheme = s.ButtonTheme, ButtonScale = s.ButtonScale,
            Gfx = new RawGfx
            {
                RenderScale = s.Gfx.RenderScale, Shadows = s.Gfx.Shadows, Grass = s.Gfx.Grass,
                Particles = s.Gfx.Particles, Water = s.Gfx.Water, View = s.Gfx.View,
                Detail = s.Gfx.Detail, Texture = s.Gfx.Texture, Bloom = s.Gfx.Bloom,
                MotionBlur = s.Gfx.MotionBlur, Volumetric = s.Gfx.Volumetric, Adaptive = s.Gfx.Adaptive,
            },
        };

        [Test]
        public void PembulatanMengikutiJsBukanBankersRounding()
        {
            /* Bug nyata yang ditangkap uji paritas: Math.Round .NET default
               membulatkan 22.5 -> 22, JS Math.round -> 23. */
            Assert.AreEqual(23, JsMath.RoundToInt(22.5));
            Assert.AreEqual(22, JsMath.RoundToInt(22.4));
            Assert.AreEqual(-22, JsMath.RoundToInt(-22.5), "JS membulatkan setengah ke +Infinity");
            Assert.AreEqual(23, JsMath.RoundToInt(22.500000001));
        }

        [Test]
        public void TingkatNolBenarBenarMematikanFitur()
        {
            var low = GfxResolver.Resolve(QualityPresets.ApplyPreset(
                SettingsNormalizer.Normalize(new RawSettings()), "low"), true);
            Assert.AreEqual(0, low.GrassCount, "grass 0 harus 0 draw call");
            Assert.IsFalse(low.GrassEnabled);
            Assert.IsFalse(low.ParticlesEnabled);
            Assert.IsFalse(low.PostEnabled);
            Assert.AreEqual(0, low.ButterflyCount);
            Assert.AreEqual(0, low.BirdCount);
            Assert.AreEqual(0, low.DustCount);
        }

        [Test]
        public void UbahSatuOpsiMenjatuhkanPresetKeCustom()
        {
            var s = QualityPresets.ApplyPreset(SettingsNormalizer.Normalize(new RawSettings()), "high");
            Assert.AreEqual("high", s.Quality);
            var t = QualityPresets.SetGfx(s, "shadows", 0);
            Assert.AreEqual("custom", t.Quality);
            Assert.IsTrue(t.Custom);
            Assert.AreEqual("custom", QualityPresets.DetectPreset(t.Gfx));
        }

        [Test]
        public void ChunkPlanStabilSepertiV8()
        {
            var plan = WorldData.ChunkPlan(100, -200, 3);
            Assert.AreEqual(49, plan.Count, "7x7 chunk");
            for (int i = 1; i < plan.Count; i++)
                Assert.GreaterOrEqual(plan[i].Distance, plan[i - 1].Distance, "harus urut naik");
            /* urutan untuk jarak sama harus mengikuti penyisipan (dz luar, dx dalam) */
            Assert.AreEqual("0,-1", plan[0].Key);
            Assert.AreEqual("0,0", plan[4].Key);
        }
    }
}
