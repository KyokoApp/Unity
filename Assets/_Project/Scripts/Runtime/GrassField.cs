// ============================================================
// GrassField.cs
//
// Rumput stylized (gradasi pangkal->ujung, goyangan angin, tanpa
// tekstur alpha) yang ditarik SATU draw call per 1023 rumpun lewat
// Graphics.DrawMeshInstanced.
//
// Perbaikan Tahap 5:
// [1] BUG CACHE: dulu RefreshCells me-Clear SEMUA sel tiap pindah
//     sel 8 m (ribuan TerrainH + alokasi List per sel = hitch +
//     GC). Komentar lamanya bahkan mengklaim "dipakai ulang dari
//     cache" padahal tidak. Sekarang sel dipertahankan, yang jauh
//     dibuang, yang baru dibangun.
// [2] LOD DUA TINGKAT: dekat = rumpun 4 bilah, jauh = 3 quad
//     silang (2,6x lebih murah). Tanpa ini, rumput jauh membuang
//     vertex untuk detail yang tidak terlihat.
// [3] Hembusan angin pakai noise texture (opsional, _WindNoise) —
//     tanpa tekstur tetap jalan dengan gelombang sin.
// ============================================================
using System.Collections.Generic;
using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    [DisallowMultipleComponent]
    public class GrassField : MonoBehaviour
    {
        [Header("Target")]
        [Tooltip("Rumput mengikuti objek ini (karakter).")]
        public Transform Target;

        [Header("Bentuk")]
        public Material GrassMaterial;

        [Tooltip("Noise angin (RG=arah, B=kekuatan). Kosong = sin murni.")]
        public Texture WindNoise;

        [Tooltip("Radius sebaran rumput di sekitar target (m).")]
        [Range(10f, 60f)] public float Radius = 30f;

        [Tooltip("Ukuran sel cache. 8 m = setengah chunk terrain.")]
        public float CellSize = 8f;

        [Tooltip("Rumpun per sel pada tingkat kualitas penuh; skala kualitas diterapkan di Awake.")]
        [Range(4, 96)] public int PerCellBase = 26;

        [Tooltip("Di bawah jarak ini (m) dipakai mesh detail; di atasnya mesh silang murah.")]
        [Range(6f, 40f)] public float LodDistance = 14f;

        public int ActiveClumps { get; private set; }
        public int ActiveCells => _near.Count + _far.Count;
        public int NearClumps { get; private set; }
        public int FarClumps { get; private set; }

        Mesh _clump;
        Mesh _farClump;
        readonly Dictionary<long, Matrix4x4[]> _near = new Dictionary<long, Matrix4x4[]>();
        readonly Dictionary<long, Matrix4x4[]> _far = new Dictionary<long, Matrix4x4[]>();
        readonly HashSet<long> _wanted = new HashSet<long>();
        readonly List<long> _drop = new List<long>();
        /* DrawMeshInstanced di Unity 6 hanya menerima Matrix4x4[] (tidak ada
           overload List<>), jadi pakai array pakai-ulang: tanpa alokasi per
           frame, tanpa GC pressure di HP. */
        readonly Matrix4x4[] _batch = new Matrix4x4[1023];
        int _lastCx = int.MinValue, _lastCz;
        int _perCell;
        bool _on;
        bool _instancingOk = true;

        static readonly int WindNoiseId = Shader.PropertyToID("_WindNoise");
        static readonly int WindNoiseStrId = Shader.PropertyToID("_WindNoiseStrength");

        void Awake() => EnsureInit();

        /* Inisialisasi idempoten. PENTING: di edit mode (screenshot batchmode)
           Awake() TIDAK dijamin dipanggil saat AddComponent, jadi semua jalur
           masuk (DrawNow/PopulateNow/BakeInto) memastikan state siap dulu. */
        void EnsureInit()
        {
            if (_clump != null) return;

            var resolved = GfxResolver.Resolve(SettingsStore.Load(), true);
            _on = resolved.GrassEnabled;
            if (!_on) return;

            var scale = resolved.GrassCount > 0 && PerCellBase > 0
                ? (double)resolved.GrassCount / (PerCellBase * CellCount())
                : 0.0;
            _perCell = Mathf.Max(4, Mathf.RoundToInt(PerCellBase * (float)scale));

            _clump = BuildClump();
            _farClump = BuildFarClump();

            WorldLook.EnableInstancing(GrassMaterial);

            if (GrassMaterial != null && WindNoise != null &&
                GrassMaterial.HasProperty("_WindNoise"))
            {
                GrassMaterial.SetTexture(WindNoiseId, WindNoise);
                GrassMaterial.SetFloat(WindNoiseStrId, 0.65f);
            }

            if (Target == null)
            {
                var motor = Object.FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
        }

        /* Dipanggil panel pengaturan / QualityApplier setelah preset berubah. */
        public void RefreshSettings()
        {
            var resolved = GfxResolver.Resolve(SettingsStore.Load(), true);
            _on = resolved.GrassEnabled;
            var scale = resolved.GrassCount > 0 && PerCellBase > 0
                ? (double)resolved.GrassCount / (PerCellBase * CellCount())
                : 0.0;
            _perCell = Mathf.Max(4, Mathf.RoundToInt(PerCellBase * (float)scale));
            _near.Clear();
            _far.Clear();
            _lastCx = int.MinValue;
        }

        int CellCount()
        {
            var n = Mathf.CeilToInt(Radius / CellSize);
            var c = 0;
            for (var x = -n; x <= n; x++)
                for (var z = -n; z <= n; z++)
                    if (x * x + z * z <= n * n) c++;
            return c;
        }

        /* Dipanggil tiap frame saat bermain: gambar semua sel yang terlihat.
           Selama loading: JANGAN DrawMeshInstanced — material tanpa
           enableInstancing melempar tiap frame dan menempel kotak merah. */
        void LateUpdate()
        {
            if (LoadingScreen.IsShown) return;
            DrawNow();
        }

        /* Diagnosa ringkas — dipakai SceneShots lewat log CI. */
        public string InitState =>
            $"on={_on} clump={_clump != null} target={Target != null} perCell={_perCell} " +
            $"cells={ActiveCells} near={NearClumps} far={FarClumps}";

        public void PopulateNow()
        {
            EnsureInit();
            if (!_on || Target == null) return;
            RefreshCells(Target.position, true);
        }

        public void DrawNow()
        {
            EnsureInit();
            if (!_on || !_instancingOk || _clump == null || GrassMaterial == null || Target == null)
                return;

            WorldLook.EnableInstancing(GrassMaterial);
            RefreshCells(Target.position, false);

            ActiveClumps = 0; NearClumps = 0; FarClumps = 0;
            FlushSet(_near, _clump, true);
            FlushSet(_far, _farClump, false);
        }

        void FlushSet(Dictionary<long, Matrix4x4[]> set, Mesh mesh, bool near)
        {
            if (!_instancingOk || mesh == null || GrassMaterial == null) return;
            var n = 0;
            var count = 0;
            foreach (var kv in set)
            {
                var arr = kv.Value;
                for (var i = 0; i < arr.Length; i++)
                {
                    _batch[n++] = arr[i];
                    if (n == 1023)
                    {
                        if (!DrawBatch(mesh, n)) return;
                        count += n; n = 0;
                    }
                }
            }
            if (n > 0)
            {
                if (!DrawBatch(mesh, n)) return;
                count += n;
            }
            ActiveClumps += count;
            if (near) NearClumps = count; else FarClumps = count;
        }

        bool DrawBatch(Mesh mesh, int n)
        {
            try
            {
                Graphics.DrawMeshInstanced(mesh, 0, GrassMaterial, _batch, n);
                return true;
            }
            catch (System.Exception e)
            {
                _instancingOk = false;
                BootLog.Add("[noise] rumput instancing mati: " + e.GetType().Name + ": " + e.Message);
                return false;
            }
        }

        /* KHUSUS SCREENSHOT (dipakai Editor/SceneShots): gabungan SEMUA
           instance jadi mesh bake world-space. */
        public int BakeInto(Mesh dst)
        {
            EnsureInit();
            if (!_on || _clump == null || Target == null || dst == null) return 0;
            RefreshCells(Target.position, false);

            var V = new List<Vector3>();
            var U = new List<Vector2>();
            var T = new List<int>();
            var n = BakeSet(_near, _clump, V, U, T) + BakeSet(_far, _farClump, V, U, T);
            if (n == 0) return 0;
            dst.vertices = V.ToArray();
            dst.uv = U.ToArray();
            dst.triangles = T.ToArray();
            dst.RecalculateBounds();
            return n;
        }

        static int BakeSet(Dictionary<long, Matrix4x4[]> set, Mesh src,
                           List<Vector3> V, List<Vector2> U, List<int> T)
        {
            var sv = src.vertices; var su = src.uv; var st = src.triangles;
            if (sv == null || st == null || sv.Length == 0) return 0;
            var hasU = su != null && su.Length == sv.Length;
            var n = 0;
            foreach (var kv in set)
            {
                foreach (var m in kv.Value)
                {
                    var baseV = V.Count;
                    for (var i = 0; i < sv.Length; i++)
                    {
                        V.Add(m.MultiplyPoint3x4(sv[i]));
                        U.Add(hasU ? su[i] : Vector2.zero);
                    }
                    for (var i = 0; i < st.Length; i++) T.Add(st[i] + baseV);
                    n++;
                }
            }
            return n;
        }

        public void DrawInto(UnityEngine.Rendering.CommandBuffer cmd)
        {
            if (!_on || _clump == null || GrassMaterial == null || Target == null || cmd == null) return;
            RefreshCells(Target.position, false);
            DrawSetInto(cmd, _near, _clump);
            DrawSetInto(cmd, _far, _farClump);
        }

        void DrawSetInto(UnityEngine.Rendering.CommandBuffer cmd,
                         Dictionary<long, Matrix4x4[]> set, Mesh mesh)
        {
            var n = 0;
            foreach (var kv in set)
            {
                var arr = kv.Value;
                for (var i = 0; i < arr.Length; i++)
                {
                    _batch[n++] = arr[i];
                    if (n == 1023)
                    {
                        cmd.DrawMeshInstanced(mesh, 0, GrassMaterial, 0, _batch, n);
                        n = 0;
                    }
                }
            }
            if (n > 0) cmd.DrawMeshInstanced(mesh, 0, GrassMaterial, 0, _batch, n);
        }

        void RefreshCells(Vector3 p, bool force)
        {
            var cx = Mathf.FloorToInt(p.x / CellSize);
            var cz = Mathf.FloorToInt(p.z / CellSize);
            if (!force && cx == _lastCx && cz == _lastCz && ActiveCells > 0) return;
            _lastCx = cx; _lastCz = cz;

            // Sel dipertahankan antar refresh: hanya sel BARU yang dibangun
            // (mahal: ratusan TerrainH), sel yang JAUH yang dibuang.
            _wanted.Clear();
            var n = Mathf.CeilToInt(Radius / CellSize);
            var r2 = Radius * Radius;
            for (var x = cx - n; x <= cx + n; x++)
            {
                for (var z = cz - n; z <= cz + n; z++)
                {
                    var dx = (x + 0.5f) * CellSize - p.x;
                    var dz = (z + 0.5f) * CellSize - p.z;
                    if (dx * dx + dz * dz > r2) continue;
                    var key = Key(x, z);
                    _wanted.Add(key);
                    if (_near.ContainsKey(key) || _far.ContainsKey(key)) continue;
                    var near = Mathf.Sqrt(dx * dx + dz * dz) < LodDistance;
                    var cell = PlaceCell(x, z, p);
                    if (cell.Length > 0) (near ? _near : _far)[key] = cell;
                }
            }

            _drop.Clear();
            foreach (var k in _near.Keys) if (!_wanted.Contains(k)) _drop.Add(k);
            foreach (var k in _drop) _near.Remove(k);
            _drop.Clear();
            foreach (var k in _far.Keys) if (!_wanted.Contains(k)) _drop.Add(k);
            foreach (var k in _drop) _far.Remove(k);
        }

        static long Key(int x, int z) => ((long)x << 32) | (uint)z;

        Matrix4x4[] PlaceCell(int cx, int cz, Vector3 focus)
        {
            /* Hamparan padat di dekat pemain lalu menipis ke arah tepi —
               caranya membagi anggaran instance yang SAMA, supaya kesan
               "padang rumput" terbaca tanpa menambah biaya GPU. */
            var ccx = (cx + 0.5f) * CellSize;
            var ccz = (cz + 0.5f) * CellSize;
            var d = Vector3.Distance(new Vector3(ccx, 0f, ccz), new Vector3(focus.x, 0f, focus.z));
            var t = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(d / Radius));
            var count = Mathf.Max(3, Mathf.RoundToInt(_perCell * Mathf.Lerp(2.6f, 0.30f, t)));
            var list = new List<Matrix4x4>(count);
            var ox = cx * CellSize;
            var oz = cz * CellSize;

            for (var i = 0; i < count; i++)
            {
                var hx = Hash3(cx, cz, i * 3);
                var hz = Hash3(cx, cz, i * 3 + 1);
                var hr = Hash3(cx, cz, i * 3 + 2);

                var x = ox + hx * CellSize;
                var z = oz + hz * CellSize;

                var y = (float)WorldData.TerrainH(x, z);
                if (y < WorldData.WaterLevel + 0.25f) continue;
                var y2 = (float)WorldData.TerrainH(x + 1f, z);
                var y3 = (float)WorldData.TerrainH(x, z + 1f);
                if (Mathf.Abs(y2 - y) > 0.9f || Mathf.Abs(y3 - y) > 0.9f) continue;

                var yaw   = hr * 360f;
                var scale = 0.75f + Hash3(cx, cz, i * 5 + 1) * 0.65f;
                var pos   = new Vector3(x, y - 0.04f, z);
                list.Add(Matrix4x4.TRS(pos, Quaternion.Euler(0f, yaw, 0f), new Vector3(scale, scale, scale)));
            }
            return list.ToArray();
        }

        /* Hash integer deterministik (bukan UnityEngine.Random): sel yang
           sama selalu menghasilkan rumput yang sama. */
        static float Hash3(int x, int z, int i)
        {
            var n = x * 127 + z * 311 + i * 741 + 1013;
            n = (n << 13) ^ n;
            var v = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff;
            return v / (float)0x7fffffff;
        }

        /* LOD DEKAT: rumpun 4 bilah meruncing (24 vertex, 16 segitiga).
           uv.y = tinggi normalized untuk gradasi + amplitudo angin. */
        static Mesh BuildClump()
        {
            var verts  = new List<Vector3>();
            var norms  = new List<Vector3>();
            var uvs    = new List<Vector2>();
            var tris   = new List<int>();

            for (var b = 0; b < 4; b++)
            {
                var yaw   = b * 90f + b * 17f;
                var tilt  = 14f + b * 5f;
                var h     = 0.30f + b * 0.05f;
                var w     = 0.05f;
                var rot   = Quaternion.Euler(0f, yaw, 0f);
                var lean  = Quaternion.Euler(0f, 0f, tilt);
                var fwd   = rot * lean * Vector3.forward;
                var side  = rot * Vector3.right;

                float[] ys = { 0f, h * 0.55f, h };
                float[] ws = { w, w * 0.62f, 0.004f };
                float[] cu = { 0f, 0.05f, 0.16f };
                float[] tv = { 0f, 0.55f, 1f };

                var baseIdx = verts.Count;
                for (var s = 0; s < 3; s++)
                {
                    var center = rot * lean * new Vector3(0f, ys[s], cu[s]);
                    verts.Add(center - side * ws[s]);
                    verts.Add(center + side * ws[s]);
                    norms.Add(fwd); norms.Add(fwd);
                    uvs.Add(new Vector2(b / 3f, tv[s]));
                    uvs.Add(new Vector2(b / 3f, tv[s]));
                }
                for (var s = 0; s < 2; s++)
                {
                    var i0 = baseIdx + s * 2;
                    tris.Add(i0); tris.Add(i0 + 1); tris.Add(i0 + 2);
                    tris.Add(i0 + 2); tris.Add(i0 + 1); tris.Add(i0 + 3);
                }
            }

            var mesh = new Mesh();
            mesh.name = "AureliaGrassClump";
            mesh.vertices  = verts.ToArray();
            mesh.normals   = norms.ToArray();
            mesh.uv        = uvs.ToArray();
            mesh.triangles = tris.ToArray();
            mesh.RecalculateBounds();
            return mesh;
        }

        /* LOD JAUH: 3 quad silang (12 vertex, 6 segitiga) — dari >14 m
           bentuknya terbaca sama, biayanya 2,6x lebih kecil. Shader yang
           sama (gradasi + angin dari uv.y), jadi transisinya mulus. */
        static Mesh BuildFarClump()
        {
            var verts = new List<Vector3>();
            var norms = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();

            for (var b = 0; b < 3; b++)
            {
                var yaw = b * 60f + b * 13f;
                var rot = Quaternion.Euler(0f, yaw, 0f);
                var side = rot * Vector3.right;
                var fwd = rot * Vector3.forward;
                var w = 0.17f;
                var h = 0.34f;
                var baseIdx = verts.Count;

                verts.Add(-side * w); verts.Add(side * w);
                verts.Add(-side * w * 0.55f + Vector3.up * h);
                verts.Add(side * w * 0.55f + Vector3.up * h);
                for (var k = 0; k < 4; k++) norms.Add(fwd);
                uvs.Add(new Vector2(0f, 0f)); uvs.Add(new Vector2(1f, 0f));
                uvs.Add(new Vector2(0.2f, 1f)); uvs.Add(new Vector2(0.8f, 1f));
                tris.Add(baseIdx); tris.Add(baseIdx + 1); tris.Add(baseIdx + 2);
                tris.Add(baseIdx + 2); tris.Add(baseIdx + 1); tris.Add(baseIdx + 3);
            }

            var mesh = new Mesh();
            mesh.name = "AureliaGrassFar";
            mesh.vertices = verts.ToArray();
            mesh.normals = norms.ToArray();
            mesh.uv = uvs.ToArray();
            mesh.triangles = tris.ToArray();
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
