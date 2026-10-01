using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;

/// <summary>
/// Satu-satunya script yang dipasang di scene. Membangun seluruh game saat runtime:
/// world grid tanpa batas, player (UAL2), kamera orbit, dan UI sentuh Android.
/// </summary>
public class GameBootstrap : MonoBehaviour
{
    /// <summary>Dimatikan saat tes headless (jangan sentuh jaringan).</summary>
    public static bool SkipUpdater;

    void Awake()
    {
        // ---- Pengaturan global (mobile friendly) ----
        Application.targetFrameRate = 60;
        QualitySettings.vSyncCount = 0;
        QualitySettings.shadows = ShadowQuality.HardOnly;
        QualitySettings.shadowDistance = 45f;
        Input.multiTouchEnabled = true;

        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogColor = new Color(0.75f, 0.82f, 0.90f);
        RenderSettings.fogStartDistance = 45f;
        RenderSettings.fogEndDistance = 170f;
        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.62f, 0.65f, 0.71f);

        // ---- Library animasi (Universal Animation Library 2 - Quaternius) ----
        var lib = new AnimLibrary();
        Debug.Log("[UAL2] Animasi termuat: " + lib.Count);

        // ---- World: pulau 1 km x 1 km (port redesign world Godot-mu):
        // gunung/tebing, danau + sungai, jalan pedesaan, plaza batu, laut ----
        var island = IslandTerrain.Build();

        // ---- Player (lahir di plaza batu) ----
        var playerGO = new GameObject("Player");
        playerGO.transform.position = island.SpawnPoint;
        var player = playerGO.AddComponent<PlayerController>();
        player.Init(lib);

        // ---- rumput berlapis (port grass_field.gd) + hutan deterministik ----
        var grassGO = new GameObject("GrassField");
        var grass = grassGO.AddComponent<GrassField>();
        grass.player = playerGO.transform;

        var forestGO = new GameObject("WorldForest");
        var forest = forestGO.AddComponent<WorldForest>();
        forest.target = playerGO.transform;
        forest.LoadAssets();

        // ---- cakrawala pulau (grid kotak-kotak dihapus) ----
        RenderSettings.fogColor = new Color(0.80f, 0.87f, 0.91f);
        RenderSettings.fogStartDistance = 80f;
        RenderSettings.fogEndDistance = 650f;

        // ---- Kamera orbit (third person) ----
        var cam = Camera.main;
        if (cam == null)
        {
            var camGO = new GameObject("Main Camera");
            camGO.tag = "MainCamera";
            cam = camGO.AddComponent<Camera>();
            camGO.AddComponent<AudioListener>();
        }
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.80f, 0.87f, 0.91f);
        cam.fieldOfView = 55f;
        cam.nearClipPlane = 0.1f;
        cam.farClipPlane = 3000f;   // pulau 1 km + laut 4 km harus terlihat utuh

        var orbit = cam.gameObject.AddComponent<OrbitCamera>();
        orbit.target = player.CameraTarget;
        orbit.SnapBehind(playerGO.transform);
        player.cameraTransform = cam.transform;

        // ---- UI sentuh (analog + tombol) ----
        var uiGO = new GameObject("GameUI");
        var ui = uiGO.AddComponent<GameUI>();
        ui.Init(player, lib, orbit);

        // ---- Updater konten in-game (APK = peluncur; konten diunduh live) ----
        if (!SkipUpdater)
        {
            var updater = gameObject.AddComponent<ContentUpdater>();
            updater.Init(player, ui);
        }

        // ---- EventSystem untuk input sentuh ----
        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }
    }
}
