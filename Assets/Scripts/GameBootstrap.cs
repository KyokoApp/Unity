using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;

/// <summary>
/// Satu-satunya script yang dipasang di scene. Membangun seluruh game saat runtime:
/// world grid tanpa batas, player (UAL2), kamera orbit, dan UI sentuh Android.
/// </summary>
public class GameBootstrap : MonoBehaviour
{
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

        // ---- World: lantai datar + grid kotak-kotak tanpa batas ----
        var world = WorldGrid.Create();

        // ---- Player ----
        var playerGO = new GameObject("Player");
        playerGO.transform.position = new Vector3(0f, 0.1f, 0f);
        var player = playerGO.AddComponent<PlayerController>();
        player.Init(lib);

        world.target = playerGO.transform;

        // ---- hutan prosedural: nature CC0 (Kenney) dari repo Godot, dikonversi saat build ----
        var forestGO = new GameObject("WorldForest");
        var forest = forestGO.AddComponent<WorldForest>();
        forest.target = playerGO.transform;
        forest.LoadAssets();

        // ---- look ground: padang rumput stylized (bukan grid abu-abu) ----
        WorldGrid.ApplyLook(
            new Color(0.42f, 0.58f, 0.33f),  // base rumput
            new Color(0.38f, 0.53f, 0.30f),  // garis grid halus
            new Color(0.33f, 0.47f, 0.26f),  // garis utama
            new Color(0.72f, 0.82f, 0.70f)); // fog/cakrawala lembut

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
        cam.backgroundColor = new Color(0.75f, 0.82f, 0.90f);
        cam.fieldOfView = 55f;
        cam.nearClipPlane = 0.1f;
        cam.farClipPlane = 400f;

        var orbit = cam.gameObject.AddComponent<OrbitCamera>();
        orbit.target = player.CameraTarget;
        orbit.SnapBehind(playerGO.transform);
        player.cameraTransform = cam.transform;

        // ---- UI sentuh (analog + tombol) ----
        var uiGO = new GameObject("GameUI");
        var ui = uiGO.AddComponent<GameUI>();
        ui.Init(player, lib, orbit);

        // ---- Updater konten in-game (APK = peluncur; konten diunduh live) ----
        var updater = gameObject.AddComponent<ContentUpdater>();
        updater.Init(player, ui);

        // ---- EventSystem untuk input sentuh ----
        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }
    }
}
