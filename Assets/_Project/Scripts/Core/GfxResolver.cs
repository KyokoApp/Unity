using System;

namespace RPG.Core
{
    /* ============================================================
       GFX RESOLVER — port dari resolveGfx() di game/quality.mjs.

       Menerjemahkan TINGKAT (0..3) menjadi ANGKA KONKRET untuk engine.
       isTouch menurunkan plafon karena GPU ponsel jauh lebih sempit.

       CATATAN untuk Unity: angka-angka di bawah adalah *target*. Cara
       memakainya beda per pipeline —
         shadowMapSize  -> UniversalAdditionalLightData / Light.shadowResolution
         fogNear/fogFar -> RenderSettings.fog + Camera.farClipPlane
         renderScale    -> UniversalRenderPipelineAsset.renderScale
         bloom/blur/vol -> Volume profile (URP) — lihat Fase 6
       Resolver ini tetap satu-satunya sumber kebenaran untuk ANGKANYA;
       yang menerapkannya adalah komponen di assembly Runtime.
       ============================================================ */
    public static class GfxResolver
    {
        static readonly double[] Ramp4 = { 0, 0.25, 0.55, 1 };          // faktor jumlah populasi
        static readonly double[] RampView = { 0.45, 0.7, 1, 1.35 };    // faktor jarak pandang

        public sealed class Resolved
        {
            public double DprCap;
            public double RenderScale;
            public bool Adaptive;

            public bool ShadowsEnabled;
            public int ShadowMapSize;
            public int ShadowRefreshFrames;

            public int GrassCount;
            public bool GrassEnabled;
            public int DustCount;
            public int ButterflyCount;
            public int BirdCount;
            public bool ParticlesEnabled;

            public int WaterSegments;
            public bool WaterWaves;
            public double WaterOpacity;

            public int FogNear;
            public int FogFar;
            public int OrbCullDistance;
            public int StreamRadius;

            public int TerrainSegmentsNear;
            public int PropsNear;
            public int PropsFar;
            public bool RoadProps;
            public int RoadPropSpacing;

            public int TextureSize;
            public int Anisotropy;

            public int BloomLevel;
            public int MotionBlurLevel;
            public int VolumetricLevel;
            public bool PostEnabled;
        }

        static T At<T>(T[] arr, int i, T fallback) => i >= 0 && i < arr.Length ? arr[i] : fallback;

        public static Resolved Resolve(GameSettings settings, bool isTouch = false)
        {
            var g = settings.Gfx ?? QualityPresets.Presets["balanced"].Gfx;
            var dprCap = isTouch ? 2.0 : 2.5;

            var grassBase = isTouch ? 9000.0 : 28000.0;
            var dustBase = isTouch ? 90.0 : 190.0;
            var bflyBase = isTouch ? 26.0 : 55.0;
            var birdBase = isTouch ? 18.0 : 34.0;

            var shadowSize = At(new[] { 0, 1024, 1536, 2048 }, g.Shadows, 0);
            var viewF = At(RampView, g.View, 1.0);

            return new Resolved
            {
                /* --- resolusi ---
                   pixelRatio final TIDAK dihitung di sini. Di Unity yang
                   menentukan adalah komponen Runtime yang mengenal
                   Screen.dpi & adaptive resolution. Menyediakannya di sini
                   akan membuat dua sumber kebenaran untuk satu hal. */
                DprCap = dprCap,
                RenderScale = g.RenderScale == 0 ? 1 : g.RenderScale,
                Adaptive = g.Adaptive,

                /* --- bayangan --- */
                ShadowsEnabled = shadowSize > 0 && settings.Shadows,
                ShadowMapSize = shadowSize == 0 ? 512 : shadowSize,
                /* diperbarui tiap N frame: hemat besar, nyaris tak terlihat */
                ShadowRefreshFrames = g.Shadows >= 3 ? 1 : g.Shadows == 2 ? 1 : 2,

                /* --- vegetasi & partikel --- */
                GrassCount = JsMath.RoundToInt(grassBase * At(Ramp4, g.Grass, 0.0)),
                GrassEnabled = g.Grass > 0,
                DustCount = JsMath.RoundToInt(dustBase * At(Ramp4, g.Particles, 0.0)),
                ButterflyCount = JsMath.RoundToInt(bflyBase * At(Ramp4, g.Particles, 0.0)),
                BirdCount = JsMath.RoundToInt(birdBase * At(Ramp4, g.Particles, 0.0)),
                ParticlesEnabled = g.Particles > 0,

                /* --- air --- */
                WaterSegments = At(new[] { 24, 44, 68, 96 }, g.Water, 68),
                WaterWaves = g.Water >= 2,
                WaterOpacity = g.Water == 0 ? 0.55 : 0.86,

                /* --- jarak pandang / streaming dunia --- */
                FogNear = JsMath.RoundToInt((isTouch ? 260.0 : 450.0) * viewF),
                FogFar = JsMath.RoundToInt((isTouch ? 700.0 : 950.0) * viewF),
                OrbCullDistance = JsMath.RoundToInt(650 * viewF),
                StreamRadius = Math.Max(2, Math.Min(5,
                    (isTouch ? 3 : 4) + (g.View >= 3 ? 1 : g.View == 0 ? -1 : 0))),

                /* --- kedetailan dunia --- */
                TerrainSegmentsNear = At(new[] { 28, 44, 64, 84 }, g.Detail, 64),
                PropsNear = At(new[] { 10, 24, 40, 56 }, g.Detail, 40),
                PropsFar = At(new[] { 3, 5, 8, 12 }, g.Detail, 8),
                RoadProps = g.Detail >= 1,
                RoadPropSpacing = g.Detail >= 3 ? 90 : g.Detail == 2 ? 130 : 190,

                /* --- tekstur --- */
                TextureSize = At(new[] { 128, 256, 512 }, g.Texture, 256),
                Anisotropy = At(new[] { 1, 4, 8 }, g.Texture, 4),

                /* --- post-processing --- */
                BloomLevel = g.Bloom,
                MotionBlurLevel = g.MotionBlur,
                VolumetricLevel = g.Volumetric,
                PostEnabled = g.Bloom > 0 || g.MotionBlur > 0 || g.Volumetric > 0,
            };
        }
    }

    /* ============================================================
       ADAPTIVE RESOLUTION — port dari createAdaptiveResolution().
       Naik-turunkan skala render mengikuti waktu frame terukur.
       Histeresis lebar (turun cepat, naik pelan) supaya tidak berosilasi.
       ============================================================ */
    public sealed class AdaptiveResolution
    {
        readonly double _min, _max, _start;
        double _scale;
        int _badFrames, _goodFrames;

        public AdaptiveResolution(double min = 0.55, double max = 1, double start = 1)
        {
            _min = min; _max = max; _start = start;
            _scale = start;
        }

        public double Scale => _scale;

        public void Reset(double? next = null)
        {
            _scale = next ?? _start;
            _badFrames = 0;
            _goodFrames = 0;
        }

        /* targetMs = budget frame (mis. 1000/45). Mengembalikan skala baru. */
        public double Update(double frameMs, double targetMs)
        {
            if (!(targetMs > 0) || double.IsNaN(frameMs) || double.IsInfinity(frameMs)) return _scale;

            if (frameMs > targetMs * 1.22) { _badFrames++; _goodFrames = 0; }
            else if (frameMs < targetMs * 0.82) { _goodFrames++; _badFrames = 0; }
            else { _badFrames = 0; _goodFrames = 0; }

            if (_badFrames >= 20) { _scale = Math.Max(_min, _scale - 0.1); _badFrames = 0; }
            else if (_goodFrames >= 150) { _scale = Math.Min(_max, _scale + 0.05); _goodFrames = 0; }
            return _scale;
        }
    }
}
