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

        // ---- EventSystem untuk input sentuh ----
        if (FindObjectOfType<EventSystem>() == null)
        {
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
        }
    }
}
