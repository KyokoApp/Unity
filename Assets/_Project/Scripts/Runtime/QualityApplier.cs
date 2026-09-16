using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       QUALITY APPLIER — menerjemahkan GfxResolver menjadi kenyataan.

       PERBAIKAN BUG BESAR Tahap 5: sebelum ini, GfxResolver +
       AdaptiveResolution + preset kualitas TIDAK TERPAKAI — angka
       resolvenya dihitung (oleh GrassField saja) tapi fog, shadow,
       render scale, bloom, dan adaptive resolution tidak pernah
       diterapkan ke apa pun. Pengaturan kualitas = pajangan.

       Sekarang komponen ini (sekali di Awake + tiap pengaturan
       berubah + tiap frame untuk adaptive):
         * URP asset: renderScale, shadowDistance, cascade count
         * Fog near/far, target frame rate
         * Terrain: quads + radius (rebuild hanya kalau berubah)
         * Rumput: radius + refresh (mati total di preset Rendah)
         * Volume: bloom level + nyala/mati post
         * Matahari: bayangan lembut/mati
         * Karakter toon: outline nyala/mati (preset Rendah)
         * Adaptive resolution: renderScale turun-naik ikut frame
       ============================================================ */
    [DisallowMultipleComponent]
    public class QualityApplier : MonoBehaviour
    {
        public static QualityApplier Instance { get; private set; }

        AdaptiveResolution _adaptive;
        float _baseScale = 1f;
        bool _adaptiveOn;
        int _fpsTarget = 60;

        void Awake()
        {
            Instance = this;
            ApplyAll();
        }

        void OnDestroy()
        {
            if (Instance == this) Instance = null;
        }

        void Update()
        {
            if (!_adaptiveOn) return;
            var urp = GraphicsSettings.defaultRenderPipeline as UniversalRenderPipelineAsset;
            if (urp == null) return;
            var frameMs = Time.unscaledDeltaTime * 1000.0;
            var targetMs = 1000.0 / Mathf.Max(1, _fpsTarget);
            var s = _adaptive.Update(frameMs, targetMs);
            if (System.Math.Abs(s - urp.renderScale) > 0.01)
                urp.renderScale = (float)s;
        }

        public static void RefreshAll()
        {
            if (Instance != null) Instance.ApplyAll();
        }

        public void ApplyAll()
        {
            var settings = SettingsStore.Load();
            var touch = Input.touchSupported;
            var r = GfxResolver.Resolve(settings, touch);

            ApplyUrp(r);
            ApplyFog(r);
            ApplyTerrain(r);
            ApplyGrass(r, settings);
            ApplyPost(r);
            ApplyShadows(r);
            ApplyOutline(r);

            Application.targetFrameRate = settings.Fps;
            _fpsTarget = settings.Fps;

            // Adaptive resolution: mulai dari skala preset.
            _adaptiveOn = r.Adaptive;
            _adaptive = new AdaptiveResolution(0.55, _baseScale, _baseScale);

            // Komponen lain membaca ulang pengaturannya.
            var cam = FindFirstObjectByType<CameraRig>();
            if (cam != null) cam.RefreshSettings();
            var cycle = FindFirstObjectByType<DayNightCycle>();
            if (cycle != null) cycle.RefreshSettings();
            var joy = FindFirstObjectByType<TouchJoystick>();
            if (joy != null) joy.RefreshSettings();
        }

        void ApplyUrp(GfxResolver.Resolved r)
        {
            var urp = GraphicsSettings.defaultRenderPipeline as UniversalRenderPipelineAsset;
            if (urp == null) return;
            _baseScale = Mathf.Clamp((float)r.RenderScale, 0.5f, 1.5f);
            urp.renderScale = _baseScale;
            // HDR di tile-GPU HP sering menghasilkan blit hitam. Dunia
            // stylized tidak butuh HDR; bloom tetap jalan di LDR.
            urp.supportsHDR = false;
            // Bayangan 80 m + 2 cascade (tinggi) / 1 cascade: cukup untuk
            // karakter + pohon dekat; jauhnya ditutup fog + bayangan toon.
            urp.shadowDistance = 80f;
            urp.shadowCascadeCount = Mathf.Clamp(r.ShadowsEnabled && r.ShadowMapSize >= 1536 ? 2 : 1, 1, 4);
        }

        static void ApplyFog(GfxResolver.Resolved r)
        {
            /* Fog di HP + MixFog shader = dunia hitam (unity_FogColor
               sering 0). Dunia harus kelihatan dulu. */
            RenderSettings.fog = false;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogStartDistance = r.FogNear;
            RenderSettings.fogEndDistance = r.FogFar;
        }

        static void ApplyTerrain(GfxResolver.Resolved r)
        {
            var streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            if (streamer == null) return;
            var quads = r.TerrainSegmentsNear >= 84 ? 48
                      : r.TerrainSegmentsNear >= 64 ? 32
                      : r.TerrainSegmentsNear >= 44 ? 24 : 16;
            var radius = Mathf.Clamp(r.StreamRadius, 1, 3);
            if (streamer.QuadsPerChunk != quads || streamer.StreamRadius != radius)
                streamer.SetQuality(quads, radius);
        }

        static void ApplyGrass(GfxResolver.Resolved r, GameSettings s)
        {
            var grass = FindFirstObjectByType<GrassField>();
            if (grass == null) return;
            grass.enabled = r.GrassEnabled;
            if (r.GrassEnabled)
            {
                grass.Radius = 18f + s.Gfx.Grass * 5f;   // 23/28/33 m
                grass.RefreshSettings();
            }
        }

        static void ApplyPost(GfxResolver.Resolved r)
        {
            var vol = FindFirstObjectByType<StylizedVolume>();
            if (vol == null || vol.Volume == null) return;
            vol.SetBloomLevel(0);
            vol.Volume.enabled = false;
        }

        static void ApplyShadows(GfxResolver.Resolved r)
        {
            // DayNightCycle yang pegang lampu (tahu kapan malam).
            var cycle = FindFirstObjectByType<DayNightCycle>();
            if (cycle != null) { cycle.RefreshSettings(); return; }
            var light = FindFirstObjectByType<Light>();
            if (light != null)
                light.shadows = r.ShadowsEnabled ? LightShadows.Soft : LightShadows.None;
        }

        static void ApplyOutline(GfxResolver.Resolved r)
        {
            // Preset Rendah (rumput mati) = outline mati: hemat 1 draw
            // call + 1x vertex per material karakter.
            var setup = FindFirstObjectByType<ToonCharacterSetup>();
            if (setup != null) setup.SetOutlineEnabled(r.GrassEnabled);
        }
    }
}
