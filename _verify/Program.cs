using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using RPG.Core;

/* Dump kanonik dari PORT C#. Harus menghasilkan baris yang identik
   dengan verify/dump-js.mjs yang membaca modul JS asli.
   Selisih sekecil apa pun = port tidak setia. */
static class Program
{
    static readonly List<string> Outp = new List<string>();
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    /* -0 dinormalkan: IEEE -0 == 0, jadi ini murni artefak format string,
       bukan selisih perilaku. Tanpa ini diff penuh noise "-0.000000000". */
    static string Num(double v) => (v == 0 ? 0.0 : v).ToString("G17", Inv);
    static string Bool(bool v) => v ? "true" : "false";
    static void Push(string k, string v) => Outp.Add(k + "=" + v);

    static int Main()
    {
        /* ---------- world-data ---------- */
        var pts = new (double x, double z)[]
        {
            (0,0),(617,-2839),(1500,1500),(-1500,-1500),(800,1050),
            (-1850,1050),(1400,-1350),(150,750),(1468,1468),(-1400,300),
        };
        foreach (var (x, z) in pts)
        {
            Push($"wd.terrainH({Fmt(x)},{Fmt(z)})", Num(WorldData.TerrainH(x, z)));
            Push($"wd.roadHeight({Fmt(x)},{Fmt(z)})", Num(WorldData.RoadHeight(x, z)));
            var ri = WorldData.RoadInfo(x, z);
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).edge", Num(ri.Edge));
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).distance", Num(ri.Distance));
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).halfWidth", Num(ri.HalfWidth));
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).along", Num(ri.Along));
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).lane", ri.Lane.ToString(Inv));
            Push($"wd.roadInfo({Fmt(x)},{Fmt(z)}).axis", ri.Axis.ToString());
            Push($"wd.regionAt({Fmt(x)},{Fmt(z)})", WorldData.RegionAt(x, z).Id);
            Push($"wd.terrainColor({Fmt(x)},{Fmt(z)})",
                 string.Join(",", WorldData.TerrainColor(x, z).Select(Num)));
        }
        foreach (var (lx, lz) in new (int, int)[] { (0,0), (2,-2), (1,1) })
        {
            var it = WorldData.Intersection(lx, lz);
            Push($"wd.intersection({lx},{lz})", $"{Num(it.x)},{Num(it.z)}");
        }
        for (int i = 0; i < WorldData.Waypoints.Length; i++)
        {
            var w = WorldData.Waypoints[i];
            Push($"wd.waypoint[{i}]", $"{w.Region.Id}:{Num(w.X)},{Num(w.Z)}");
        }
        var plan = WorldData.ChunkPlan(100, -200, 3);
        for (int i = 0; i < 8 && i < plan.Count; i++)
            Push($"wd.chunkPlan[{i}]", $"{plan[i].Key}:{Bool(plan[i].Near)}:{plan[i].Distance}");
        Push("wd.chunkPlan.count", plan.Count.ToString(Inv));
        var rnd = WorldData.RandomForChunk(7, -3);
        for (int i = 0; i < 5; i++) Push($"wd.randomForChunk(7,-3)[{i}]", Num(rnd()));
        Push("wd.REGION_COUNT", WorldData.Regions.Length.ToString(Inv));
        Push("wd.WORLD_LIMIT", Num(WorldData.WorldLimit));

        /* ---------- locomotion ---------- */
        var poses = new Locomotion.PoseInput[]
        {
            new Locomotion.PoseInput(0.7, 1.3, 1, 0, 0, false, false, null, 0),
            new Locomotion.PoseInput(2.1, 5.5, 1, 1, 0, false, false, null, 0),
            new Locomotion.PoseInput(3.3, 9.1, 1, 0, 1, true, true, null, 0),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.31, 0),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.85, 1),
            new Locomotion.PoseInput(0.4, 2.2, 1, 0, 0, false, false, 0.50, 2),
        };
        for (int i = 0; i < poses.Length; i++)
        {
            var pose = Locomotion.SamplePose(poses[i]);
            foreach (var k in pose.Keys.OrderBy(s => s, StringComparer.Ordinal))
                Push($"lo.pose[{i}].{k}", $"{Num(pose[k].X)},{Num(pose[k].Y)},{Num(pose[k].Z)}");
            Push($"lo.pose[{i}].__count", pose.Count.ToString(Inv));
        }
        foreach (var (c, t, r, dt) in new (double, double, double, double)[] { (0,1,8,0.016), (5,-2,3,0.033) })
            Push($"lo.damp({Fmt(c)},{Fmt(t)},{Fmt(r)},{Fmt(dt)})", Num(Locomotion.Damp(c, t, r, dt)));
        foreach (var (x, y) in new (double, double)[] { (0,0),(10,5),(40,-30),(0,55),(100,100),(3,4) })
        {
            var a = Locomotion.JoystickAxis(x, y);
            Push($"lo.joystick({Fmt(x)},{Fmt(y)})", $"{Num(a.X)},{Num(a.Y)}");
        }

        /* ---------- quality ---------- */
        var cases = new (string name, RawSettings raw)[]
        {
            ("legacy", new RawSettings { Sensitivity = 1.4, CameraDistance = 6, Quality = "high", Shadows = false, Sound = true }),
            ("empty", new RawSettings()),
            ("nullish", null),
            ("junkgfx", new RawSettings { Gfx = null }),
            ("oob", new RawSettings {
                Sensitivity = 99, CameraDistance = -5, Quality = "ngawur", Fps = 999,
                Gfx = new RawGfx { RenderScale = 9, Shadows = 9, Texture = 9, Bloom = -3 } }),
            ("nan", new RawSettings { Fps = double.NaN, Gfx = new RawGfx { RenderScale = double.NaN } }),
            ("partial", new RawSettings { Quality = "ultra", Gfx = new RawGfx { Shadows = 2 } }),
            ("layout", new RawSettings { Layout = new Dictionary<string, RawPoint> {
                ["a"] = new RawPoint { X = 1.5, Y = -0.2 },
                ["b"] = new RawPoint { X = 0.3, Y = 0.4 },
                ["c"] = null } }),
        };
        foreach (var (name, raw) in cases)
        {
            var s = SettingsNormalizer.Normalize(raw);
            Push($"q.norm[{name}].sensitivity", Num(s.Sensitivity));
            Push($"q.norm[{name}].cameraDistance", Num(s.CameraDistance));
            Push($"q.norm[{name}].quality", s.Quality);
            Push($"q.norm[{name}].shadows", Bool(s.Shadows));
            Push($"q.norm[{name}].sound", Bool(s.Sound));
            Push($"q.norm[{name}].fps", s.Fps.ToString(Inv));
            Push($"q.norm[{name}].custom", Bool(s.Custom));
            Push($"q.norm[{name}].showFps", Bool(s.ShowFps));
            Push($"q.norm[{name}].stickShape", s.StickShape);
            Push($"q.norm[{name}].buttonTheme", s.ButtonTheme);
            Push($"q.norm[{name}].buttonScale", Num(s.ButtonScale));
            var g = s.Gfx;
            Push($"q.norm[{name}].gfx", string.Join(",", new[] {
                Num(g.RenderScale), Num(g.Shadows), Num(g.Grass), Num(g.Particles), Num(g.Water),
                Num(g.View), Num(g.Detail), Num(g.Texture), Num(g.Bloom), Num(g.MotionBlur),
                Num(g.Volumetric), Bool(g.Adaptive) }));
            var lay = s.Layout.Keys.OrderBy(k => k, StringComparer.Ordinal)
                .Select(k => $"{k}:{Num(s.Layout[k].x)},{Num(s.Layout[k].y)}");
            var layStr = string.Join("|", lay);
            Push($"q.norm[{name}].layout", string.IsNullOrEmpty(layStr) ? "(kosong)" : layStr);
        }

        var s0 = SettingsNormalizer.Normalize(new RawSettings());
        foreach (var id in QualityPresets.PresetIds)
        {
            var s = QualityPresets.ApplyPreset(s0, id);
            Push($"q.applyPreset({id})",
                 $"{s.Quality}:{s.Fps.ToString(Inv)}:{Bool(s.Custom)}:{Bool(s.Shadows)}:" +
                 $"{Num(s.Gfx.RenderScale)}:{s.Gfx.Shadows}:{s.Gfx.MotionBlur}:{Bool(s.Gfx.Adaptive)}");
            Push($"q.detectPreset({id})", QualityPresets.DetectPreset(s.Gfx));
            var r1 = GfxResolver.Resolve(s, false);
            var r2 = GfxResolver.Resolve(s, true);
            foreach (var (k, sel) in ResolveKeys())
            {
                Push($"q.resolve[{id}].desk.{k}", sel(r1));
                Push($"q.resolve[{id}].touch.{k}", sel(r2));
            }
        }

        var mixed = QualityPresets.SetGfx(QualityPresets.ApplyPreset(s0, "high"), "shadows", 0);
        Push("q.setGfx(shadows,0)",
             $"{mixed.Quality}:{Bool(mixed.Custom)}:{mixed.Gfx.Shadows}:{QualityPresets.DetectPreset(mixed.Gfx)}");
        var scaled = QualityPresets.SetGfx(QualityPresets.ApplyPreset(s0, "low"), "renderScale", 0.93);
        Push("q.setGfx(renderScale,0.93)", $"{scaled.Quality}:{Num(scaled.Gfx.RenderScale)}");
        var clamped = QualityPresets.SetGfx(QualityPresets.ApplyPreset(s0, "low"), "bloom", 99);
        Push("q.setGfx(bloom,99)", clamped.Gfx.Bloom.ToString(Inv));
        var adaptive = QualityPresets.SetGfx(QualityPresets.ApplyPreset(s0, "low"), "adaptive", false);
        Push("q.setGfx(adaptive,false)", $"{Bool(adaptive.Gfx.Adaptive)}:{adaptive.Quality}");
        var unknown = QualityPresets.SetGfx(s0, "ngawur", 3);
        Push("q.setGfx(unknown)", $"{unknown.Quality}:{Bool(unknown.Custom)}");
        foreach (var f in QualityPresets.FpsChoices)
            Push($"q.frameInterval({f})", Num(QualityPresets.FrameInterval(f)));
        Push("q.frameInterval(50)", Num(QualityPresets.FrameInterval(50)));
        Push("q.frameInterval(0)", Num(QualityPresets.FrameInterval(0)));

        var ar = new AdaptiveResolution(0.6, 1, 1);
        for (int i = 0; i < 25; i++) Push($"q.adaptive.bad[{i}]", Num(ar.Update(40, 1000.0 / 45)));
        for (int i = 0; i < 160; i++) Push($"q.adaptive.good[{i}]", Num(ar.Update(5, 1000.0 / 45)));
        Push("q.adaptive.invalid", Num(ar.Update(double.NaN, 1000.0 / 45)));
        Push("q.adaptive.zerotarget", Num(ar.Update(40, 0)));


        /* ---------- world-scatter: keputusan sebar properti + orb ----------
           Harus mengonsumsi RNG dalam urutan yang sama persis dengan JS.
           Penjumlahan juga harus berurutan sama — float tidak asosiatif. */
        var scatterCases = new (int cx, int cz, bool near)[]
        {
            (0,0,true),(0,0,false),(2,-3,true),(-4,5,true),(5,5,false),(-2,-2,true),
        };
        foreach (var (cx, cz, near) in scatterCases)
        {
            var r = WorldScatter.Build(cx, cz, near, 40, 8);
            var tag = $"sc[{cx},{cx.ToString(Inv)},{(near ? "near" : "far")}]";
            tag = $"sc[{cx},{cz},{(near ? "near" : "far")}]";
            Push($"{tag}.count", Num(r.Props.Count));
            double sx = 0, sy = 0, sz = 0, syaw = 0;
            foreach (var p in r.Props) { sx += p.X; sy += p.Y; sz += p.Z; syaw += p.Yaw; }
            Push($"{tag}.sumX", Num(sx));
            Push($"{tag}.sumY", Num(sy));
            Push($"{tag}.sumZ", Num(sz));
            Push($"{tag}.sumYaw", Num(syaw));
            Push($"{tag}.colliders", Num(r.Colliders.Count));
            double sr = 0;
            foreach (var c in r.Colliders) sr += c.R;
            Push($"{tag}.sumR", Num(sr));
            var n = Math.Min(3, r.Props.Count);
            for (var i = 0; i < n; i++)
            {
                var p = r.Props[i];
                var kind = p.Kind.ToString().ToLower(Inv);
                var fol = p.HasFoliage ? p.Foliage.ToString(Inv) : "";
                Push($"{tag}.p{i}", string.Join("|", kind, Num(p.X), Num(p.Y), Num(p.Z),
                                                 Num(p.Sx), Num(p.Sy), Num(p.Sz), Num(p.Yaw), fol));
            }
        }
        /* Sapuan seluruh dunia — lihat catatan di dump-js.mjs. */
        for (var gx = -6; gx <= 5; gx++)
        for (var gz = -6; gz <= 5; gz++)
        {
            var gr = WorldScatter.Build(gx, gz, true, 40, 8);
            var gtag = $"grid[{gx},{gz}]";
            Push($"{gtag}.count", Num(gr.Props.Count));
            double gsy = 0, gsyaw = 0;
            foreach (var p in gr.Props) { gsy += p.Y; gsyaw += p.Yaw; }
            Push($"{gtag}.sumY", Num(gsy));
            Push($"{gtag}.sumYaw", Num(gsyaw));
            Push($"{gtag}.colliders", Num(gr.Colliders.Count));
            double gsr = 0;
            foreach (var c in gr.Colliders) gsr += c.R;
            Push($"{gtag}.sumR", Num(gsr));
            int kTrunk = 0, kLeaf = 0, kPine = 0, kRock = 0;
            foreach (var p in gr.Props)
            {
                if (p.Kind == PropKind.Trunk) kTrunk++;
                else if (p.Kind == PropKind.Leaf) kLeaf++;
                else if (p.Kind == PropKind.Pine) kPine++;
                else kRock++;
            }
            Push($"{gtag}.kinds", $"{kTrunk},{kLeaf},{kPine},{kRock}");
        }

        var orbs = WorldScatter.PlaceOrbs();
        Push("orb.count", Num(orbs.Count));
        for (var i = 0; i < orbs.Count; i++)
            Push($"orb[{i}]", string.Join(",", Num(orbs[i].X), Num(orbs[i].Y), Num(orbs[i].Z)));
        Push("orb.bob.t0.7.x123.4", Num(WorldScatter.OrbY(orbs[0].BaseY, 123.4, 0.7)));
        Push("orb.bob.t12.5.x-900", Num(WorldScatter.OrbY(orbs[5].BaseY, -900, 12.5)));

        Console.Write(string.Join("\n", Outp) + "\n");
        return 0;
    }

    /* JS memakai template literal untuk angka bulat di beberapa tempat
       (String(5) -> "5"), jadi Fmt() meniru itu, bukan F9. */
    static string Fmt(double v) =>
        v == Math.Floor(v) && Math.Abs(v) < 1e15 ? ((long)v).ToString(Inv) : v.ToString("R", Inv);

    static (string key, Func<GfxResolver.Resolved, string> get)[] ResolveKeys() => new (string, Func<GfxResolver.Resolved, string>)[]
    {
        ("dprCap",               r => Num(r.DprCap)),
        ("renderScale",          r => Num(r.RenderScale)),
        ("adaptive",             r => Bool(r.Adaptive)),
        ("shadowsEnabled",       r => Bool(r.ShadowsEnabled)),
        ("shadowMapSize",        r => Num(r.ShadowMapSize)),
        ("shadowRefreshFrames",  r => Num(r.ShadowRefreshFrames)),
        ("grassCount",           r => Num(r.GrassCount)),
        ("grassEnabled",         r => Bool(r.GrassEnabled)),
        ("dustCount",            r => Num(r.DustCount)),
        ("butterflyCount",       r => Num(r.ButterflyCount)),
        ("birdCount",            r => Num(r.BirdCount)),
        ("particlesEnabled",     r => Bool(r.ParticlesEnabled)),
        ("waterSegments",        r => Num(r.WaterSegments)),
        ("waterWaves",           r => Bool(r.WaterWaves)),
        ("waterOpacity",         r => Num(r.WaterOpacity)),
        ("fogNear",              r => Num(r.FogNear)),
        ("fogFar",               r => Num(r.FogFar)),
        ("orbCullDistance",      r => Num(r.OrbCullDistance)),
        ("streamRadius",         r => Num(r.StreamRadius)),
        ("terrainSegmentsNear",  r => Num(r.TerrainSegmentsNear)),
        ("propsNear",            r => Num(r.PropsNear)),
        ("propsFar",             r => Num(r.PropsFar)),
        ("roadProps",            r => Bool(r.RoadProps)),
        ("roadPropSpacing",      r => Num(r.RoadPropSpacing)),
        ("textureSize",          r => Num(r.TextureSize)),
        ("anisotropy",           r => Num(r.Anisotropy)),
        ("bloomLevel",           r => Num(r.BloomLevel)),
        ("motionBlurLevel",      r => Num(r.MotionBlurLevel)),
        ("volumetricLevel",      r => Num(r.VolumetricLevel)),
        ("postEnabled",          r => Bool(r.PostEnabled)),
    };
}
