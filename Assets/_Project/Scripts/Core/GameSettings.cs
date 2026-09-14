using System;
using System.Collections.Generic;

namespace RPG.Core
{
    /* ============================================================
       GAME SETTINGS — port dari game/quality.mjs (bagian data).

       Di JS, normalizeSettings() menerima objek bentuk APA PUN karena
       storage bisa berisi keluaran readSettings versi lama (insiden
       produksi 2026-09-15). C# bertipe statis, jadi bentuk "apa pun"
       itu dimodelkan sebagai RawSettings dengan SEMUA field nullable:
       field yang hilang di JSON menjadi null, dan normalisasi mengisi
       default yang sama persis seperti JS.

       Kelas ini PURE: tidak ada UnityEngine, tidak ada PlayerPrefs.
       Adapter storage (PlayerPrefs/JSON) hidup di assembly Runtime.
       ============================================================ */

    /* ---- bentuk mentah dari storage; semuanya boleh tidak ada ---- */
    public sealed class RawSettings
    {
        public double? Sensitivity;
        public double? CameraDistance;
        public string Quality;
        public bool? Shadows;
        public bool? Sound;
        public double? Fps;
        public bool? Custom;
        public bool? ShowFps;
        public RawGfx Gfx;
        public string StickShape;
        public string ButtonTheme;
        public double? ButtonScale;
        public Dictionary<string, RawPoint> Layout;
        /* CarCamera sengaja TIDAK ada: game ini tanpa mobil.
           Ini penyimpangan dari game/world-data.mjs yang masih punya field itu. */
    }

    public sealed class RawGfx
    {
        public double? RenderScale;
        public double? Shadows;
        public double? Grass;
        public double? Particles;
        public double? Water;
        public double? View;
        public double? Detail;
        public double? Texture;
        public double? Bloom;
        public double? MotionBlur;
        public double? Volumetric;
        public bool? Adaptive;
    }

    public sealed class RawPoint { public double? X, Y; }

    /* ---- bentuk ternormalisasi: dijamin lengkap ---- */
    public sealed class GfxSettings
    {
        public double RenderScale;
        public int Shadows, Grass, Particles, Water, View, Detail, Texture;
        public int Bloom, MotionBlur, Volumetric;
        public bool Adaptive;

        public GfxSettings Clone() => (GfxSettings)MemberwiseClone();

        /* Kesetaraan nilai — JS membandingkan per kunci di detectPreset(). */
        public bool SameValues(GfxSettings o) =>
            RenderScale == o.RenderScale && Shadows == o.Shadows && Grass == o.Grass &&
            Particles == o.Particles && Water == o.Water && View == o.View &&
            Detail == o.Detail && Texture == o.Texture && Bloom == o.Bloom &&
            MotionBlur == o.MotionBlur && Volumetric == o.Volumetric && Adaptive == o.Adaptive;
    }

    public sealed class GameSettings
    {
        public double Sensitivity;
        public double CameraDistance;
        public string Quality;
        public bool Shadows;
        public bool Sound;
        public int Fps;
        public bool Custom;
        public bool ShowFps;
        public GfxSettings Gfx;
        public string StickShape;
        public string ButtonTheme;
        public double ButtonScale;
        /* Fraksi 0..1 terhadap viewport, bukan piksel — tetap pas setelah
           ponsel diputar. */
        public Dictionary<string, (double x, double y)> Layout;

        public GameSettings Clone() => new GameSettings
        {
            Sensitivity = Sensitivity, CameraDistance = CameraDistance, Quality = Quality,
            Shadows = Shadows, Sound = Sound, Fps = Fps, Custom = Custom, ShowFps = ShowFps,
            Gfx = Gfx.Clone(), StickShape = StickShape, ButtonTheme = ButtonTheme,
            ButtonScale = ButtonScale,
            Layout = new Dictionary<string, (double, double)>(Layout),
        };
    }

    public static class SettingsNormalizer
    {
        /* ---- helper clamp, semantiknya harus sama dengan JS ----
           JS: Number.isFinite(v) ? ... : fallback.
           NaN dan tak-hingga di JSON tidak valid, tapi field yang HILANG
           (null) harus jatuh ke default — bukan ke 0. */
        static double ClampNum(double? v, double a, double b, double d)
            => v.HasValue && !double.IsNaN(v.Value) && !double.IsInfinity(v.Value)
                ? Math.Max(a, Math.Min(b, v.Value)) : d;

        static int ClampInt(double? v, int a, int b)
            => v.HasValue && !double.IsNaN(v.Value) && !double.IsInfinity(v.Value)
                ? Math.Max(a, Math.Min(b, JsMath.RoundToInt(v.Value))) : a;

        /* Tingkat yang hilang/rusak jatuh ke DEFAULT PRESET, bukan 0.
           Tanpa ini, setting lama tanpa field baru mematikan semua fitur
           secara diam-diam. */
        static int Level(double? v, int max, int d)
            => v.HasValue && !double.IsNaN(v.Value) && !double.IsInfinity(v.Value)
                ? Math.Max(0, Math.Min(max, JsMath.RoundToInt(v.Value))) : d;

        static string Pick(string v, string[] list, string d)
            => v != null && Array.IndexOf(list, v) >= 0 ? v : d;

        static int PickFps(double? v, int[] list, int d)
        {
            if (!v.HasValue || double.IsNaN(v.Value) || double.IsInfinity(v.Value)) return d;
            var iv = JsMath.RoundToInt(v.Value);
            return Array.IndexOf(list, iv) >= 0 ? iv : d;
        }

        public static GfxSettings NormalizeGfx(RawGfx gfx)
        {
            var b = QualityPresets.Presets["balanced"].Gfx;
            var src = gfx ?? new RawGfx();
            return new GfxSettings
            {
                RenderScale = ClampNum(src.RenderScale, 0.5, 1.5, b.RenderScale),
                Shadows = Level(src.Shadows, 3, b.Shadows),
                Grass = Level(src.Grass, 3, b.Grass),
                Particles = Level(src.Particles, 3, b.Particles),
                Water = Level(src.Water, 3, b.Water),
                View = Level(src.View, 3, b.View),
                Detail = Level(src.Detail, 3, b.Detail),
                Texture = Level(src.Texture, 2, b.Texture),
                Bloom = Level(src.Bloom, 3, b.Bloom),
                MotionBlur = Level(src.MotionBlur, 3, b.MotionBlur),
                Volumetric = Level(src.Volumetric, 3, b.Volumetric),
                Adaptive = src.Adaptive ?? b.Adaptive,
            };
        }

        static Dictionary<string, (double x, double y)> NormalizeLayout(
            Dictionary<string, RawPoint> layout)
        {
            var outp = new Dictionary<string, (double, double)>();
            if (layout == null) return outp;
            foreach (var kv in layout)
            {
                var p = kv.Value;
                if (p == null || !p.X.HasValue || !p.Y.HasValue) continue;
                if (double.IsNaN(p.X.Value) || double.IsInfinity(p.X.Value)) continue;
                if (double.IsNaN(p.Y.Value) || double.IsInfinity(p.Y.Value)) continue;
                outp[kv.Key] = (Math.Max(0, Math.Min(1, p.X.Value)),
                                Math.Max(0, Math.Min(1, p.Y.Value)));
            }
            return outp;
        }

        /* Port persis normalizeSettings(). Input null = objek kosong. */
        public static GameSettings Normalize(RawSettings raw)
        {
            var s = raw ?? new RawSettings();
            var gfx = NormalizeGfx(s.Gfx);
            var allowed = new List<string>(QualityPresets.PresetIds) { "custom" }.ToArray();
            var quality = Pick(s.Quality, allowed, "balanced");

            return new GameSettings
            {
                Sensitivity = ClampNum(s.Sensitivity, 0.4, 2, 1),
                CameraDistance = ClampNum(s.CameraDistance, 3, 8, 5),
                Quality = quality,
                Shadows = s.Shadows ?? true,
                Sound = s.Sound ?? true,
                Fps = PickFps(s.Fps, QualityPresets.FpsChoices, 60),
                Custom = s.Custom ?? (quality == "custom"),
                ShowFps = s.ShowFps ?? false,
                Gfx = gfx,
                StickShape = Pick(s.StickShape, QualityPresets.StickShapes, "circle"),
                ButtonTheme = Pick(s.ButtonTheme, QualityPresets.ButtonThemes, "mono"),
                ButtonScale = ClampNum(s.ButtonScale, 0.75, 1.4, 1),
                Layout = NormalizeLayout(s.Layout),
            };
        }
    }
}
