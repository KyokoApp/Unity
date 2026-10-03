using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Rendering;

/// <summary>
/// Membangun pengalaman PoolRooms mandiri: ruang kolam, locker, shower, dan atrium
/// liminal yang tersambung, kamera first-person tanpa karakter, serta kontrol HP.
/// </summary>
public class GameBootstrap : MonoBehaviour
{
    void Awake()
    {
        ConfigureRendering();

        Camera viewCamera = Camera.main;
        if (viewCamera == null)
        {
            var cameraGO = new GameObject("Main Camera");
            cameraGO.tag = "MainCamera";
            viewCamera = cameraGO.AddComponent<Camera>();
            cameraGO.AddComponent<AudioListener>();
        }
        else if (viewCamera.GetComponent<AudioListener>() == null)
        {
            viewCamera.gameObject.AddComponent<AudioListener>();
        }

        viewCamera.clearFlags = CameraClearFlags.SolidColor;
        viewCamera.backgroundColor = new Color(0.075f, 0.105f, 0.13f, 1f);
        viewCamera.fieldOfView = 74f;
        viewCamera.nearClipPlane = 0.08f;
        viewCamera.farClipPlane = 180f;
        viewCamera.allowHDR = false;
        viewCamera.allowMSAA = true;
        viewCamera.useOcclusionCulling = false;

        // Rig hanya berisi CharacterController + kamera; tidak ada avatar yang terlihat.
        var rigGO = new GameObject("First Person Camera Rig (no visible body)");
        rigGO.transform.SetParent(transform, false);
        var firstPerson = rigGO.AddComponent<FirstPersonRoomController>();
        firstPerson.Initialize(viewCamera, new Vector3(PoolRoomsEnvironment.SpawnX, 0.03f, 0f), 0f);

        PoolRoomsEnvironment.Build(transform, firstPerson);
        BuildMobileUI(firstPerson);
        EnsureEventSystem(transform);
    }

    static void ConfigureRendering()
    {
        Application.targetFrameRate = 60;
        QualitySettings.vSyncCount = 0;
        QualitySettings.antiAliasing = 2;
        QualitySettings.shadows = ShadowQuality.HardOnly;
        QualitySettings.shadowDistance = 28f;
        QualitySettings.pixelLightCount = 2;
        Input.multiTouchEnabled = true;

        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogColor = new Color(0.09f, 0.13f, 0.16f, 1f);
        RenderSettings.fogStartDistance = 22f;
        RenderSettings.fogEndDistance = 96f;
        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.24f, 0.30f, 0.34f, 1f);
        RenderSettings.reflectionIntensity = 0.34f;

        Light keyLight = null;
        var lights = FindObjectsOfType<Light>();
        for (int i = 0; i < lights.Length; i++)
        {
            if (lights[i] != null && lights[i].type == LightType.Directional)
            {
                keyLight = lights[i];
                break;
            }
        }
        if (keyLight == null)
        {
            var lightGO = new GameObject("Soft room key light");
            keyLight = lightGO.AddComponent<Light>();
        }

        keyLight.type = LightType.Directional;
        keyLight.color = new Color(0.68f, 0.79f, 0.87f);
        keyLight.intensity = 0.38f;
        keyLight.shadows = LightShadows.Hard;
        keyLight.shadowStrength = 0.16f;
        keyLight.transform.rotation = Quaternion.Euler(52f, -28f, 0f);
        RenderSettings.sun = keyLight;
    }

    void BuildMobileUI(FirstPersonRoomController player)
    {
        var uiGO = new GameObject("Room Mobile UI");
        uiGO.transform.SetParent(transform, false);
        var ui = uiGO.AddComponent<GameUI>();
        ui.Init(player);
    }

    static void EnsureEventSystem(Transform parent)
    {
        if (FindObjectOfType<EventSystem>() != null) return;
        var eventSystem = new GameObject("EventSystem");
        eventSystem.transform.SetParent(parent, false);
        eventSystem.AddComponent<EventSystem>();
        eventSystem.AddComponent<StandaloneInputModule>();
    }
}
