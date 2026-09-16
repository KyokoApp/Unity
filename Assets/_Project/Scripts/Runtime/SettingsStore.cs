using System.Collections.Generic;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       SETTINGS STORE — adapter penyimpanan untuk GameSettings.

       RPG.Core sengaja pure (lihat komentar di GameSettings.cs:
       "Adapter storage (PlayerPrefs/JSON) hidup di assembly Runtime").
       Ini adapter-nya.

       Keputusan: PlayerPrefs dengan kunci datar, BUKAN JSON.
       Alasannya praktis — RawSettings penuh `double?` dan GameSettings
       punya Dictionary bernilai tuple, dua hal yang JsonUtility tidak
       bisa. Menarik Newtonsoft hanya untuk ini menambah satu
       dependensi tanpa keuntungan.

       Yang penting dijaga: setiap nilai yang dibaca TETAP dilewatkan
       ke SettingsNormalizer.Normalize(), jadi batas yang sudah diuji
       paritas (Sensitivity 0,4..2, CameraDistance 3..8, dst) berlaku
       di sini juga. PlayerPrefs yang rusak/asing tidak bisa
       menghasilkan setelan di luar batas.

       CameraDistance 3..8 adalah tingkat zoom menu. Meter di dunia
       dipetakan CameraFraming (default ~3,2 m, bukan 5 m).
       ============================================================ */
    public static class SettingsStore
    {
        const string Prefix = "aurelia.settings.";

        static string K(string name) => Prefix + name;

        public static GameSettings Load()
        {
            if (!PlayerPrefs.HasKey(K("quality")))
                return QualityPresets.DefaultSettings();

            var raw = new RawSettings
            {
                Sensitivity    = GetD("sensitivity"),
                CameraDistance = GetD("cameraDistance"),
                Quality        = GetS("quality"),
                Shadows        = GetB("shadows"),
                Sound          = GetB("sound"),
                Fps            = GetI("fps"),
                ShowFps        = GetB("showFps"),
                StickShape     = GetS("stickShape"),
                ButtonTheme    = GetS("buttonTheme"),
                ButtonScale    = GetD("buttonScale"),
                Gfx            = LoadGfx(),
            };
            return SettingsNormalizer.Normalize(raw);
        }

        public static void Save(GameSettings s)
        {
            if (s == null) return;
            PlayerPrefs.SetString(K("quality"),        s.Quality ?? "balanced");
            PlayerPrefs.SetFloat (K("sensitivity"),    (float)s.Sensitivity);
            PlayerPrefs.SetFloat (K("cameraDistance"), (float)s.CameraDistance);
            PlayerPrefs.SetInt   (K("shadows"),        s.Shadows ? 1 : 0);
            PlayerPrefs.SetInt   (K("sound"),          s.Sound ? 1 : 0);
            PlayerPrefs.SetInt   (K("fps"),            s.Fps);
            PlayerPrefs.SetInt   (K("showFps"),        s.ShowFps ? 1 : 0);
            PlayerPrefs.SetString(K("stickShape"),     s.StickShape ?? "circle");
            PlayerPrefs.SetString(K("buttonTheme"),    s.ButtonTheme ?? "mono");
            PlayerPrefs.SetFloat (K("buttonScale"),    (float)s.ButtonScale);
            SaveGfx(s.Gfx);
            PlayerPrefs.Save();
        }

        /* Setelan diturunkan secara fungsional: ambil yang sekarang, ubah satu
           nilai, normalisasi ulang supaya tetap di dalam batas. Tidak ada
           mutasi in-place pada objek yang mungkin sedang dibaca komponen lain. */
        public static GameSettings WithCameraDistance(GameSettings s, double meters)
        {
            var c = s.Clone(); c.CameraDistance = meters;
            return Renormalize(c);
        }

        public static GameSettings WithSensitivity(GameSettings s, double value)
        {
            var c = s.Clone(); c.Sensitivity = value;
            return Renormalize(c);
        }

        static GameSettings Renormalize(GameSettings c) => SettingsNormalizer.Normalize(new RawSettings
        {
            Sensitivity = c.Sensitivity, CameraDistance = c.CameraDistance, Quality = c.Quality,
            Shadows = c.Shadows, Sound = c.Sound, Fps = c.Fps, Custom = c.Custom, ShowFps = c.ShowFps,
            StickShape = c.StickShape, ButtonTheme = c.ButtonTheme, ButtonScale = c.ButtonScale,
            Gfx = new RawGfx
            {
                RenderScale = c.Gfx.RenderScale, Shadows = c.Gfx.Shadows, Grass = c.Gfx.Grass,
                Particles = c.Gfx.Particles, Water = c.Gfx.Water, View = c.Gfx.View,
                Detail = c.Gfx.Detail, Texture = c.Gfx.Texture, Bloom = c.Gfx.Bloom,
                MotionBlur = c.Gfx.MotionBlur, Volumetric = c.Gfx.Volumetric, Adaptive = c.Gfx.Adaptive,
            },
        });

        public static void DeleteAll()
        {
            foreach (var k in AllKeys()) PlayerPrefs.DeleteKey(k);
            PlayerPrefs.Save();
        }

        // ------------------------------------------------------------------
        static RawGfx LoadGfx()
        {
            if (!PlayerPrefs.HasKey(K("gfx.renderScale"))) return null;   // biarkan Normalize mengisi default
            return new RawGfx
            {
                RenderScale = GetD("gfx.renderScale"), Shadows    = GetI("gfx.shadows"),
                Grass       = GetI("gfx.grass"),        Particles  = GetI("gfx.particles"),
                Water       = GetI("gfx.water"),        View       = GetI("gfx.view"),
                Detail      = GetI("gfx.detail"),       Texture    = GetI("gfx.texture"),
                Bloom       = GetI("gfx.bloom"),        MotionBlur = GetI("gfx.motionBlur"),
                Volumetric  = GetI("gfx.volumetric"),   Adaptive   = GetB("gfx.adaptive"),
            };
        }

        static void SaveGfx(GfxSettings g)
        {
            if (g == null) return;
            PlayerPrefs.SetFloat(K("gfx.renderScale"), (float)g.RenderScale);
            PlayerPrefs.SetInt(K("gfx.shadows"),    g.Shadows);
            PlayerPrefs.SetInt(K("gfx.grass"),      g.Grass);
            PlayerPrefs.SetInt(K("gfx.particles"),  g.Particles);
            PlayerPrefs.SetInt(K("gfx.water"),      g.Water);
            PlayerPrefs.SetInt(K("gfx.view"),       g.View);
            PlayerPrefs.SetInt(K("gfx.detail"),     g.Detail);
            PlayerPrefs.SetInt(K("gfx.texture"),    g.Texture);
            PlayerPrefs.SetInt(K("gfx.bloom"),      g.Bloom);
            PlayerPrefs.SetInt(K("gfx.motionBlur"), g.MotionBlur);
            PlayerPrefs.SetInt(K("gfx.volumetric"), g.Volumetric);
            PlayerPrefs.SetInt(K("gfx.adaptive"),   g.Adaptive ? 1 : 0);
        }

        static IEnumerable<string> AllKeys()
        {
            yield return K("quality");        yield return K("sensitivity");
            yield return K("cameraDistance"); yield return K("shadows");
            yield return K("sound");          yield return K("fps");
            yield return K("showFps");        yield return K("stickShape");
            yield return K("buttonTheme");    yield return K("buttonScale");
            foreach (var g in new[] { "renderScale","shadows","grass","particles","water",
                                      "view","detail","texture","bloom","motionBlur",
                                      "volumetric","adaptive" })
                yield return K("gfx." + g);
        }

        static double? GetD(string n) =>
            PlayerPrefs.HasKey(K(n)) ? (double?)PlayerPrefs.GetFloat(K(n)) : null;
        static int? GetI(string n) =>
            PlayerPrefs.HasKey(K(n)) ? (int?)PlayerPrefs.GetInt(K(n)) : null;
        static bool? GetB(string n) =>
            PlayerPrefs.HasKey(K(n)) ? (bool?)(PlayerPrefs.GetInt(K(n)) != 0) : null;
        static string GetS(string n) =>
            PlayerPrefs.HasKey(K(n)) ? PlayerPrefs.GetString(K(n)) : null;
    }
}
