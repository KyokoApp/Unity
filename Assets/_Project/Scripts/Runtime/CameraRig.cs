using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       CAMERA RIG — kamera orang ketiga mengorbit.

       Jarak dan sensitivitas TIDAK punya default sendiri: keduanya
       diambil dari GameSettings, yang batasnya sudah dipatok di
       SettingsNormalizer (CameraDistance 3..8 default 5,
       Sensitivity 0,4..2 default 1). Menaruh angka lain di sini
       berarti menyimpang dari hasil port yang sudah dites paritas.

       Fase 2 cuma butuh orbit + ikut karakter. Tabrakan kamera
       dengan terrain dan mode sinematik menyusul di Fase 7.
       ============================================================ */
    [DisallowMultipleComponent]
    public class CameraRig : MonoBehaviour
    {
        [Header("Target")]
        public Transform Target;
        [Tooltip("Tinggi titik fokus di atas kaki karakter.")]
        public float FocusHeight = 1.35f;

        [Header("Batas pitch (derajat)")]
        public float MinPitch = -35f;
        public float MaxPitch = 70f;
        public float StartPitch = 12f;

        [Header("Penghalusan")]
        public float PositionDamp = 12f;
        public float RotationDamp = 18f;

        [Header("Sentuh / mouse")]
        [Tooltip("Kalau true, menyeret di mana pun memutar kamera (untuk HP). " +
                 "Kalau false, hanya tombol mouse kanan.")]
        public bool DragAnywhere = true;

        public float Yaw { get; private set; }
        public float Pitch { get; private set; }
        public GameSettings Settings { get; private set; }

        Camera _cam;
        TouchJoystick _joystick;
        SettingsPanel _settingsPanel;
        int _dragId = int.MinValue;
        Vector2 _lastMouse;
        Vector2 _lastTouch;

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

            // FIX: pastikan camera clear solid color untuk hindari jejak
            _cam.clearFlags = CameraClearFlags.SolidColor;
            if (_cam.backgroundColor.a < 0.9f)
            {
                var c = _cam.backgroundColor;
                c.a = 1f;
                _cam.backgroundColor = c;
            }

            Settings = SettingsStore.Load();
            Pitch = StartPitch;
            if (Target == null)
            {
                var motor = FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
            _joystick = FindFirstObjectByType<TouchJoystick>();
            _settingsPanel = FindFirstObjectByType<SettingsPanel>();
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

            if (_cam != null) _cam.fieldOfView = 60f;
        }

        void ReadLookInput()
        {
            var sens = (float)Settings.Sensitivity;

            // Jika setting panel terbuka, jangan putar kamera
            if (_settingsPanel != null && _settingsPanel.Visible) return;

            // ---- mouse (Editor & PC) ----
            if (Input.GetMouseButtonDown(1) || (DragAnywhere && Input.GetMouseButtonDown(0)
                && !IsPointerOverUi()))
            {
                // Jangan mulai drag kalau di area joystick
                if (_joystick != null && Input.mousePosition.x < Screen.width * 0.5f && Input.mousePosition.y < Screen.height * 0.6f)
                {
                    // kemungkinan joystick, skip
                }
                else
                {
                    _dragId = -1;
                    _lastMouse = Input.mousePosition;
                }
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

            // ---- sentuh (Android) ----
            // FIX: hindari konflik dengan joystick — kalau touch di zona joystick, jangan pakai untuk kamera
            if (Input.touchCount > 0)
            {
                for (int i = 0; i < Input.touchCount; i++)
                {
                    var t = Input.GetTouch(i);
                    // Skip kalau ini finger joystick
                    if (_joystick != null && _joystick.IsActive)
                    {
                        // Joystick sudah pakai satu finger, jangan ambil finger itu untuk kamera
                        // Dan jangan ambil touch di zona joystick
                        if (t.position.x < Screen.width * 0.5f && t.position.y < Screen.height * 0.6f)
                            continue;
                    }

                    if (t.phase == TouchPhase.Began && !IsPointerOverUi(t))
                    {
                        // Cek lagi: kalau di zona joystick, skip
                        if (t.position.x < Screen.width * 0.5f && t.position.y < Screen.height * 0.6f)
                            continue;
                        _dragId = t.fingerId;
                        _lastTouch = t.position;
                        break;
                    }
                    else if (t.fingerId == _dragId &&
                             (t.phase == TouchPhase.Moved || t.phase == TouchPhase.Stationary))
                    {
                        ApplyLook((t.position - _lastTouch).x, (t.position - _lastTouch).y, sens);
                        _lastTouch = t.position;
                        break;
                    }
                    else if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                    {
                        if (t.fingerId == _dragId) _dragId = int.MinValue;
                    }
                }
            }
        }

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
