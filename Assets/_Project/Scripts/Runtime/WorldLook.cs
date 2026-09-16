using UnityEngine;
using UnityEngine.Rendering.Universal;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       WORLD LOOK — jaring pengaman tampilan di perangkat.

       Dipanggil dari CameraRig.Awake, DayNightCycle.Apply,
       WorldBoot.EnterWorld, dan Stage2SceneBuilder. Tujuannya
       SATU: pemain HP melihat tanah + langit berwarna, bukan
       layar hitam dengan HUD menumpuk chrome debug.
       ============================================================ */
    public static class WorldLook
    {
        public static bool IsMobilePlayer
        {
            get
            {
#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR
                return true;
#else
                return false;
#endif
            }
        }

        public static void PrepareCamera(Camera cam)
        {
            if (cam == null) return;
            cam.allowHDR = false;
            cam.allowMSAA = false;
            try
            {
                var data = cam.GetUniversalAdditionalCameraData();
                if (data != null)
                {
                    data.renderPostProcessing = false;
                    data.renderShadows = false;
                }
            }
            catch { /* stub / URP belum siap: kamera tetap jalan */ }

            if (WorldLookPolicy.UseSolidSky(IsMobilePlayer))
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
                var bg = cam.backgroundColor;
                if (WorldLookPolicy.AmbientTooDark(bg.r, bg.g, bg.b))
                    cam.backgroundColor = new Color(0.62f, 0.70f, 0.78f);
            }
        }

        /* Langit: di HP pakai SolidColor (horizon) — shader skybox
           custom sering gagal sebagai skybox URP di GLES. Di editor
           / desktop tetap skybox gradien. */
        public static void ApplySky(Camera cam, Material sky, Color horizon)
        {
            if (cam == null) return;
            cam.backgroundColor = horizon;
            if (WorldLookPolicy.UseSolidSky(IsMobilePlayer) || sky == null)
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
            }
            else
            {
                RenderSettings.skybox = sky;
                cam.clearFlags = CameraClearFlags.Skybox;
            }
        }

        public static void EnableInstancing(Material mat)
        {
            if (mat == null) return;
            mat.enableInstancing = true;
        }

        /* Chrome debug (PerfHud, tombol Pagi/Siang, stik IMGUI)
           menumpuk HUD Genshin di landscape HP. Sembunyikan saat
           masuk dunia; F1 / ketuk sudut tetap bisa menampilkan
           PerfHud, F2 untuk tombol suasana. */
        public static void HideDevChrome()
        {
            var perf = Object.FindFirstObjectByType<PerfHud>();
            if (perf != null) perf.Visible = false;
            var cycle = Object.FindFirstObjectByType<DayNightCycle>();
            if (cycle != null) cycle.ShowButtons = false;
            var tj = Object.FindFirstObjectByType<TouchJoystick>();
            if (tj != null)
            {
                tj.Visible = false;
                tj.ShowRunButton = false;
                tj.ShowJumpButton = false;
            }
        }

        public static void OnEnteredWorld()
        {
            HideDevChrome();
            ForceVisibleFrame();

            var grass = Object.FindFirstObjectByType<GrassField>();
            if (grass != null)
            {
                EnableInstancing(grass.GrassMaterial);
                grass.enabled = false; // jangan spam instancing sampai dunia terlihat
            }

            var vfx = Object.FindFirstObjectByType<AnimeVFX>();
            if (vfx != null) EnableInstancing(vfx.SparkleMaterial);
        }

        /* Dipanggil setiap LateUpdate oleh WorldLookDriver.
           Menimpa fog/skybox/HDR/post/bayangan yang membuat HP hitam. */
        public static void ForceVisibleFrame()
        {
            RenderSettings.fog = false;
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            var amb = RenderSettings.ambientLight;
            if (WorldLookPolicy.AmbientTooDark(amb.r, amb.g, amb.b))
                RenderSettings.ambientLight = new Color(0.50f, 0.56f, 0.64f);

            Camera cam = Camera.main;
            if (cam == null)
            {
                var rig = Object.FindFirstObjectByType<CameraRig>();
                if (rig != null) cam = rig.GetComponent<Camera>();
            }
            if (cam != null)
            {
                cam.enabled = true;
                cam.allowHDR = false;
                cam.allowMSAA = false;
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = new Color(0.55f, 0.72f, 0.92f);
                try
                {
                    var data = cam.GetUniversalAdditionalCameraData();
                    if (data != null)
                    {
                        data.renderPostProcessing = false;
                        data.renderShadows = false;
                    }
                }
                catch { }
            }

            var light = Object.FindFirstObjectByType<Light>();
            if (light != null) light.shadows = LightShadows.None;

            var vol = Object.FindFirstObjectByType<StylizedVolume>();
            if (vol != null && vol.Volume != null) vol.Volume.enabled = false;
        }
    }
}
