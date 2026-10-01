using System.Collections;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;

/// <summary>
/// Satu-satunya script yang dipasang di scene. Menampilkan splash tipis dahulu,
/// memuat paket visual cache, lalu membangun pulau, player, kamera, dan UI.
/// </summary>
public class GameBootstrap : MonoBehaviour
{
    /// <summary>Dimatikan saat tes headless (jangan sentuh jaringan).</summary>
    public static bool SkipUpdater;

    GameLoadingScreen loading;

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

        loading = GameLoadingScreen.Show();
    }

    IEnumerator Start()
    {
        if (loading != null) loading.SetProgress(0.04f, "MEMULAI ARPG...");
        yield return null; // pastikan gambar splash tampil sebelum kerja berat

        if (!SkipUpdater)
            ContentUpdater.LoadCachedBootstrapData();

        var lib = new AnimLibrary();
        if (loading != null) loading.SetProgress(0.16f, "MEMUAT KARAKTER & ANIMASI...");
        yield return null;
        Debug.Log("[ARPG] Animasi termuat: " + lib.Count);

        // Pulau mencakup terrain 200 m x 200 m, air, plaza, jalan, dan batu.
        if (loading != null) loading.SetProgress(0.36f, "MEMBANGUN DUNIA...");
        yield return null;
        var island = IslandTerrain.Build();
        if (loading != null) loading.SetProgress(0.64f, "MEMBANGUN DUNIA...");
        yield return null;

        var playerGO = new GameObject("Player");
        playerGO.transform.position = island.SpawnPoint;
        var player = playerGO.AddComponent<PlayerController>();
        player.Init(lib);

        var grassGO = new GameObject("GrassField");
        var grass = grassGO.AddComponent<GrassField>();
        grass.player = playerGO.transform;

        var forestGO = new GameObject("WorldForest");
        var forest = forestGO.AddComponent<WorldForest>();
        forest.target = playerGO.transform;
        forest.LoadAssets();

        RenderSettings.fogColor = new Color(0.80f, 0.87f, 0.91f);
        RenderSettings.fogStartDistance = 80f;
        RenderSettings.fogEndDistance = 180f;

        if (loading != null) loading.SetProgress(0.80f, "MENYIAPKAN KAMERA...");
        yield return null;

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
        cam.farClipPlane = 3000f;

        var orbit = cam.gameObject.AddComponent<OrbitCamera>();
        orbit.target = player.CameraTarget;
        orbit.SnapBehind(playerGO.transform);
        player.cameraTransform = cam.transform;

        var uiGO = new GameObject("GameUI");
        var ui = uiGO.AddComponent<GameUI>();
        ui.Init(player, lib, orbit);

        if (!SkipUpdater)
        {
            var updater = gameObject.AddComponent<ContentUpdater>();
            updater.Init(player, ui);
        }

        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }

        if (loading != null)
        {
            loading.SetProgress(1f, "SIAP");
            yield return new WaitForSeconds(0.25f);
            loading.Hide();
        }
    }
}
