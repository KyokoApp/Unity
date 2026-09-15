using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using UnityEngine;
using RPG.Core;
using Debug = UnityEngine.Debug;

namespace RPG.Runtime
{
    /* ============================================================
       TERRAIN CHUNK STREAMER — memuat & membuang chunk terrain
       mengikuti karakter.

       Urutan pemuatan TIDAK ditentukan di sini. Ia memakai
       WorldData.ChunkPlan(), yang sudah diuji paritas terhadap JS
       dan yang urutannya untuk jarak sama sudah dikunci lewat
       LINQ OrderBy (lihat komentar panjang di WorldData.cs soal
       List.Sort yang tidak stabil). Mengganti urutan di sini akan
       membuat chunk termuat dalam urutan berbeda dari yang sudah
       diuji — jadi jangan.

       ------------------------------------------------------------
       DUA PEKERJAAN, DUA THREAD
       ------------------------------------------------------------
       Membangun satu chunk (menyampel TerrainH + mewarnai + menyusun
       indeks) terukur 2,0–4,6 ms di komputer pada quads=32. Di satu
       core HP angkanya bisa beberapa kali lipat — cukup untuk
       menghabiskan seluruh budget frame 50 fps (20 ms) dalam SATU
       frame, dan itu terasa sebagai sentakan tiap kali karakter
       menyeberang batas chunk.

       Untungnya pekerjaan itu bisa dipindah ke thread latar, dan
       keamanannya bukan asumsi:

         (1) RPG.Core.asmdef punya noEngineReferences: true — jadi
             TerrainMesh.Build secara kompilasi TIDAK BISA menyentuh
             UnityEngine. Tidak ada Mesh, tidak ada Transform.
         (2) RPG.Core tidak punya satu pun field statis mutable.
             Semua statiknya const atau static readonly yang diisi
             sekali oleh type initializer CLR (dijamin thread-safe).
             Diperiksa mekanis oleh _verify/terrain --lihat catatan
             di TAHAP-3.md.
         (3) Hasilnya array polos yang diserahkan lewat
             ConcurrentQueue, yang menyediakan memory barrier.

       Yang TETAP di main thread: mengunggah array ke Mesh (API
       Unity hanya boleh dipanggil dari main thread). Itu murah,
       ~0,3 ms, dan dibatasi MaxUploadsPerFrame.

       Matikan UseBackgroundThread kalau mau membandingkan angka,
       atau kalau di perangkat muncul masalah yang menunjuk ke sini.
       Jalur sinkronnya masih utuh, bukan dihapus.
       ============================================================ */
    [DisallowMultipleComponent]
    public class TerrainChunkStreamer : MonoBehaviour
    {
        [Header("Target")]
        [Tooltip("Transform yang diikuti. Kosong = cari CharacterMotor.")]
        public Transform Target;

        [Header("Streaming")]
        [Tooltip("Radius chunk. 2 = 25 chunk / jangkauan 1.280 m. 3 = 49 chunk / 1.792 m.\n" +
                 "Angka ini yang dipakai ChunkPlan, jadi urutannya tetap yang sudah diuji.")]
        [Range(1, 3)] public int StreamRadius = 2;

        [Tooltip("Resolusi grid per chunk. 32 = 8 m per segitiga (51.200 segitiga total di radius 2).\n" +
                 "16 = 16 m (12.800 segitiga) untuk HP lemah. Jangan diisi beda-beda antar chunk:\n" +
                 "resolusi tidak seragam menyebabkan retakan di perbatasan.")]
        [Range(8, 64)] public int QuadsPerChunk = TerrainMesh.DefaultQuads;

        [Header("Threading")]
        [Tooltip("Bangun chunk di thread latar. Aman: RPG.Core tidak bisa menyentuh UnityEngine\n" +
                 "(noEngineReferences: true) dan tidak punya state statis mutable. Matikan untuk\n" +
                 "membandingkan angka, atau kalau ada masalah yang menunjuk ke sini.")]
        public bool UseBackgroundThread = true;

        [Tooltip("Maksimum chunk DIUNGGAH ke Mesh per frame (main thread, ~0,3 ms tiap chunk).\n" +
                 "Hanya dipakai saat UseBackgroundThread aktif.")]
        [Range(1, 8)] public int MaxUploadsPerFrame = 2;

        [Tooltip("Maksimum chunk dibangun per frame pada jalur SINKRON.\n" +
                 "Terukur 2,0–4,6 ms/chunk pada quads=32 di komputer (varians antar-run besar;\n" +
                 "angka perangkat bisa beberapa kali lipat). Diabaikan kalau thread latar aktif.")]
        [Range(1, 4)] public int MaxBuildsPerFrame = 1;

        /* Berapa banyak job boleh berada di worker sekaligus. Sengaja kecil:
           kalau karakter berlari 13,5 m/s dan rencana chunk berubah, job yang
           sudah terlanjur masuk worker tidak bisa ditarik kembali. Dengan 2,
           kerja basi yang terbuang maksimal ~2 chunk. */
        const int MaxInFlight = 2;

        [Header("Tampilan")]
        public Material TerrainMaterial;
        [Tooltip("Chunk diberi layer ini (untuk shadow/kamera).")]
        public string ChunkLayer = "Default";

        /* ---- statistik, dibaca PerfHud ---- */
        public int ActiveChunks { get; private set; }
        public int QueuedChunks => _pending.Count + _inFlight.Count;
        public int PooledMeshes => _pool.Count;
        public long TotalTriangles { get; private set; }
        public long TotalVertices { get; private set; }
        public float LastBuildMs { get; private set; }
        public float LastUploadMs { get; private set; }
        public bool ThreadActive => _worker != null && _worker.IsAlive;
        public int DiscardedBuilds { get; private set; }

        /* ---- keadaan main-thread saja ---- */
        /* Nilai bukan cuma GameObject: jumlah segitiga/verteks ikut disimpan.
           Kalau tidak, satu-satunya cara mengetahui ukurannya adalah membaca
           balik Mesh.triangles -- yang mengalokasikan salinan seluruh indeks
           dan setelah UploadMeshData(true) memang sudah tidak bisa dibaca. */
        struct Live { public GameObject Go; public long Triangles, Vertices; }
        readonly Dictionary<long, Live> _active = new Dictionary<long, Live>();
        readonly List<long> _wanted = new List<long>();
        readonly List<long> _pending = new List<long>();
        readonly HashSet<long> _inFlight = new HashSet<long>();
        readonly Stack<Mesh> _pool = new Stack<Mesh>();

        /* ---- penyeberangan antar-thread ---- */
        readonly ConcurrentQueue<Job> _jobs = new ConcurrentQueue<Job>();
        readonly ConcurrentQueue<Done> _done = new ConcurrentQueue<Done>();
        readonly AutoResetEvent _wake = new AutoResetEvent(false);
        Thread _worker;
        volatile bool _running;

        /* Scratch buffer untuk konversi array. Dipakai ulang supaya tidak ada
           ~52 KB sampah per chunk (1,3 MB saat 25 chunk pertama termuat).
           Di-alokasi ulang hanya kalau quads berubah. */
        Vector3[] _sv, _sn;
        Color[] _sc;
        Vector2[] _su;

        int _lastCx = int.MinValue, _lastCz = int.MinValue;
        int _layer;
        Transform _holder;

        struct Job { public long Key; public int Cx, Cz, Quads; }
        struct Done { public long Key; public int Quads; public ChunkMesh Data; public double Ms; public string Error; }

        static long Key(int cx, int cz) => ((long)(cx + 4096) << 16) | (uint)(cz + 4096);
        static void Unkey(long k, out int cx, out int cz)
        {
            cx = (int)((k >> 16) & 0xFFFF) - 4096;
            cz = (int)(k & 0xFFFF) - 4096;
        }

        void Awake()
        {
            _layer = LayerMask.NameToLayer(ChunkLayer);
            if (_layer < 0) _layer = 0;
            if (Target == null)
            {
                var motor = FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
            _holder = new GameObject("TerrainChunks").transform;
            _holder.SetParent(transform, false);
            StartWorker();
        }

        void StartWorker()
        {
            if (!Application.isPlaying || !UseBackgroundThread) return;
            if (_worker != null && _worker.IsAlive) return;
            _running = true;
            _worker = new Thread(WorkerLoop) { IsBackground = true, Name = "TerrainChunkBuilder" };
            _worker.Start();
        }

        void StopWorker()
        {
            _running = false;
            _wake.Set();
            if (_worker != null)
            {
                /* Join dengan batas waktu. Kalau worker macet, kita tetap
                   lanjut — thread-nya IsBackground jadi tidak menahan proses. */
                _worker.Join(500);
                _worker = null;
            }
            while (_jobs.TryDequeue(out _)) { }
            while (_done.TryDequeue(out _)) { }
            _inFlight.Clear();
        }

        void WorkerLoop()
        {
            while (_running)
            {
                if (_jobs.TryDequeue(out var job))
                {
                    var d = new Done { Key = job.Key, Quads = job.Quads };
                    var sw = Stopwatch.StartNew();
                    try { d.Data = TerrainMesh.Build(job.Cx, job.Cz, job.Quads); }
                    catch (Exception e) { d.Error = e.ToString(); }
                    sw.Stop();
                    d.Ms = sw.Elapsed.TotalMilliseconds;
                    _done.Enqueue(d);
                }
                else
                {
                    /* AutoResetEvent menahan satu Set() kalau tidak ada yang
                       menunggu, jadi sinyal tidak hilang. Batas 16 ms hanya
                       jaring pengaman agar latensi terburuk tetap terbatas. */
                    _wake.WaitOne(16);
                }
            }
        }

        void Update()
        {
            if (Target == null) return;

            /* Mode thread bisa diubah lewat Inspector saat berjalan. */
            if (UseBackgroundThread && !ThreadActive && Application.isPlaying) StartWorker();

            var p = Target.position;
            var cx = TerrainMesh.ChunkIndex(p.x);
            var cz = TerrainMesh.ChunkIndex(p.z);

            if (cx != _lastCx || cz != _lastCz || _active.Count == 0)
            {
                _lastCx = cx; _lastCz = cz;
                RefreshPlan(cx, cz);
            }

            if (UseBackgroundThread && ThreadActive)
            {
                FeedWorker();
                DrainResults();
            }
            else
            {
                BuildBudgetedSync();
            }

            ActiveChunks = _active.Count;
        }

        /* Untuk screenshot batchmode (SceneShots): di edit mode tidak ada
           loop Update yang men-stream chunk, jadi dipaksa sinkron di sini.
           Jalur sinkronnya sudah ada (BuildBudgetedSync) -- dipakai ulang,
           bukan ditulis ulang, supaya hasilnya identik dengan permainan. */
        public void EditorStreamNow(int maxBuilds)
        {
            if (Target == null) return;
            var prevThread = UseBackgroundThread;
            UseBackgroundThread = false;
            try
            {
                for (var i = 0; i < maxBuilds; i++)
                {
                    var p = Target.position;
                    var cx = TerrainMesh.ChunkIndex(p.x);
                    var cz = TerrainMesh.ChunkIndex(p.z);
                    if (cx != _lastCx || cz != _lastCz || _active.Count == 0)
                    {
                        _lastCx = cx; _lastCz = cz;
                        RefreshPlan(cx, cz);
                    }
                    BuildBudgetedSync();
                    ActiveChunks = _active.Count;
                    if (_pending.Count == 0 && _inFlight.Count == 0) break;
                }
            }
            finally
            {
                UseBackgroundThread = prevThread;
            }
        }

        void RefreshPlan(int cx, int cz)
        {
            var plan = WorldData.ChunkPlan(cx * WorldData.ChunkSize + WorldData.ChunkSize * 0.5,
                                           cz * WorldData.ChunkSize + WorldData.ChunkSize * 0.5,
                                           StreamRadius);

            _wanted.Clear();
            foreach (var c in plan)
                if (TerrainMesh.ChunkInWorld(c.Cx, c.Cz))
                    _wanted.Add(Key(c.Cx, c.Cz));

            // buang yang sudah tidak diminta
            var stale = new List<long>();
            foreach (var k in _active.Keys)
                if (!_wanted.Contains(k)) stale.Add(k);
            foreach (var k in stale) Release(k);

            /* Antrekan yang baru, mengikuti urutan ChunkPlan (terdekat dulu).
               _inFlight tidak diantrekan ulang: hasilnya akan datang sendiri,
               dan DrainResults yang memutuskan masih dipakai atau dibuang. */
            _pending.Clear();
            foreach (var k in _wanted)
                if (!_active.ContainsKey(k) && !_inFlight.Contains(k)) _pending.Add(k);
        }

        void FeedWorker()
        {
            while (_inFlight.Count < MaxInFlight && _pending.Count > 0)
            {
                var k = _pending[0];
                _pending.RemoveAt(0);
                Unkey(k, out var cx, out var cz);
                _inFlight.Add(k);
                _jobs.Enqueue(new Job { Key = k, Cx = cx, Cz = cz, Quads = QuadsPerChunk });
                _wake.Set();
            }
        }

        void DrainResults()
        {
            var uploads = 0;
            while (_done.TryDequeue(out var d))
            {
                _inFlight.Remove(d.Key);

                if (d.Error != null)
                {
                    Debug.LogError($"[TerrainChunkStreamer] build chunk gagal: {d.Error}");
                    continue;
                }
                LastBuildMs = (float)d.Ms;

                /* Hasil dibuang kalau quads-nya sudah berubah (SetQuality) atau
                   chunk-nya sudah tidak diminta lagi (karakter keburu lewat).
                   Tidak ada yang perlu di-release: Mesh belum dibuat. */
                if (d.Quads != QuadsPerChunk || !_wanted.Contains(d.Key) ||
                    _active.ContainsKey(d.Key) || uploads >= MaxUploadsPerFrame)
                {
                    if (d.Quads == QuadsPerChunk && _wanted.Contains(d.Key) && !_active.ContainsKey(d.Key))
                    {
                        // masih dibutuhkan, tapi budget upload frame ini habis -> antre lagi
                        _pending.Add(d.Key);
                    }
                    else DiscardedBuilds++;
                    continue;
                }

                Upload(d.Key, d.Data);
                uploads++;
            }
        }

        void BuildBudgetedSync()
        {
            for (var i = 0; i < MaxBuildsPerFrame && _pending.Count > 0; i++)
            {
                var k = _pending[0];
                _pending.RemoveAt(0);
                if (_active.ContainsKey(k)) continue;
                Unkey(k, out var cx, out var cz);

                var sw = Stopwatch.StartNew();
                var data = TerrainMesh.Build(cx, cz, QuadsPerChunk);
                sw.Stop();
                LastBuildMs = (float)sw.Elapsed.TotalMilliseconds;
                if (data == null) continue;
                Upload(k, data);
            }
        }

        void Upload(long key, ChunkMesh data)
        {
            if (data == null) return;
            Unkey(key, out var cx, out var cz);

            var sw = Stopwatch.StartNew();
            var mesh = _pool.Count > 0 ? _pool.Pop() : new Mesh();
            mesh.Clear(true);
            mesh.name = $"chunk_{cx}_{cz}_q{QuadsPerChunk}";
            FillMesh(mesh, data);
            /* Mesh sudah diunggah ke GPU; salinan CPU-nya dibuang. Di Android
               ini menghemat RAM sebesar ukuran vertex buffer (~76 KB/chunk). */
            mesh.UploadMeshData(true);
            sw.Stop();
            LastUploadMs = (float)sw.Elapsed.TotalMilliseconds;

            var go = new GameObject(mesh.name);
            go.layer = _layer;
            go.transform.SetParent(_holder, false);
            go.transform.localPosition = Vector3.zero;    // verteks sudah dalam koordinat dunia
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            if (TerrainMaterial != null) mr.sharedMaterial = TerrainMaterial;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            mr.receiveShadows = true;

            _active[key] = new Live { Go = go, Triangles = data.TriangleCount, Vertices = data.VertexCount };
            TotalTriangles += data.TriangleCount;
            TotalVertices += data.VertexCount;
        }

        /* Konversi array polos dari RPG.Core ke array Unity. RPG.Core sengaja
           tidak boleh menyentuh UnityEngine (noEngineReferences: true), jadi
           salinan ini memang harus terjadi di sini — dan karena itu ia ada di
           main thread.

           Scratch buffer dipakai ulang; Unity menyalin isinya ke memori native
           saat setter dipanggil, jadi buffer ini aman dipakai untuk chunk
           berikutnya. Di-alokasi ulang hanya kalau jumlah verteks berubah
           (yaitu kalau QuadsPerChunk diubah). */
        void FillMesh(Mesh mesh, ChunkMesh d)
        {
            var vc = d.VertexCount;
            if (_sv == null || _sv.Length != vc)
            {
                _sv = new Vector3[vc];
                _sn = new Vector3[vc];
                _sc = new Color[vc];
                _su = new Vector2[vc];
            }

            for (var i = 0; i < vc; i++)
            {
                _sv[i] = new Vector3(d.Vertices[i * 3], d.Vertices[i * 3 + 1], d.Vertices[i * 3 + 2]);
                _sn[i] = new Vector3(d.Normals[i * 3], d.Normals[i * 3 + 1], d.Normals[i * 3 + 2]);
                _sc[i] = new Color(d.Colors[i * 4], d.Colors[i * 4 + 1], d.Colors[i * 4 + 2], d.Colors[i * 4 + 3]);
                _su[i] = new Vector2(d.UVs[i * 2], d.UVs[i * 2 + 1]);
            }

            mesh.vertices = _sv;
            mesh.normals = _sn;
            mesh.colors = _sc;
            mesh.uv = _su;
            mesh.triangles = d.Triangles;
            mesh.RecalculateBounds();
            /* quads maks 64 -> 65x65 = 4.225 verteks, jauh di bawah batas
               UInt16 (65.535). IndexFormat default sudah cukup; tidak perlu
               diubah, dan mengubahnya ke UInt32 justru menggandakan memori
               indeks di perangkat. */
        }

        void Release(long key)
        {
            if (!_active.TryGetValue(key, out var live)) return;
            var go = live.Go;
            TotalTriangles -= live.Triangles;
            TotalVertices -= live.Vertices;
            var mf = go.GetComponent<MeshFilter>();
            if (mf != null && mf.sharedMesh != null)
            {
                var m = mf.sharedMesh;
                m.Clear(true);
                /* UploadMeshData(true) sudah membuang salinan CPU, jadi mesh bekas
                   ini tetap bisa dipakai ulang sebagai wadah — datanya ditulis
                   ulang sepenuhnya oleh FillMesh. */
                if (_pool.Count < 64) _pool.Push(m); else ObjectUtil.SafeDestroy(m);
            }
            _active.Remove(key);
            ObjectUtil.SafeDestroy(go);
        }

        void OnDestroy()
        {
            StopWorker();
            foreach (var live in _active.Values) ObjectUtil.SafeDestroy(live.Go);
            _active.Clear();
            while (_pool.Count > 0) ObjectUtil.SafeDestroy(_pool.Pop());
            _wake.Dispose();
        }

        void OnApplicationQuit() => StopWorker();

        /* Dipanggil dari Tahap 7 saat tier kualitas berubah. Membangun ulang
           semuanya pada resolusi baru. */
        public void SetQuality(int quads, int radius)
        {
            QuadsPerChunk = Mathf.Clamp(quads, 8, TerrainMesh.MaxQuads);
            StreamRadius = Mathf.Clamp(radius, 1, 3);
            foreach (var k in new List<long>(_active.Keys)) Release(k);
            /* Job yang sedang dikerjakan worker memakai quads lama; hasilnya
               akan dibuang oleh DrainResults karena d.Quads != QuadsPerChunk. */
            _pending.Clear();
            TotalTriangles = 0; TotalVertices = 0;
            _lastCx = int.MinValue; _lastCz = int.MinValue;
        }
    }
}
