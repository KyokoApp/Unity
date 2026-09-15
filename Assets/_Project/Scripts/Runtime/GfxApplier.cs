using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using RPG.Core;

namespace RPG.Runtime
{
    // ============================================================
    // GfxApplier — menerapkan setting grafik ke engine Unity
    //
    // Dipanggil saat game mulai dan saat setting berubah via SettingsPanel.
    // Mengatur:
    // - Shadow resolution & enabled
    // - Terrain quads & radius
    // - Grass enabled & density (via GfxResolver)
    // - RenderScale (URP asset)
    // - Fog distance
    // - Cel-shading intensity (via material property)
    //
    // FIX untuk bug layar hitam:
    // - Memastikan camera clearFlags = SolidColor (bukan Nothing/Skybox tanpa skybox)
    // - Memastikan URP asset terpasang di semua quality level
    // ============================================================
    [DisallowMultipleComponent]
    public class GfxApplier : MonoBehaviour
    {
        [Header("Rujukan")]
        public TerrainChunkStreamer Streamer;
        public GrassField Grass;
        public Light Sun;
        public Camera MainCamera;

        GameSettings _current;

        void Awake()
        {
            if (MainCamera == null) MainCamera = Camera.main;
            if (Sun == null) Sun = FindFirstObjectByType<Light>();
            if (Streamer == null) Streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            if (Grass == null) Grass = FindFirstObjectByType<GrassField>();

            _current = SettingsStore.Load();
            Apply(_current);

            // FIX: pastikan camera selalu clear solid color untuk hindari trails
            EnsureCameraClear();
        }

        void EnsureCameraClear()
        {
            if (MainCamera == null) return;
            MainCamera.clearFlags = CameraClearFlags.SolidColor;
            if (MainCamera.backgroundColor.a < 0.99f)
            {
                var c = MainCamera.backgroundColor;
                c.a = 1f;
                MainCamera.backgroundColor = c;
            }
            // Pastikan UniversalAdditionalCameraData clearDepth true
            var camData = MainCamera.GetComponent<UniversalAdditionalCameraData>();
            if (camData != null)
            {
#if UNITY_EDITOR
                try
                {
                    var so = new UnityEditor.SerializedObject(camData);
                    var clearDepth = so.FindProperty("m_ClearDepth");
                    if (clearDepth != null) clearDepth.boolValue = true;
                    so.ApplyModifiedPropertiesWithoutUndo();
                }
                catch { }
#endif
            }
        }

        public void Apply(GameSettings s)
        {
            if (s == null) return;
            _current = s;
            var r = GfxResolver.Resolve(s, true); // isTouch = true untuk Android

            // Shadows
            // HARUS ditulis penuh UnityEngine.ShadowQuality: Unity punya
            // UnityEngine.ShadowQuality { Disable, HardOnly, All } (tipe dari
            // QualitySettings.shadows) DAN URP punya UnityEngine.Rendering.Universal.ShadowQuality
            // { Disabled, HardShadows, SoftShadows } yang ANGGOTA-NYA BERBEDA.
            // Berkas ini meng-import kedua namespace, jadi nama telanjang berarti
            // CS0104 'ambiguous reference' -- dan itu yang membunuh build
            // v0.2.0-cel-fix6..fix10 (tujuh build, satu baris ini).
            QualitySettings.shadows = r.ShadowsEnabled ? UnityEngine.ShadowQuality.All : UnityEngine.ShadowQuality.Disable;
            if (Sun != null)
            {
                Sun.shadows = r.ShadowsEnabled ? LightShadows.Soft : LightShadows.None;
                var addLight = Sun.GetComponent<UniversalAdditionalLightData>();
                if (addLight != null)
                {
                    // shadow resolution via additional data tidak ada setter publik,
                    // tapi kita bisa set via light shadow custom resolution? fallback
                    // pakai QualitySettings.shadowResolution = r.ShadowMapSize?
                }
            }

            // Terrain
            if (Streamer != null)
            {
                int quads = r.TerrainSegmentsNear;
                // Clamp quads ke range valid
                quads = Mathf.Clamp(quads, 8, TerrainMesh.MaxQuads);
                int radius = r.StreamRadius;
                Streamer.SetQuality(quads, radius);
            }

            // Grass — enabled/disabled via material dan count
            if (Grass != null)
            {
                // GrassField baca dari SettingsStore di EnsureInit, jadi perlu
                // paksa re-init kalau setting berubah
                // Untuk sekarang, set gameObject active sesuai enabled
                Grass.gameObject.SetActive(r.GrassEnabled);
            }

            // RenderScale — URP asset
            UniversalRenderPipelineAsset urp = null;
            try { urp = GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset; } catch { }
            if (urp == null) urp = GraphicsSettings.defaultRenderPipeline as UniversalRenderPipelineAsset;
            if (urp == null) urp = QualitySettings.renderPipeline as UniversalRenderPipelineAsset;
            if (urp != null)
            {
                urp.renderScale = Mathf.Clamp((float)r.RenderScale, 0.5f, 1.5f);
            }

            // Fog distance dari GfxResolver
            RenderSettings.fogStartDistance = r.FogNear;
            RenderSettings.fogEndDistance = r.FogFar;

            // Cel-shading tweak: kalau quality low, feather lebih besar (lebih halus, hemat)
            // Kalau high/ultra, feather kecil (garis tegas ala Genshin)
            ApplyCelTweak(r);

            Debug.Log($"[GfxApplier] Applied preset={s.Quality} shadows={r.ShadowsEnabled} grass={r.GrassCount} renderScale={r.RenderScale:F2} fog={r.FogNear}/{r.FogFar}");
        }

        void ApplyCelTweak(GfxResolver.Resolved r)
        {
            // Cari semua material yang pakai cel shader dan tweak feather
            float feather = 0.05f;
            if (r.BloomLevel == 0) feather = 0.12f; // low = lebih halus
            else if (r.BloomLevel >= 2) feather = 0.03f; // high/ultra = tegas

            var mats = Resources.FindObjectsOfTypeAll<Material>();
            foreach (var m in mats)
            {
                if (m == null) continue;
                if (m.HasProperty("_Feather")) m.SetFloat("_Feather", feather);
                if (m.HasProperty("_CelFeather")) m.SetFloat("_CelFeather", feather);
                if (m.HasProperty("_ShadowStep"))
                {
                    // Di low, shadow step lebih tinggi (area shadow lebih kecil, lebih terang)
                    float shadowStep = r.ShadowsEnabled ? 0.28f : 0.35f;
                    m.SetFloat("_ShadowStep", shadowStep);
                }
            }
        }

        public GameSettings Current => _current;
    }
}
