using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       CAMERA RIG — kamera orang ketiga mengorbit.

       Jarak dan sensitivitas TIDAK punya default sendiri: keduanya
       diambil dari GameSettings, yang batasnya sudah dipatok di
       SettingsNormalizer (CameraDistance 3..8 default 5,
       Sensitivity 0,4..2 default 1).

       Perbaikan Tahap 5:
       [1] BUG MULTI-SENTUH: dulu hanya Input.GetTouch(0) yang dibaca,
           jadi kamera TIDAK BISA diputar sambil berjalan (jari 0
           dipegang stik). Sekarang semua jari dipindai.
       [2] Kamera bisa masuk ke dalam bukit. Sekarang dijepit di atas
           terrain (+ TerrainClearance).
       [3] FOV menendang saat sprint + screen-shake halus untuk
           tebasan/dash/mendarat (rasa RPG).
       ============================================================ */
    [DisallowMultipleComponent]
    public class CameraRig : MonoBehaviour
    {
        [Header("Target")]
        public Transform Target;
        [Tooltip("Tinggi titik fokus di atas kaki karakter.")]
        public float FocusHeight = 1.35f;
        [Tooltip("Dibaca untuk FOV sprint. Kosong = cari sendiri.")]
        public CharacterMotor Motor;

        [Header("Batas pitch (derajat)")]
        public float MinPitch = -35f;
        public float MaxPitch = 70f;
        public float StartPitch = 12f;

        [Header("Penghalusan")]
        public float PositionDamp = 12f;
        public float RotationDamp = 18f;

        [Header("Terrain")]
        [Tooltip("Jarak minimum kamera di atas tanah (m). Mencegah kamera masuk bukit.")]
        public float TerrainClearance = 0.4f;

        [Header("Rasa (game feel)")]
        public float BaseFov = 60f;
        [Tooltip("FOV saat sprint penuh.")]
        public float SprintFov = 67f;

        [Header("Sentuh / mouse")]
        [Tooltip("Kalau true, menyeret di mana pun memutar kamera (untuk HP). " +
                 "Kalau false, hanya tombol mouse kanan.")]
        public bool DragAnywhere = true;

        public float Yaw { get; private set; }
        public float Pitch { get; private set; }
        public GameSettings Settings { get; private set; }

        Camera _cam;
        int _dragId = int.MinValue;
        Vector2 _lastMouse;
        Vector2 _lastTouch;
        float _shake;

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
        }

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

        void LateUpdate()
        {
            ReadLookInput();

            if (Target == null) return;

            var focus = Target.position + Vector3.up * FocusHeight;
            var dist = (float)Settings.CameraDistance;

            var pitchRad = Pitch * Mathf.Deg2Rad;
            var yawRad = Yaw * Mathf.Deg2Rad;
            var offset = new Vector3(
                Mathf.Sin(yawRad) * Mathf.Cos(pitchRad),
                Mathf.Sin(pitchRad),
                Mathf.Cos(yawRad) * Mathf.Cos(pitchRad)) * -dist;

            var wantPos = focus + offset;

            // Jepit di atas terrain supaya tidak masuk bukit.
            var groundY = (float)WorldData.TerrainH(wantPos.x, wantPos.z)
                          + TerrainClearance;
            if (wantPos.y < groundY) wantPos.y = groundY;

            var wantRot = Quaternion.LookRotation(focus - wantPos, Vector3.up);

            /* Damp dari Locomotion, bukan SmoothDamp: laju penghalusan harus
               sama dengan yang dipakai karakter supaya kamera dan badan tidak
               terasa seperti dua sistem berbeda. */
            var dt = Time.deltaTime;
            transform.position = new Vector3(
                (float)Locomotion.Damp(transform.position.x, wantPos.x, PositionDamp, dt),
                (float)Locomotion.Damp(transform.position.y, wantPos.y, PositionDamp, dt),
                (float)Locomotion.Damp(transform.position.z, wantPos.z, PositionDamp, dt));
            transform.rotation = Quaternion.Slerp(transform.rotation, wantRot,
                1f - Mathf.Exp(-RotationDamp * dt));

            // Shake: getaran sinus dua frekuensi, meluruh cepat.
            if (_shake > 0.001f && dt > 0f)
            {
                _shake *= Mathf.Exp(-7f * dt);
                var t = Time.time;
                transform.position += new Vector3(
                    Mathf.Sin(t * 91f) * _shake * 0.06f,
                    Mathf.Sin(t * 113f + 1.7f) * _shake * 0.06f, 0f);
            }
            else _shake = 0f;

            // FOV menendang saat sprint/dash.
            if (_cam != null)
            {
                var run = Motor != null ? (float)Motor.Run01 : 0f;
                var dashKick = (Motor != null && Motor.IsDashing) ? 4f : 0f;
                var wantFov = BaseFov + (SprintFov - BaseFov) * run + dashKick;
                _cam.fieldOfView = (float)Locomotion.Damp(_cam.fieldOfView, wantFov, 6.0, dt);
            }
        }

        void ReadLookInput()
        {
            var sens = (float)Settings.Sensitivity;

            // ---- mouse (Editor & PC) ----
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

            // ---- sentuh (Android): SEMUA jari, bukan cuma jari 0 ----
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

        /* Zona stik kiri-bawah (koordinat sentuh: Y ke atas). Sentuhan yang
           mulai di sini milik joystick, bukan kamera. */
        static bool InStickZone(Vector2 p) =>
            p.x < Screen.width * 0.45f && p.y < Screen.height * 0.7f;

        void ApplyLook(float dx, float dy, float sens)
        {
            Yaw += dx * 0.12f * sens;
            Pitch = Mathf.Clamp(Pitch + dy * 0.10f * sens, MinPitch, MaxPitch);
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
