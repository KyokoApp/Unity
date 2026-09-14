using System;
using System.Collections.Generic;

namespace RPG.Core
{
    /* ============================================================
       QUALITY PRESETS — port dari game/quality.mjs (bagian preset).

       Prinsip yang dipertahankan dari aslinya:
       1. PRESET dulu, CUSTOM kemudian. Begitu satu opsi diubah manual,
          preset otomatis jadi 'custom' — tidak ada state "preset
          setengah jadi".
       2. Modul ini PURE: tidak menyentuh engine. Bisa dites headless.
       3. Tingkat 0 = benar-benar MATI. Tidak boleh ada sisa draw call.

       Penamaan tingkat: 0=Mati, 1=Rendah, 2=Sedang, 3=Tinggi.
       ============================================================ */
    public static class QualityPresets
    {
        /* 'balanced' = nama internal "Sedang" supaya setting lama tetap kebaca. */
        public static readonly string[] PresetIds = { "low", "balanced", "high", "ultra" };

        public static readonly Dictionary<string, string> PresetLabel = new Dictionary<string, string>
        {
            { "low", "Rendah" }, { "balanced", "Sedang" }, { "high", "Tinggi" },
            { "ultra", "Ultra" }, { "custom", "Custom" },
        };

        /* 60 = default; 24 untuk perangkat sangat lemah supaya simulasi
           tetap jalan mulus (bukan patah-patah). */
        public static readonly int[] FpsChoices = { 24, 30, 45, 60 };

        public static readonly string[] LevelLabel = { "Mati", "Rendah", "Sedang", "Tinggi" };
        public static readonly string[] TextureLevelLabel = { "Rendah", "Sedang", "Tinggi" };

        public sealed class GfxOption
        {
            public string Key, Label, Hint;
            public int Max;
            public bool Off;   // true = tingkat 0 mematikan fitur
        }

        public static readonly GfxOption[] GfxOptions =
        {
            new GfxOption { Key="shadows",    Label="Bayangan",         Max=3, Off=true,  Hint="Peta bayangan matahari" },
            new GfxOption { Key="grass",      Label="Rumput",           Max=3, Off=true,  Hint="Jumlah bilah rumput di sekitar pemain" },
            new GfxOption { Key="particles",  Label="Partikel & satwa", Max=3, Off=true,  Hint="Debu, kupu-kupu, burung" },
            new GfxOption { Key="water",      Label="Air",              Max=3, Off=true,  Hint="Detail gelombang permukaan air" },
            new GfxOption { Key="view",       Label="Jarak pandang",    Max=3, Off=false, Hint="Kabut, cakrawala, dan jarak streaming dunia" },
            new GfxOption { Key="detail",     Label="Kedetailan dunia", Max=3, Off=false, Hint="Kerapatan pohon, batu, dan properti jalan" },
            new GfxOption { Key="texture",    Label="Detail tekstur",   Max=2, Off=false, Hint="Resolusi & anisotropi tekstur prosedural" },
            new GfxOption { Key="bloom",      Label="Bloom",            Max=3, Off=true,  Hint="Pendar cahaya pada orb, lampu, dan knalpot" },
            new GfxOption { Key="motionBlur", Label="Motion blur",      Max=3, Off=true,  Hint="Blur kecepatan ala Forza Horizon" },
            new GfxOption { Key="volumetric", Label="Volumetrik",       Max=3, Off=true,  Hint="Berkas cahaya matahari (god rays)" },
        };

        public sealed class Preset
        {
            public int Fps;
            public GfxSettings Gfx;
        }

        /* Angka ini hasil penalaran biaya: bayangan & post-processing adalah
           beban GPU terbesar, jadi preset Rendah mematikannya total. */
        public static readonly Dictionary<string, Preset> Presets = new Dictionary<string, Preset>
        {
            ["low"] = new Preset { Fps = 30, Gfx = new GfxSettings {
                RenderScale=0.70, Shadows=0, Grass=0, Particles=0, Water=1, View=1, Detail=0,
                Texture=0, Bloom=0, MotionBlur=0, Volumetric=0, Adaptive=true } },
            ["balanced"] = new Preset { Fps = 45, Gfx = new GfxSettings {
                RenderScale=0.85, Shadows=1, Grass=1, Particles=1, Water=2, View=2, Detail=1,
                Texture=1, Bloom=1, MotionBlur=0, Volumetric=0, Adaptive=true } },
            ["high"] = new Preset { Fps = 60, Gfx = new GfxSettings {
                RenderScale=1.00, Shadows=2, Grass=2, Particles=2, Water=3, View=3, Detail=2,
                Texture=2, Bloom=2, MotionBlur=1, Volumetric=1, Adaptive=true } },
            ["ultra"] = new Preset { Fps = 60, Gfx = new GfxSettings {
                RenderScale=1.25, Shadows=3, Grass=3, Particles=3, Water=3, View=3, Detail=3,
                Texture=2, Bloom=3, MotionBlur=2, Volumetric=2, Adaptive=false } },
        };

        /* Bentuk default = preset 'balanced'. */
        public static GameSettings DefaultSettings() => new GameSettings
        {
            Sensitivity = 1,
            CameraDistance = 5,
            Quality = "balanced",
            Shadows = true,
            Sound = true,
            Fps = 60,
            Custom = false,
            ShowFps = false,
            Gfx = Presets["balanced"].Gfx.Clone(),
            StickShape = "circle",
            ButtonTheme = "mono",
            ButtonScale = 1,
            Layout = new Dictionary<string, (double, double)>(),
            CarCamera = "near",
        };

        public static readonly string[] StickShapes = { "circle", "square" };
        public static readonly string[] ButtonThemes = { "mono", "color" };
        public static readonly string[] CarCameraModes = { "near", "far", "cine" };
        public static readonly Dictionary<string, string> CarCameraLabel = new Dictionary<string, string>
        {
            { "near", "Dekat" }, { "far", "Jauh" }, { "cine", "Sinematik" },
        };

        /* Mengembalikan settings BARU (immutable style, sama seperti JS
           yang selalu menyebar {...settings}). */
        public static GameSettings ApplyPreset(GameSettings settings, string id)
        {
            if (!Presets.TryGetValue(id, out var p)) return settings;
            var next = settings.Clone();
            next.Quality = id;
            next.Custom = false;
            next.Fps = p.Fps;
            next.Gfx = p.Gfx.Clone();
            /* preset ikut menyetel saklar bayangan lama supaya konsisten */
            next.Shadows = p.Gfx.Shadows > 0;
            return next;
        }

        static int ClampInt(double v, int a, int b)
            => double.IsNaN(v) || double.IsInfinity(v) ? a : Math.Max(a, Math.Min(b, JsMath.RoundToInt(v)));

        static double ClampNum(double v, double a, double b, double d)
            => double.IsNaN(v) || double.IsInfinity(v) ? d : Math.Max(a, Math.Min(b, v));

        /* Mengubah satu opsi: preset langsung turun jadi 'custom'. */
        public static GameSettings SetGfx(GameSettings settings, string key, double value)
        {
            var opt = Array.Find(GfxOptions, o => o.Key == key);
            var gfx = settings.Gfx.Clone();
            if (opt != null) SetLevel(gfx, key, ClampInt(value, 0, opt.Max));
            else if (key == "renderScale") gfx.RenderScale = ClampNum(value, 0.5, 1.5, gfx.RenderScale);
            else return settings;   // kunci tak dikenal: kembalikan apa adanya
            var next = settings.Clone();
            next.Gfx = gfx;
            next.Quality = "custom";
            next.Custom = true;
            return next;
        }

        public static GameSettings SetGfx(GameSettings settings, string key, bool value)
        {
            if (key != "adaptive") return settings;
            var next = settings.Clone();
            next.Gfx = settings.Gfx.Clone();
            next.Gfx.Adaptive = value;
            next.Quality = "custom";
            next.Custom = true;
            return next;
        }

        static void SetLevel(GfxSettings g, string key, int v)
        {
            switch (key)
            {
                case "shadows": g.Shadows = v; break;
                case "grass": g.Grass = v; break;
                case "particles": g.Particles = v; break;
                case "water": g.Water = v; break;
                case "view": g.View = v; break;
                case "detail": g.Detail = v; break;
                case "texture": g.Texture = v; break;
                case "bloom": g.Bloom = v; break;
                case "motionBlur": g.MotionBlur = v; break;
                case "volumetric": g.Volumetric = v; break;
            }
        }

        /* Apakah isi gfx persis sama dengan sebuah preset? Dipakai UI untuk
           menampilkan "Custom" hanya saat benar-benar berbeda. */
        public static string DetectPreset(GfxSettings gfx)
        {
            foreach (var id in PresetIds)
                if (Presets[id].Gfx.SameValues(gfx)) return id;
            return "custom";
        }

        /* Interval frame dalam ms untuk FPS cap. 0 = tanpa batas. */
        public static double FrameInterval(int fps)
            => Array.IndexOf(FpsChoices, fps) >= 0 && fps > 0 ? 1000.0 / fps : 0;
    }
}
