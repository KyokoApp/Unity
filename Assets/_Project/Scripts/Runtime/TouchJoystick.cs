using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       TOUCH JOYSTICK — stik virtual untuk Android.

       Sengaja TIDAK pakai uGUI/Canvas di Tahap 2. HUD yang sebenarnya
       baru dikerjakan di Tahap 5 (lihat DESAIN.md), dan membangun
       Canvas sekarang hanya untuk dibongkar lagi nanti adalah kerja
       ganda. Versi ini membaca Touch langsung dan menggambar dirinya
       lewat OnGUI — cukup untuk membuktikan karakter bisa dikendalikan
       dari layar sentuh.

       Yang penting: sumbunya dihitung dengan Locomotion.JoystickAxis(),
       fungsi yang SUDAH diuji paritas terhadap game aslinya. Jadi
       deadzone 0,14 dan perilaku "amount" setelah deadzone persis
       sama dengan versi three.js, bukan karangan baru.

       Radius 55 px adalah angka asli dari game lama (diameter stik
       110 px), dikalikan ButtonScale dari setelan.
       ============================================================ */
    [DisallowMultipleComponent]
    public class TouchJoystick : MonoBehaviour
    {
        [Header("Bentuk")]
        [Tooltip("Radius stik dalam piksel pada acuan tinggi layar 800 px. " +
                 "55 = angka asli game lama.")]
        public float BaseRadiusPx = 55f;
        [Tooltip("Kalau true, radius diskalakan menurut tinggi layar supaya " +
                 "terasa sama di HP kecil dan besar.")]
        public bool ScaleWithScreen = true;
        public float ReferenceScreenHeight = 800f;

        [Header("Wilayah")]
        [Tooltip("Bagian layar kiri-bawah yang menerima sentuhan, sebagai fraksi.")]
        [Range(0.2f, 1f)] public float ZoneWidthFraction  = 0.5f;
        [Range(0.2f, 1f)] public float ZoneHeightFraction = 0.6f;

        [Header("Tombol")]
        public bool ShowRunButton  = true;
        public bool ShowJumpButton = true;

        [Header("Tampilan")]
        public bool Visible = true;
        public Color RingColor  = new Color(1f, 1f, 1f, 0.35f);
        public Color KnobColor  = new Color(1f, 1f, 1f, 0.60f);
        public Color ButtonColor = new Color(1f, 1f, 1f, 0.25f);

        /* ---- dibaca CharacterMotor ---- */
        public Locomotion.Axis Axis { get; private set; }
        public bool IsActive { get; private set; }
        public bool RunHeld { get; private set; }
        public bool JumpPressed { get; private set; }

        int _finger = int.MinValue;
        Vector2 _origin;
        Texture2D _dot;
        double _buttonScale = 1.0;

        void Awake()
        {
            var s = SettingsStore.Load();
            _buttonScale = s.ButtonScale;
        }

        void OnDestroy()
        {
            ObjectUtil.SafeDestroy(_dot);
        }

        public float RadiusPx =>
            BaseRadiusPx * (float)_buttonScale *
            (ScaleWithScreen ? Mathf.Max(0.4f, Screen.height / ReferenceScreenHeight) : 1f);

        void Update()
        {
            JumpPressed = false;
            PollStick();
            PollButtons();
        }

        void PollStick()
        {
            for (var i = 0; i < Input.touchCount; i++)
            {
                var t = Input.GetTouch(i);

                if (t.phase == TouchPhase.Began && _finger == int.MinValue && InZone(t.position))
                {
                    _finger = t.fingerId;
                    _origin = t.position;
                }

                if (t.fingerId != _finger) continue;

                if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled)
                {
                    _finger = int.MinValue;
                    IsActive = false;
                    Axis = new Locomotion.Axis(0, 0);
                    continue;
                }

                var delta = t.position - _origin;
                IsActive = true;
                /* Y layar sudah mengarah ke atas, jadi +delta.y = maju. */
                Axis = Locomotion.JoystickAxis(delta.x, delta.y, RadiusPx);
                return;
            }

            if (_finger == int.MinValue)
            {
                IsActive = false;
                Axis = new Locomotion.Axis(0, 0);
            }
        }

        void PollButtons()
        {
            RunHeld = false;
            if (!ShowRunButton && !ShowJumpButton) return;

            for (var i = 0; i < Input.touchCount; i++)
            {
                var t = Input.GetTouch(i);
                if (t.fingerId == _finger) continue;

                if (ShowRunButton && RunButtonRect().Contains(t.position))
                {
                    RunHeld = t.phase != TouchPhase.Ended && t.phase != TouchPhase.Canceled;
                }
                if (ShowJumpButton && JumpButtonRect().Contains(t.position) &&
                    t.phase == TouchPhase.Began)
                {
                    JumpPressed = true;
                }
            }
        }

        bool InZone(Vector2 p)
        {
            if (ShowRunButton  && RunButtonRect().Contains(p))  return false;
            if (ShowJumpButton && JumpButtonRect().Contains(p)) return false;
            return p.x < Screen.width * ZoneWidthFraction &&
                   p.y < Screen.height * ZoneHeightFraction;
        }

        Rect RunButtonRect()
        {
            var s = 96f * (float)_buttonScale;
            return new Rect(Screen.width - s - 24f, 24f, s, s);
        }

        Rect JumpButtonRect()
        {
            var s = 96f * (float)_buttonScale;
            return new Rect(Screen.width - s - 24f, 24f + s + 16f, s, s);
        }

        GUIStyle _labelStyle;
        GUIStyle LabelStyle
        {
            get
            {
                if (_labelStyle == null)
                {
                    _labelStyle = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleCenter };
                    _labelStyle.normal.textColor = Color.white;
                }
                _labelStyle.fontSize = Mathf.Max(11, Mathf.RoundToInt(14f * (float)_buttonScale));
                return _labelStyle;
            }
        }

        // ------------------------------------------------------------------
        void OnGUI()
        {
            if (!Visible) return;
            EnsureDot();

            if (ShowRunButton)
                DrawButton(RunButtonRect(), RunHeld ? "LARI" : "lari");
            if (ShowJumpButton)
                DrawButton(JumpButtonRect(), "LOMPAT");

            if (!IsActive) return;

            /* OnGUI memakai koordinat Y ke bawah; Touch.position Y ke atas. */
            var originGui = new Vector2(_origin.x, Screen.height - _origin.y);
            var r = RadiusPx;
            DrawCircle(originGui, r, RingColor);

            var knob = originGui + new Vector2((float)Axis.X, -(float)Axis.Y) * r;
            DrawCircle(knob, r * 0.42f, KnobColor);
        }

        void DrawButton(Rect rect, string label)
        {
            var gui = new Rect(rect.x, Screen.height - rect.yMax, rect.width, rect.height);
            var prev = GUI.color;
            GUI.color = ButtonColor;
            GUI.DrawTexture(gui, _dot);
            GUI.color = prev;
            GUI.Label(gui, label, LabelStyle);
        }

        void DrawCircle(Vector2 centerGui, float radius, Color color)
        {
            var rect = new Rect(centerGui.x - radius, centerGui.y - radius, radius * 2f, radius * 2f);
            var prev = GUI.color;
            GUI.color = color;
            GUI.DrawTexture(rect, _dot);
            GUI.color = prev;
        }

        /* Satu tekstur bulat 64x64 dipakai untuk semua elemen. Dibuat sekali,
           tanpa aset eksternal, supaya preview sandbox tetap jalan. */
        void EnsureDot()
        {
            if (_dot != null) return;
            const int S = 64;
            _dot = new Texture2D(S, S, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            var px = new Color32[S * S];
            var c = (S - 1) * 0.5f;
            for (var y = 0; y < S; y++)
            for (var x = 0; x < S; x++)
            {
                var d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c)) / c;
                byte a = (byte)(255 * Mathf.Clamp01((1f - d) * 6f));
                px[y * S + x] = new Color32(255, 255, 255, a);
            }
            _dot.SetPixels32(px);
            _dot.Apply(false, false);
        }
    }
}
