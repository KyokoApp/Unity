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

        [Tooltip("Probe render dijalankan tiap sekian detik (bukan tiap frame): murah tapi tidak gratis, dan angkanya untuk dibaca manusia.")]
        public float ProbeInterval = 1.5f;

        float _nextProbe;
        string _probe = "";
        bool  _verdictBad;

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
               "tidak ada langit".

               v0.2.0-cel-fix18: ditambah PROBE (di bawah) dan kotak latar.
               Kotaknya bukan hiasan: SettingsPanel menggambar tombolnya di
               Rect(12,12,110,44) -- tepat di atas blok teks ini -- sehingga
               keduanya bertumpuk dan tidak ada satu pun baris yang bisa
               dibaca. Laporan "jejak" di HP adalah itu, bukan motion blur:
               angka `terrain:` dan `spike:` di screenshot v0.2.0-cel-fix17
               literally tidak terbaca, jadi yang kita butuhkan adalah HUD
               yang bisa dibaca, bukan HUD yang lebih banyak. */
            var cam = Camera.main;
            if (cam == null)
            {
                _sb.Append("kamera : MainCamera TIDAK ADA -- tag MainCamera belum diset?\n");
            }
            else
            {
                var cp = cam.transform.position;
                _sb.Append($"kamera : ({cp.x:F1}; {cp.y:F1}; {cp.z:F1}) clear={cam.clearFlags} aktif={cam.isActiveAndEnabled}\n");
                if (Streamer != null && Streamer.Target != null)
                {
                    var tp = Streamer.Target.position;
                    _sb.Append($"target : ({tp.x:F1}; {tp.y:F1}; {tp.z:F1})\n");
                }
                var h  = (float)WorldData.TerrainH(cp.x, cp.z);
                var dy = cp.y - h;
                _sb.Append($"tanah  : tinggi={h:F1}, cam.y-tinggi={dy:F1}" +
                           (dy < 0f ? "  <-- KAMERA DI DALAM TANAH" : "") + "\n");
                _sb.Append("lainnya: lampu=" +
                           (Object.FindFirstObjectByType<Light>() != null ? "ada" : "TIDAK ADA") +
                           $", ambient={RenderSettings.ambientMode}, fog={(RenderSettings.fog ? "ya" : "tidak")}\n");
            }

            AppendProbe();

            /* Kotak latar digambar dulu, lalu teksnya; tingginya dihitung dari
               jumlah baris yang benar-benar tersusun, bukan perkiraan tetap.
               Dimulai di y=56 supaya tidak bertumpuk dengan tombol Setting. */
            var lines = 1;
            for (var i = 0; i < _sb.Length; i++) if (_sb[i] == '\n') lines++;
            var w = Mathf.Min(Screen.width - 24, 640);
            var hgt = 8 + lines * (Style.fontSize + 4);
            var prev = GUI.color;
            GUI.color = Color.white;
            GUI.DrawTexture(new Rect(8, 56, w + 12, hgt), Backdrop);
            GUI.color = _verdictBad ? new Color(1f, 0.56f, 0.5f) : Color.white;
            GUI.Label(new Rect(14, 60, w, hgt), _sb.ToString(), Style);
            GUI.color = prev;
        }

        /* ── PROBE RENDER ───────────────────────────────────────────────
           Empat dugaan "dunia hitam" yang selama ini cuma bisa dituduh,
           dan tiap tuduhan koszt satu build Unity ~1 jam:

             rp      : tidak ada RenderPipeline di player -> tidak ada yang
                       menggambar, backbuffer tidak di-clear -> teks lama
                       tertinggal. Mencurigakan karena ProjectSettings/
                       GraphicsSettings.asset TIDAK ada di repo: pipeline
                       dipasang editor script SAAT build.
             shader  : Shader.Find() di player hanya mengenal shader yang ikut
                       dibungkus. NULL di sini = kepingnya di-strip.
             materi  : renderer ada tapi materialnya NULL -> di URP tidak ada
                       "magenta" untuk ini; hasilnya diam-diam tidak tergambar.
             chunk   : 0 chunk = worker terrain tidak pernah mengunggah Mesh.

           Semua dibungkus try/catch: HUD yang melempar akan mengubah diagnosis
           menjadi bencana, dan itu pernah terjadi di tempat lain di proyek ini. */
        void AppendProbe()
        {
            if (Time.unscaledTime >= _nextProbe)
            {
                _nextProbe = Time.unscaledTime + ProbeInterval;
                _probe = BuildProbe();
            }
            _sb.Append(_probe);
        }

        string BuildProbe()
        {
            var sb = new StringBuilder(420);
            try
            {
                var rp  = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline;
                var rpq = QualitySettings.renderPipeline;
                _verdictBad = rp == null && rpq == null;
                sb.Append("probe rp     : ")
                  .Append(rp != null ? rp.name : rpq != null ? "hanya-di-quality: " + rpq.name : "TIDAK ADA")
                  .Append(" | kualitas ").Append(QualitySettings.GetQualityLevel())
                  .Append(" | dev ").Append(SystemInfo.graphicsDeviceType)
                  .Append(" shaderLvl ").Append(SystemInfo.graphicsShaderLevel).Append('\n');

                sb.Append("probe shader : ")
                  .Append(HasShader("Aurelia/Terrain")).Append(' ')
                  .Append(HasShader("Aurelia/TerrainCel")).Append(' ')
                  .Append(HasShader("Aurelia/GrassCel")).Append(' ')
                  .Append(HasShader("Aurelia/Water")).Append(' ')
                  .Append(HasShader("Aurelia/CharCel")).Append('\n');

                var chunk = Streamer != null ? Streamer.ActiveChunks : -1;
                sb.Append("probe terrain: chunk=").Append(chunk)
                  .Append(" antre=").Append(Streamer != null ? Streamer.QueuedChunks : -1)
                  .Append(" err=").Append(Streamer != null ? Streamer.BuildErrors : -1)
                  .Append(" materi=").Append(Streamer != null && Streamer.TerrainMaterial != null
                                                ? Streamer.TerrainMaterial.name : "NULL").Append('\n');
                if (Streamer != null && Streamer.LastError != null)
                    sb.Append("   err: ").Append(OneLine(Streamer.LastError)).Append('\n');

                sb.Append("probe rumput: ")
                  .Append(Grass != null ? Grass.InitState : "GrassField tidak ada")
                  .Append(" aktif=").Append(Grass != null ? Grass.ActiveClumps : -1)
                  .Append(" materi=").Append(Grass != null && Grass.GrassMaterial != null
                                              ? Grass.GrassMaterial.name : "NULL").Append('\n');

                var rs = Object.FindObjectsByType<Renderer>(FindObjectsSortMode.None);
                var tot = 0; var aktif = 0; var tanpaMat = 0; var terlihat = 0;
                for (var i = 0; i < rs.Length; i++)
                {
                    if (rs[i] == null) continue;
                    tot++;
                    if (rs[i].enabled) aktif++;
                    if (rs[i].sharedMaterial == null) tanpaMat++;
                    if (rs[i].isVisible) terlihat++;
                }
                sb.Append("probe render : ").Append(tot).Append(" renderer, ").Append(aktif)
                  .Append(" aktif, ").Append(tanpaMat).Append(" tanpa materi, ").Append(terlihat)
                  .Append(" terlihat kamera\n");

                if (rp == null && rpq == null)
                    sb.Append("=> PLAYER TANPA RENDER PIPELINE. Tidak ada yang menggambar apa pun dan backbuffer tidak pernah di-clear (itulah \"jejak\").\n");
                else if (chunk == 0)
                    sb.Append("=> pipeline ADA tapi 0 chunk terunggah -> lihat \"err=\" di atas; kalau err=0 berarti worker tidak pernah diberi pekerjaan.\n");
                else if (tot > 0 && tanpaMat == tot)
                    sb.Append("=> SEMUA renderer tanpa materi -> material .mat tidak ikut terbungkus build.\n");
                else if (chunk > 0 && terlihat == 0)
                    sb.Append("=> chunk ADA tapi NOL terlihat kamera -> yang salah adalah culling: cullingMask, near/far clip, atau posisi. Bukan materi, bukan shader.\n");
                else if (chunk > 0 && tot > 0 && tanpaMat < tot)
                    sb.Append("=> pipeline ADA, chunk ADA, materi ADA, ada yang terlihat. Kalau masih hitam, yang salah adalah SHADER-nya saat digambar (varian/keyword/target), bukan build-nya.\n");
                else
                    sb.Append("=> belum conclusif; screenshot ini sudah memangkas setengah kemungkinan.\n");
            }
            catch (System.Exception e)
            {
                _verdictBad = true;
                sb.Append("probe GAGAL: ").Append(e.GetType().Name).Append(' ').Append(e.Message).Append('\n');
            }
            return sb.ToString();
        }

        static string HasShader(string shaderName)
        {
            var cut = shaderName.IndexOf('/');
            var shortName = cut >= 0 ? shaderName.Substring(cut + 1) : shaderName;
            return shortName + (Shader.Find(shaderName) == null ? "=NULL" : "=ada");
        }

        static string OneLine(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace('\n', ' ').Replace('\r', ' ');
        }

        static Texture2D _backdrop;
        static Texture2D Backdrop
        {
            get
            {
                if (_backdrop == null)
                {
                    _backdrop = new Texture2D(1, 1);
                    _backdrop.SetPixels32(new[] { new Color32(6, 6, 9, 185) });
                    _backdrop.Apply();
                }
                return _backdrop;
            }
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
