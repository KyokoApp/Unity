using System.Collections.Generic;
using System.Text;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       PERF HUD — angka, bukan perasaan.

       "Rasanya lancar" tidak bisa dipakai untuk memutuskan apa pun.
       HUD ini menampilkan tiga hal yang menentukan apakah game ini
       benar-benar 50 fps di HP-mu:

         1. Waktu frame min/rata-rata/maks + jumlah SPIKE.
            Rata-rata 20 ms bisa saja berarti 60 frame @ 16 ms dan
            1 frame @ 260 ms. Yang terasa di tangan adalah spike,
            dan rata-rata menyembunyikannya.

         2. Jumlah GC generasi-0 per detik.
            Setiap koleksi gen-0 adalah jeda. Kalau angka ini naik
            saat karakter berlari, ada alokasi per frame yang harus
            dicari — biasanya membaca balik properti Unity yang
            mengalokasikan (Mesh.triangles, Mesh.vertices,
            GetComponents<T>(), string di Update).

         3. Statistik terrain, termasuk waktu build di thread latar
            dan waktu upload di main thread. Dua angka itu terpisah
            karena hanya yang kedua yang memotong budget frame.

       Cara pakai: tempel di GameObject mana pun di scene, atau
       panggil Tools > Aurelia > 6. Pasang Perf HUD.
       Sembunyikan/tampilkan: tombol F1 (desktop) atau ketuk sudut
       kanan-atas 3 kali (HP).

       HUD ini memakai OnGUI, yang sendiri punya biaya. Untuk angka
       yang benar-benar bersih, pakai profiler Unity. Tapi untuk
       "apakah ini 50 fps dan di mana sentakannya", ini cukup dan
       bisa dibaca langsung di layar HP tanpa kabel.
       ============================================================ */
    [DisallowMultipleComponent]
    public class PerfHud : MonoBehaviour
    {
        [Header("Tampilan")]
        [Tooltip("Tampilkan HUD saat mulai. Matikan untuk build rilis.")]
        public bool Visible = true;

        [Tooltip("Ukuran font. 26 cukup terbaca di layar HP 6 inci.")]
        [Range(14, 48)] public int FontSize = 26;

        [Tooltip("Panjang jendela pengukuran dalam frame. 300 frame @ 50 fps = 6 detik.")]
        [Range(30, 600)] public int Window = 300;

        [Tooltip("Frame di atas ambang ini dihitung sebagai spike (ms).")]
        public float SpikeMs = 33f;

        [Header("Sumber")]
        public TerrainChunkStreamer Streamer;
        public WaterPlane Water;
        public GrassField Grass;
        public DayNightCycle Cycle;

        readonly Queue<float> _samples = new Queue<float>();
        readonly StringBuilder _sb = new StringBuilder(512);

        float _sum, _min = float.MaxValue, _max;
        int _spikes;
        float _fpsSmoothed;
        int _gc0Last, _gcPerSec;
        float _gcTimer;
        int _tapCount;
        float _tapTimer;
        GUIStyle _style;

        void Reset()
        {
            if (Streamer == null) Streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            if (Water == null) Water = FindFirstObjectByType<WaterPlane>();
        }

        void Update()
        {
            /* unscaledDeltaTime, bukan deltaTime: HUD harus tetap jujur
               walaupun Time.timeScale dipakai untuk jeda nanti. */
            var dt = Time.unscaledDeltaTime;
            if (dt <= 0f) return;

            var ms = dt * 1000f;
            _samples.Enqueue(ms);
            while (_samples.Count > Window) _sum -= _samples.Dequeue();
            _sum += ms;
            if (ms < _min) _min = ms;
            if (ms > _max) _max = ms;
            if (ms > SpikeMs) _spikes++;

            _fpsSmoothed += (1f / dt - _fpsSmoothed) * 0.1f;

            /* GC gen-0 per detik. CollectionCount(0) tersedia di semua
               profil .NET yang didukung Unity, dan murah. */
            _gcTimer += dt;
            if (_gcTimer >= 1f)
            {
                var now = System.GC.CollectionCount(0);
                _gcPerSec = now - _gc0Last;
                _gc0Last = now;
                _gcTimer = 0f;
                /* reset jendela tiap detik supaya spike tidak menumpuk
                   jadi angka yang tidak berarti setelah 10 menit main */
                _min = float.MaxValue; _max = 0f; _spikes = 0;
            }

            ToggleInput();
        }

        void ToggleInput()
        {
            if (Input.GetKeyDown(KeyCode.F1)) { Visible = !Visible; return; }

            /* Ketuk sudut kanan-atas 3 kali dalam 1 detik. Tidak pakai tombol
               visible supaya HUD tidak menutupi layar saat dimainkan. */
            _tapTimer -= Time.unscaledDeltaTime;
            if (_tapTimer <= 0f) _tapCount = 0;
            if (Input.GetMouseButtonDown(0))
            {
                var p = Input.mousePosition;
                if (p.x > Screen.width - 140 && p.y > Screen.height - 140)
                {
                    _tapCount++;
                    _tapTimer = 1f;
                    if (_tapCount >= 3) { Visible = !Visible; _tapCount = 0; }
                }
            }
        }

        GUIStyle Style
        {
            get
            {
                if (_style == null || _style.fontSize != FontSize)
                {
                    _style = new GUIStyle(GUI.skin.label) { fontSize = FontSize };
                    _style.normal.textColor = Color.white;
                }
                return _style;
            }
        }

        void OnGUI()
        {
            if (!Visible) return;

            var n = Mathf.Max(_samples.Count, 1);
            var avg = _sum / n;

            _sb.Clear();
            _sb.Append($"{_fpsSmoothed,5:F1} fps   frame {_min,5:F1}/{avg,5:F1}/{_max,6:F1} ms\n");
            _sb.Append($"spike >{SpikeMs:F0} ms: {_spikes}   GC gen0: {_gcPerSec}/s\n");

            if (Streamer != null)
            {
                _sb.Append($"terrain: {Streamer.ActiveChunks} chunk, antre {Streamer.QueuedChunks}, " +
                           $"{Streamer.TotalTriangles:N0} segitiga\n");
                _sb.Append($"  build {(Streamer.ThreadActive ? "thread" : "SINKRON")} " +
                           $"{Streamer.LastBuildMs,5:F2} ms | upload {Streamer.LastUploadMs,4:F2} ms " +
                           $"| pool {Streamer.PooledMeshes} | buang {Streamer.DiscardedBuilds}\n");
            }
            else _sb.Append("terrain: TerrainChunkStreamer tidak ada di scene\n");

            if (Water != null)
                _sb.Append($"air: y={Water.transform.position.y:F2}, {Water.Size:F0} m\n");

            if (Grass != null)
                _sb.Append($"rumput: {Grass.ActiveClumps:N0} rumpun, {Grass.ActiveCells} sel\n");
            if (Cycle != null)
                _sb.Append(Cycle.Label + "\n");

            /* Diagnostik. Baris-baris ini ada karena build CI ke-5: game
               JALAN (HUD hidup, 18 fps, stik tergambar) tapi dunia gelap
               total di HP, dan tidak ada cara melihat logcat tanpa PC.
               Dengan angka ini, satu screenshot cukup untuk membedakan
               "kamera terkubur di dalam tanah", "tidak ada lampu", dan
               "tidak ada langit". */
            var cam = Camera.main;
            if (cam == null)
            {
                _sb.Append("DIAG: MainCamera TIDAK ADA -- tag MainCamera belum diset?\n");
            }
            else
            {
                var cp = cam.transform.position;
                _sb.Append($"DIAG cam : ({cp.x:F1}; {cp.y:F1}; {cp.z:F1}) clear={cam.clearFlags}\n");
                if (Streamer != null && Streamer.Target != null)
                {
                    var tp = Streamer.Target.position;
                    _sb.Append($"DIAG tgt : ({tp.x:F1}; {tp.y:F1}; {tp.z:F1})\n");
                }
                var h  = (float)WorldData.TerrainH(cp.x, cp.z);
                var dy = cp.y - h;
                _sb.Append($"DIAG tnh : tinggi={h:F1}, cam.y-tinggi={dy:F1}" +
                           (dy < 0f ? "  <-- KAMERA DI DALAM TANAH" : "") + "\n");
                _sb.Append("DIAG lain: lampu=" +
                           (Object.FindFirstObjectByType<Light>() != null ? "ada" : "TIDAK ADA") +
                           $", ambient={RenderSettings.ambientMode}, fog={(RenderSettings.fog ? "ya" : "tidak")}\n");
            }

            GUI.Label(new Rect(12, 12, Screen.width - 24, Screen.height), _sb.ToString(), Style);
        }

        /* Supaya angka ini bisa ditempel ke laporan, bukan cuma dibaca di layar. */
        public string Snapshot()
        {
            var n = Mathf.Max(_samples.Count, 1);
            return $"{_fpsSmoothed:F1} fps, frame {_min:F1}/{_sum / n:F1}/{_max:F1} ms, " +
                   $"spike {_spikes}, gc0 {_gcPerSec}/s";
        }
    }
}
