using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       CAMERA RIG — orang ketiga rapat di belakang karakter.

       Jarak visual TIDAK memakai CameraDistance (3..8 m) mentah:
       angka itu tingkat zoom menu (paritas JS). Dipetakan ke
       2,35..4,40 m oleh CameraFraming supaya framing-nya Genshin
       (karakter mengisi ~1/3 bawah layar), bukan semut di padang.

       Perbaikan Tahap 5 / 5d:
       [1] BUG MULTI-SENTUH: semua jari dipindai, bukan cuma GetTouch(0).
       [2] Kamera dijepit di atas terrain.
       [3] FOV menendang saat sprint + screen-shake.
       [4] Pitch positif = kamera DI ATAS (dulu rumus spherical
           menaruh kamera DI BAWAH fokus — sudut aneh + jarak terasa
           jauh). Sekarang Quaternion.Euler ala Unity/Genshin.
       [5] SnapNow saat OnEnable: tidak damping dari 8 m jauhnya.
       ============================================================ */
    [DisallowMultipleComponent]
    public class CameraRig : MonoBehaviour
    {
        [Header("Target")]
        public Transform Target;
        [Tooltip("Tinggi titik fokus di atas kaki karakter (dada/leher).")]
        public float FocusHeight = (float)CameraFraming.DefaultFocusHeight;
        [Tooltip("Geser ke kanan bahu, meter. 0 = tepat di belakang.")]
        public float ShoulderOffset = (float)CameraFraming.DefaultShoulder;
        [Tooltip("Dibaca untuk FOV sprint. Kosong = cari sendiri.")]
        public CharacterMotor Motor;

        [Header("Batas pitch (derajat, positif = dari atas)")]
        public float MinPitch = -8f;
        public float MaxPitch = 55f;
        public float StartPitch = (float)CameraFraming.DefaultPitchDeg;

        [Header("Penghalusan")]
        public float PositionDamp = 18f;
        public float RotationDamp = 22f;

        [Header("Terrain")]
        [Tooltip("Jarak minimum kamera di atas tanah (m).")]
        public float TerrainClearance = 0.35f;

        [Header("Rasa (game feel)")]
        public float BaseFov = 50f;
        [Tooltip("FOV saat sprint penuh.")]
        public float SprintFov = 56f;

        [Header("Sentuh / mouse")]
        [Tooltip("Kalau true, menyeret di mana pun memutar kamera (untuk HP). " +
                 "Kalau false, hanya tombol mouse kanan.")]
        public bool DragAnywhere = true;

        public float Yaw { get; private set; }
        public float Pitch { get; private set; }
        public GameSettings Settings { get; private set; }
        public float FramingMeters =>
            (float)CameraFraming.MetersFromSettings(
                Settings != null ? Settings.CameraDistance : CameraFraming.SettingsDefault);

        Camera _cam;
        int _dragId = int.MinValue;
        Vector2 _lastMouse;
        Vector2 _lastTouch;
        float _shake;
        bool _snap = true;

        void Awake()
        {
            /* Paksa landscape. Dunia terbuka dengan stik virtual di kiri dan
               tombol lari/lompat di kanan tidak terbaca dalam portrait, dan
               game fantasi ingin cakrawala lebar. PlayerSettings sudah diset
               LandscapeLeft; ini jaring pengaman supaya Play di Editor (dan
               build lama yang belum punya setelan itu) ikut benar. */
            if (Screen.orientation != ScreenOrientation.LandscapeLeft &&
                Screen.orientation != ScreenOrientation.LandscapeRight)
            {
                Screen.orientation = ScreenOrientation.LandscapeLeft;
            }

            _cam = GetComponent<Camera>();
            if (_cam == null) _cam = gameObject.AddComponent<Camera>();

            Settings = SettingsStore.Load();
            Pitch = StartPitch;
            if (Target == null)
            {
                var motor = FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
            if (Motor == null) Motor = FindFirstObjectByType<CharacterMotor>();
            _snap = true;
        }

        void OnEnable() { _snap = true; }

        public void SetDistance(double meters)
        {
            Settings = SettingsStore.WithCameraDistance(Settings, meters);
            SettingsStore.Save(Settings);
        }

        public void SetSensitivity(double value)
        {
            Settings = SettingsStore.WithSensitivity(Settings, value);
            SettingsStore.Save(Settings);
        }

        /* Dipanggil panel pengaturan setelah nilai berubah. */
        public void RefreshSettings() { Settings = SettingsStore.Load(); }

        /* Guncangan kamera 0..1 (tebasan, dash, mendarat). */
        public void AddShake(float amount)
        {
            _shake = Mathf.Clamp(_shake + amount, 0f, 1f);
        }

        /* Paksa kamera ke posisi target TANPA damping. Dipakai boot
           (OnEnable setelah loading) dan SceneShots. */
        public void SnapNow()
        {
            _snap = true;
            if (Target == null) return;
            ComputeWant(out var pos, out var rot);
            transform.position = pos;
            transform.rotation = rot;
            _snap = false;
        }

        /* Dipakai SceneShots + builder supaya screenshot = framing in-game. */
        public static void PlaceBehind(Transform cam, Vector3 targetPos,
            float yawDeg, float pitchDeg, float dist, float focusHeight, float shoulder)
        {
            if (cam == null) return;
            CameraFraming.OrbitOffset(yawDeg, pitchDeg, dist,
                out var ox, out var oy, out var oz);
            var focus = targetPos + Vector3.up * focusHeight;
            var yawRad = yawDeg * Mathf.Deg2Rad;
            var right = new Vector3(Mathf.Cos(yawRad), 0f, -Mathf.Sin(yawRad));
            var pos = focus + new Vector3((float)ox, (float)oy, (float)oz) + right * shoulder;
            var look = targetPos + Vector3.up * (focusHeight + 0.06f);
            cam.position = pos;
            var dir = look - pos;
            if (dir.sqrMagnitude > 1e-8f)
                cam.rotation = Quaternion.LookRotation(dir, Vector3.up);
        }

        void LateUpdate()
        {
            ReadLookInput();
            if (Target == null) return;

            ComputeWant(out var wantPos, out var wantRot);

            if (_snap)
            {
                transform.position = wantPos;
                transform.rotation = wantRot;
                _snap = false;
            }
            else
            {
                var dt = Time.deltaTime;
                transform.position = new Vector3(
                    (float)Locomotion.Damp(transform.position.x, wantPos.x, PositionDamp, dt),
                    (float)Locomotion.Damp(transform.position.y, wantPos.y, PositionDamp, dt),
                    (float)Locomotion.Damp(transform.position.z, wantPos.z, PositionDamp, dt));
                transform.rotation = Quaternion.Slerp(transform.rotation, wantRot,
                    1f - Mathf.Exp(-RotationDamp * dt));
            }

            var shakeDt = Time.deltaTime;
            if (_shake > 0.001f && shakeDt > 0f)
            {
                _shake *= Mathf.Exp(-7f * shakeDt);
                var t = Time.time;
                transform.position += new Vector3(
                    Mathf.Sin(t * 91f) * _shake * 0.05f,
                    Mathf.Sin(t * 113f + 1.7f) * _shake * 0.05f, 0f);
            }
            else _shake = 0f;

            if (_cam != null)
            {
                var run = Motor != null ? (float)Motor.Run01 : 0f;
                var dashKick = (Motor != null && Motor.IsDashing) ? 3f : 0f;
                var wantFov = BaseFov + (SprintFov - BaseFov) * run + dashKick;
                _cam.fieldOfView = (float)Locomotion.Damp(_cam.fieldOfView, wantFov, 6.0, Time.deltaTime);
            }
        }

        void ComputeWant(out Vector3 wantPos, out Quaternion wantRot)
        {
            var dist = FramingMeters;
            CameraFraming.OrbitOffset(Yaw, Pitch, dist, out var ox, out var oy, out var oz);
            var focus = Target.position + Vector3.up * FocusHeight;
            var yawRad = Yaw * Mathf.Deg2Rad;
            var right = new Vector3(Mathf.Cos(yawRad), 0f, -Mathf.Sin(yawRad));
            wantPos = focus + new Vector3((float)ox, (float)oy, (float)oz)
                      + right * ShoulderOffset;

            var groundY = (float)WorldData.TerrainH(wantPos.x, wantPos.z) + TerrainClearance;
            if (wantPos.y < groundY) wantPos.y = groundY;

            var look = Target.position + Vector3.up * (FocusHeight + 0.06f);
            var dir = look - wantPos;
            wantRot = dir.sqrMagnitude > 1e-8f
                ? Quaternion.LookRotation(dir, Vector3.up)
                : transform.rotation;
        }

        void ReadLookInput()
        {
            var sens = Settings != null ? (float)Settings.Sensitivity : 1f;

            if (Input.GetMouseButtonDown(1) || (DragAnywhere && Input.GetMouseButtonDown(0)
                && !IsPointerOverUi()))
            {
                _dragId = -1;
                _lastMouse = Input.mousePosition;
            }
            if (_dragId == -1)
            {
                if (Input.GetMouseButton(1) || (DragAnywhere && Input.GetMouseButton(0)))
                {
                    var cur = (Vector2)Input.mousePosition;
                    ApplyLook((cur - _lastMouse).x, (cur - _lastMouse).y, sens);
                    _lastMouse = cur;
                }
                else _dragId = int.MinValue;
            }

            for (var i = 0; i < Input.touchCount; i++)
            {
                var t = Input.GetTouch(i);
                if (t.phase == TouchPhase.Began
                    && _dragId == int.MinValue
                    && !IsPointerOverUi(t)
                    && !InStickZone(t.position))
                {
                    _dragId = t.fingerId;
                    _lastTouch = t.position;
                }
                else if (t.fingerId == _dragId)
                {
                    if (t.phase == TouchPhase.Moved || t.phase == TouchPhase.Stationary)
                    {
                        ApplyLook((t.position - _lastTouch).x, (t.position - _lastTouch).y, sens);
                        _lastTouch = t.position;
                    }
                    else if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                    {
                        _dragId = int.MinValue;
                    }
                }
            }
            if (Input.touchCount == 0 && _dragId >= 0) _dragId = int.MinValue;
        }

        static bool InStickZone(Vector2 p) =>
            p.x < Screen.width * 0.45f && p.y < Screen.height * 0.7f;

        void ApplyLook(float dx, float dy, float sens)
        {
            Yaw += dx * 0.12f * sens;
            Pitch = Mathf.Clamp(Pitch - dy * 0.10f * sens, MinPitch, MaxPitch);
            if (Yaw > 360f) Yaw -= 360f;
            else if (Yaw < -360f) Yaw += 360f;
        }

        static bool IsPointerOverUi() =>
            UnityEngine.EventSystems.EventSystem.current != null &&
            UnityEngine.EventSystems.EventSystem.current.IsPointerOverGameObject();

        static bool IsPointerOverUi(Touch t) =>
            UnityEngine.EventSystems.EventSystem.current != null &&
            UnityEngine.EventSystems.EventSystem.current.IsPointerOverGameObject(t.fingerId);
    }
}
