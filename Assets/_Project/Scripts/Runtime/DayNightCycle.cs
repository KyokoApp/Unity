// ============================================================
// DayNightCycle.cs
//
// Pencahayaan: matahari + ambient + kabut + LANGIT GRADIEN.
// Langit (AureliaSky) digerakkan dari tabel keyframe yang sama,
// jadi horizon dan kabut selalu senada — trik utama tampilan
// stylized yang "menyatu".
//
// CATATAN soal SDFGI/HDDAGI: itu fitur GODOT, tidak ada di Unity.
// Di URP mobile, padanannya yang benar untuk gaya stylized BUKAN
// realtime GI (terlalu mahal untuk HP), melainkan: 1 directional
// light + ambient datar/trilight yang di-keyframe + skybox gradien
// + fog berwarna. Persis yang dilakukan komponen ini.
//
// Perbaikan Tahap 5: kamera di-cache (dulu Camera.main tiap frame),
// tombol tidak alokasi per frame, bayangan mati otomatis di malam
// hari (hemat shadow pass), tombol pindah ke atas-tengah supaya
// tidak menutupi stik.
// ============================================================
using UnityEngine;

namespace RPG.Runtime
{
    [DisallowMultipleComponent]
    public class DayNightCycle : MonoBehaviour
    {
        [Header("Matahari & langit")]
        public Light Sun;
        [Tooltip("Material langit Aurelia/Sky. Kosong = langit warna datar (fallback lama).")]
        public Material SkyMaterial;

        [Header("Waktu")]
        [Tooltip("Jam berjalan sendiri mengikuti waktu nyata.")]
        public bool Realtime = true;

        [Tooltip("Berapa menit dunia nyata untuk satu hari game penuh.")]
        [Range(2f, 120f)] public float DayMinutes = 15f;

        [Tooltip("Jam saat scene mulai (0-24).")]
        [Range(0f, 24f)] public float StartHour = 8f;

        [HideInInspector] public float Hour;

        [Header("Tombol suasana (alat dev)")]
        [Tooltip("Default mati: tombol Pagi/Siang menumpuk kompas HUD. F2 untuk tampilkan.")]
        public bool ShowButtons = false;

        /* Tabel keyframe: jam, warna matahari, intensitas, ambient, kabut,
           + warna langit (zenith & horizon). Enam suasana. */
        static readonly float[] KJam = { 0f,    4.8f,  6.5f,  9f,    15f,   17.8f, 19.5f, 24f };
        static readonly Color[] KSun =
        {
            new Color(0.35f, 0.42f, 0.60f),
            new Color(0.45f, 0.42f, 0.55f),
            new Color(1.00f, 0.72f, 0.45f),
            new Color(1.00f, 0.96f, 0.88f),
            new Color(1.00f, 0.93f, 0.80f),
            new Color(1.00f, 0.55f, 0.28f),
            new Color(0.45f, 0.40f, 0.60f),
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
        static readonly Color[] KTop =
        {
            new Color(0.015f, 0.025f, 0.07f),
            new Color(0.10f, 0.12f, 0.22f),
            new Color(0.45f, 0.58f, 0.78f),
            new Color(0.36f, 0.55f, 0.82f),
            new Color(0.38f, 0.56f, 0.80f),
            new Color(0.28f, 0.30f, 0.52f),
            new Color(0.05f, 0.06f, 0.14f),
            new Color(0.015f, 0.025f, 0.07f),
        };
        static readonly Color[] KHor =
        {
            new Color(0.07f, 0.09f, 0.16f),
            new Color(0.28f, 0.24f, 0.30f),
            new Color(0.98f, 0.78f, 0.58f),
            new Color(0.75f, 0.82f, 0.88f),
            new Color(0.76f, 0.78f, 0.82f),
            new Color(1.00f, 0.62f, 0.36f),
            new Color(0.16f, 0.14f, 0.24f),
            new Color(0.07f, 0.09f, 0.16f),
        };

        static readonly string[] BtnLabel = { "Pagi", "Siang", "Sore", "Malam", "Live" };
        static readonly float[] BtnJam    = { 6.5f, 12f, 17.2f, 21.5f, -1f };

        static readonly int SunDirId = Shader.PropertyToID("_SunDirection");
        static readonly int TopId = Shader.PropertyToID("_TopColor");
        static readonly int HorId = Shader.PropertyToID("_HorizonColor");
        static readonly int SunColId = Shader.PropertyToID("_SunColor");

        GUIStyle _style;
        Camera _cam;
        bool _allowShadows = true;

        void Awake()
        {
            Hour = StartHour;
            if (Sun == null) Sun = Object.FindFirstObjectByType<Light>();
            _cam = Camera.main;
            RefreshSettings();
            Apply();
        }

        void Update()
        {
            if (Input.GetKeyDown(KeyCode.F2)) ShowButtons = !ShowButtons;
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

        /* Dipanggil panel pengaturan setelah nilai berubah. */
        public void RefreshSettings()
        {
            _allowShadows = SettingsStore.Load().Shadows;
            Apply();
        }

        public string Label
        {
            get
            {
                string suasana;
                if (Hour < 4.8f || Hour >= 19.5f) suasana = "malam";
                else if (Hour < 6.5f) suasana = "subuh";
                else if (Hour < 15f) suasana = "siang";
                else if (Hour < 17.8f) suasana = "sore";
                else suasana = "senja";
                return $"waktu {Hour:F1} ({suasana})";
            }
        }

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
            var top    = Color.Lerp(KTop[i], KTop[i + 1], t);
            var hor    = Color.Lerp(KHor[i], KHor[i + 1], t);

            if (Sun != null)
            {
                var ang = (Hour / 24f) * 360f - 90f;
                var rad = ang * Mathf.Deg2Rad;
                var dir = new Vector3(Mathf.Cos(rad), Mathf.Sin(rad), 0.30f);
                Sun.transform.rotation = Quaternion.LookRotation(-dir.normalized, Vector3.up);
                Sun.color = sunCol;
                Sun.intensity = inten;
                // Malam hari: bayangan mati (cahaya 0,1 nyaris tak terlihat,
                // tapi shadow pass-nya tetap dibayar kalau menyala).
                Sun.shadows = (_allowShadows && inten > 0.25f)
                    ? LightShadows.Soft : LightShadows.None;
            }

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = amb;
            RenderSettings.fogColor = fog;

            if (SkyMaterial != null)
            {
                SkyMaterial.SetColor(TopId, top);
                SkyMaterial.SetColor(HorId, hor);
                SkyMaterial.SetColor(SunColId, sunCol);
                if (Sun != null)
                {
                    var toSun = Sun.transform.rotation * new Vector3(0f, 0f, -1f);
                    SkyMaterial.SetVector(SunDirId,
                        new Vector4(toSun.x, toSun.y, toSun.z, 0f));
                }
            }

            if (_cam == null) _cam = Camera.main;
            /* HP: SolidColor horizon. Editor: skybox. backgroundColor
               selalu diisi supaya clear Skybox yang gagal tidak hitam. */
            WorldLook.ApplySky(_cam, SkyMaterial, hor);
        }

        void OnGUI()
        {
            if (!ShowButtons || LoadingScreen.IsShown) return;
            if (_style == null)
            {
                _style = new GUIStyle(GUI.skin.button) { fontSize = 18 };
            }

            const float bw = 84f, bh = 38f, gap = 6f;
            var total = BtnLabel.Length * bw + (BtnLabel.Length - 1) * gap;
            var x0 = (Screen.width - total) * 0.5f;
            for (var i = 0; i < BtnLabel.Length; i++)
            {
                var r = new Rect(x0 + i * (bw + gap), 10f, bw, bh);
                if (GUI.Button(r, BtnLabel[i], _style))
                {
                    if (BtnJam[i] < 0f) { Realtime = true; }
                    else SetHour(BtnJam[i], false);
                }
            }
        }
    }
}
