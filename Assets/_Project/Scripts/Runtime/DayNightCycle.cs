// ============================================================
// DayNightCycle.cs
//
// Pencahayaan Tahap 4: satu komponen yang memegang matahari, ambient,
// warna kabut, dan warna langit (clear color kamera -- project ini
// sengaja belum punya skydome; langit datar yang warnanya sama dengan
// kabut membuat cakrawala menyatu).
//
// DEFAULT = REALTIME: jam berjalan terus (satu hari game = DayMinutes
// menit dunia nyata), mulai pagi supaya kesan pertama cerah. Bisa
// dikunci ke jam tertentu lewat tombol kecil di sudut kiri-atas
// (Pagi / Siang / Sore / Malam / Realtime) -- game ini arena pribadi,
// jadi "cuaca" adalah mainan, bukan gangguan.
//
// Warna dan intensitas diinterpolasi dari tabel keyframe jam, bukan
// rumus astronomi: yang dicari adalah RASA (pagi keemasan, siang
// netral, sore jingga, malam biru), bukan akurasi.
// ============================================================
using UnityEngine;

namespace RPG.Runtime
{
    [DisallowMultipleComponent]
    public class DayNightCycle : MonoBehaviour
    {
        [Header("Matahari")]
        public Light Sun;

        [Header("Waktu")]
        [Tooltip("Jam berjalan sendiri mengikuti waktu nyata.")]
        public bool Realtime = true;

        [Tooltip("Berapa menit dunia nyata untuk satu hari game penuh.")]
        [Range(2f, 120f)] public float DayMinutes = 15f;

        [Tooltip("Jam saat scene mulai (0-24).")]
        [Range(0f, 24f)] public float StartHour = 8f;

        [HideInInspector] public float Hour;

        /* Tabel keyframe: jam, warna matahari, intensitas, ambient, kabut.
           Enam suasana: tengah malam, subuh, pagi, siang, senja, malam. */
        static readonly float[] KJam = { 0f,    4.8f,  6.5f,  9f,    15f,   17.8f, 19.5f, 24f };
        static readonly Color[] KSun =
        {
            new Color(0.35f, 0.42f, 0.60f),   // tengah malam: bulan biru redup
            new Color(0.45f, 0.42f, 0.55f),   // subuh
            new Color(1.00f, 0.72f, 0.45f),   // pagi keemasan
            new Color(1.00f, 0.96f, 0.88f),   // siang netral hangat
            new Color(1.00f, 0.93f, 0.80f),   // sore mulai miring
            new Color(1.00f, 0.55f, 0.28f),   // senja jingga
            new Color(0.45f, 0.40f, 0.60f),   // biru setelah matahari pergi
            new Color(0.35f, 0.42f, 0.60f),
        };
        static readonly float[] KInt = { 0.10f, 0.12f, 0.75f, 1.05f, 0.95f, 0.70f, 0.12f, 0.10f };
        static readonly Color[] KAmb =
        {
            new Color(0.10f, 0.12f, 0.20f),
            new Color(0.14f, 0.15f, 0.24f),
            new Color(0.42f, 0.40f, 0.38f),
            new Color(0.50f, 0.56f, 0.64f),
            new Color(0.48f, 0.50f, 0.56f),
            new Color(0.42f, 0.34f, 0.32f),
            new Color(0.14f, 0.15f, 0.26f),
            new Color(0.10f, 0.12f, 0.20f),
        };
        static readonly Color[] KFog =
        {
            new Color(0.05f, 0.06f, 0.10f),
            new Color(0.10f, 0.10f, 0.16f),
            new Color(0.62f, 0.55f, 0.48f),
            new Color(0.62f, 0.70f, 0.78f),
            new Color(0.66f, 0.66f, 0.70f),
            new Color(0.70f, 0.48f, 0.36f),
            new Color(0.10f, 0.11f, 0.18f),
            new Color(0.05f, 0.06f, 0.10f),
        };

        GUIStyle _style;
        int _button = 4;   // 4 = Realtime

        void Awake()
        {
            Hour = StartHour;
            if (Sun == null) Sun = Object.FindFirstObjectByType<Light>();
            Apply();
        }

        void Update()
        {
            if (Realtime && DayMinutes > 0f)
            {
                Hour += Time.deltaTime * (24f / (DayMinutes * 60f));
                if (Hour >= 24f) Hour -= 24f;
                Apply();
            }
        }

        /* Dipakai screenshot batchmode dan tombol suasana. */
        public void SetHour(float h, bool realtime)
        {
            Realtime = realtime;
            Hour = ((h % 24f) + 24f) % 24f;
            Apply();
        }

        public string Label =>
            $"waktu {Hour:F1} ({(Hour < 4.8f || Hour >= 19.5f ? "malam" :
                                  Hour < 6.5f ? "subuh" :
                                  Hour < 15f ? "siang" :
                                  Hour < 17.8f ? "sore" : "senja")})";

        void Apply()
        {
            /* Cari segmen keyframe. */
            var i = 0;
            while (i < KJam.Length - 2 && Hour >= KJam[i + 1]) i++;
            var span = Mathf.Max(0.0001f, KJam[i + 1] - KJam[i]);
            var t = Mathf.Clamp01((Hour - KJam[i]) / span);

            var sunCol = Color.Lerp(KSun[i], KSun[i + 1], t);
            var inten  = Mathf.Lerp(KInt[i], KInt[i + 1], t);
            var amb    = Color.Lerp(KAmb[i], KAmb[i + 1], t);
            var fog    = Color.Lerp(KFog[i], KFog[i + 1], t);

            if (Sun != null)
            {
                /* Matahari terbit dari timur (sumbu +X) dan terbenam di
                   barat; malam hari ia di bawah cakrawala dan yang
                   "tersisa" hanyalah cahaya bulan redup dari arah yang
                   sama, dibalik. */
                var ang = (Hour / 24f) * 360f - 90f;
                var rad = ang * Mathf.Deg2Rad;
                var dir = new Vector3(Mathf.Cos(rad), Mathf.Sin(rad), 0.30f);
                Sun.transform.rotation = Quaternion.LookRotation(-dir.normalized, Vector3.up);
                Sun.color = sunCol;
                Sun.intensity = inten;
            }

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = amb;
            RenderSettings.fogColor = fog;

            /* Langit = clear color kamera, sama dengan fog supaya
               cakrawala tidak punya garis batas. */
            var cam = Camera.main;
            if (cam != null)
            {
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = fog;
            }
        }

        /* Tombol suasana. Kecil dan di sudut supaya tidak mengganggu;
           IMGUI dipilih karena sudah dipakai PerfHud dan stik, jadi
           tidak menambah sistem UI baru di tahap ini. */
        void OnGUI()
        {
            if (_style == null)
            {
                _style = new GUIStyle(GUI.skin.button) { fontSize = 20 };
            }

            string[] label = { "Pagi", "Siang", "Sore", "Malam", "Realtime" };
            float[] jam    = { 6.5f, 12f, 17.2f, 21.5f, -1f };

            for (var i = 0; i < label.Length; i++)
            {
                var r = new Rect(12 + i * 108, Screen.height - 64, 100, 48);
                if (GUI.Button(r, label[i], _style))
                {
                    _button = i;
                    if (jam[i] < 0f) { Realtime = true; }
                    else SetHour(jam[i], false);
                }
            }

            var info = new Rect(12, Screen.height - 92, 500, 26);
            GUI.Label(info, Label + (_button == 4 ? "" : "  (dikunci)"), GUI.skin.label);
        }
    }
}
