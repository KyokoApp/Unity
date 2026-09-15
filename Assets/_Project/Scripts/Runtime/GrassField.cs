// ============================================================
// GrassField.cs
//
// Rumput Tahap 4: rumpun bilah bergaya stylized (ala Genshin: warna
// gradasi pangkal->ujung, goyangan angin, tanpa tekstur) yang ditarik
// SATU draw call per 1023 rumpun lewat Graphics.DrawMeshInstanced.
//
// KENAPA INSTANCED, BUKAN MESH RAKSASA
// ------------------------------------
// Jumlah rumpun datang dari sistem kualitas yang sudah ada di Core
// (GfxResolver.GrassCount -- angka yang sama dengan game three.js
// aslinya: 9.000 rumpun di sekitar pemain pada tingkat tertinggi untuk
// perangkat sentuh). Membangun ulang mesh 40 ribu vertex setiap pemain
// melangkah akan menyebabkan hitch; dengan instancing, yang diperbarui
// hanya daftar matriks per sel 8 m, dan sel yang tidak berubah dipakai
// ulang dari cache.
//
// KENAPA TANPA TEKSTUR
// --------------------
// Tekstur alpha rumput butuh atlas + alpha-testing (sortir & bandwidth
// di HP menengah). Bentuk bilah sudah meruncing di geometri, jadi
// siluetnya dibaca sebagai rumput meski warnanya flat -- justru itu
// tampilan stylized yang dicari. Angin dikerjakan di vertex shader
// (AureliaGrass.shader), bukan di CPU.
//
// Penempatan deterministik: hash integer sel+indeks, jadi posisi rumput
// sama setiap kali pemain kembali ke tempat yang sama (tidak "berkedip"
// saat sel dibangun ulang), dan tidak butuh Random ber-seed.
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

        [Tooltip("Radius sebaran rumput di sekitar target (m).")]
        [Range(10f, 60f)] public float Radius = 30f;

        [Tooltip("Ukuran sel cache. 8 m = setengah chunk terrain.")]
        public float CellSize = 8f;

        [Tooltip("Rumpun per sel pada tingkat kualitas penuh; skala kualitas diterapkan di Awake.")]
        [Range(4, 96)] public int PerCellBase = 26;

        public int ActiveClumps { get; private set; }
        public int ActiveCells  => _cells.Count;

        Mesh _clump;
        readonly Dictionary<long, Matrix4x4[]> _cells = new Dictionary<long, Matrix4x4[]>();
        /* DrawMeshInstanced di Unity 6 hanya menerima Matrix4x4[] (tidak ada
           overload List<>), jadi pakai array pakai-ulang: tanpa alokasi per
           frame, tanpa GC pressure di HP. */
        readonly Matrix4x4[] _batch = new Matrix4x4[1023];
        int _batchN;
        int _lastCx = int.MinValue, _lastCz;
        int _perCell;
        bool _on;

        void Awake()
        {
            /* Tingkat kualitas dibaca dari setelan tersimpan, supaya rumput
               ikut preset rendah/tinggi yang nanti dipilih pemain -- dan
               supaya build CI (tanpa PlayerPrefs) jatuh ke default
               'balanced', bukan ke nol. */
            var resolved = GfxResolver.Resolve(SettingsStore.Load(), true);
            _on = resolved.GrassEnabled;
            if (!_on) return;

            var scale = resolved.GrassCount > 0 && PerCellBase > 0
                ? (double)resolved.GrassCount / (PerCellBase * CellCount())
                : 0.0;
            _perCell = Mathf.Max(4, Mathf.RoundToInt(PerCellBase * (float)scale));

            _clump = BuildClump();

            if (Target == null)
            {
                var motor = Object.FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
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

        /* Dipanggil tiap frame saat bermain: gambar semua sel yang terlihat. */
        void LateUpdate() => DrawNow();

        /* Untuk screenshot batchmode (tidak ada loop Update di edit mode)
           dan untuk kasus Target dipindah teleport. */
        public void PopulateNow()
        {
            if (!_on || Target == null) return;
            RefreshCells(Target.position, true);
        }

        public void DrawNow()
        {
            if (!_on || _clump == null || GrassMaterial == null || Target == null) return;

            RefreshCells(Target.position, false);

            _batchN = 0;
            ActiveClumps = 0;
            foreach (var kv in _cells)
            {
                var arr = kv.Value;
                for (var i = 0; i < arr.Length; i++)
                {
                    _batch[_batchN++] = arr[i];
                    if (_batchN == 1023) Flush();
                }
            }
            Flush();
        }

        /* KHUSUS SCREENSHOT (dipakai Editor/SceneShots): gabungan SEMUA
           instance jadi SATU mesh bake world-space. Jalur ini kebal terhadap
           quirks pipeline (CommandBuffer kamera di URP bisa diam-diam
           diabaikan; DrawMeshInstanced biasa butuh frame berikutnya).
           2.250 instance x 15 vertex = ~34 ribu vertex — ringan untuk
           sekali render editor. Play mode tetap pakai instancing. */
        public int BakeInto(Mesh dst)
        {
            if (!_on || _clump == null || Target == null || dst == null) return 0;
            RefreshCells(Target.position, false);
            var sv = _clump.vertices; var su = _clump.uv; var sc = _clump.colors; var st = _clump.triangles;
            if (sv == null || st == null) return 0;
            var perV = sv.Length; var perT = st.Length;
            var n = 0; foreach (var kv in _cells) n += kv.Value.Length;
            if (n == 0 || perV == 0) return 0;
            var V = new Vector3[n * perV]; var U = new Vector2[n * perV]; var C = new Color[n * perV]; var T = new int[n * perT];
            var vi = 0; var ti = 0; var baseV = 0;
            foreach (var kv in _cells)
            {
                foreach (var m in kv.Value)
                {
                    for (var i = 0; i < perV; i++) { V[vi] = m.MultiplyPoint3x4(sv[i]); U[vi] = su[i]; C[vi] = sc[i]; vi++; }
                    for (var i = 0; i < perT; i++) T[ti++] = st[i] + baseV;
                    baseV += perV;
                }
            }
            dst.vertices = V; dst.uv = U; dst.colors = C; dst.triangles = T;
            dst.RecalculateBounds();
            return n;
        }

        /* Untuk screenshot batchmode: DrawMeshInstanced yang dipanggil
           "apa adanya" hanya ikut pada render frame berikutnya, dan di
           edit mode tidak ada frame berikutnya sebelum cam.Render().
           Lewat CommandBuffer, perintah gambarnya MENEMPEL di kamera,
           jadi pasti ikut saat kamera dirender manual. */
        public void DrawInto(UnityEngine.Rendering.CommandBuffer cmd)
        {
            if (!_on || _clump == null || GrassMaterial == null || Target == null || cmd == null) return;
            RefreshCells(Target.position, false);
            _batchN = 0;
            foreach (var kv in _cells)
            {
                var arr = kv.Value;
                for (var i = 0; i < arr.Length; i++)
                {
                    _batch[_batchN++] = arr[i];
                    if (_batchN == 1023) { cmd.DrawMeshInstanced(_clump, 0, GrassMaterial, 0, _batch, _batchN); _batchN = 0; }
                }
            }
            if (_batchN > 0) cmd.DrawMeshInstanced(_clump, 0, GrassMaterial, 0, _batch, _batchN);
            _batchN = 0;
        }

        void Flush()
        {
            if (_batchN == 0) return;
            Graphics.DrawMeshInstanced(_clump, 0, GrassMaterial, _batch, _batchN);
            ActiveClumps += _batchN;
            _batchN = 0;
        }

        void RefreshCells(Vector3 p, bool force)
        {
            var cx = Mathf.FloorToInt(p.x / CellSize);
            var cz = Mathf.FloorToInt(p.z / CellSize);
            if (!force && cx == _lastCx && cz == _lastCz && _cells.Count > 0) return;
            _lastCx = cx; _lastCz = cz;

            _cells.Clear();
            var n = Mathf.CeilToInt(Radius / CellSize);
            var r2 = Radius * Radius;
            for (var x = cx - n; x <= cx + n; x++)
            {
                for (var z = cz - n; z <= cz + n; z++)
                {
                    var dx = (x + 0.5f) * CellSize - p.x;
                    var dz = (z + 0.5f) * CellSize - p.z;
                    if (dx * dx + dz * dz > r2) continue;
                    var cell = PlaceCell(x, z);
                    if (cell.Length > 0) _cells[Key(x, z)] = cell;
                }
            }
        }

        static long Key(int x, int z) => ((long)x << 32) | (uint)z;

        Matrix4x4[] PlaceCell(int cx, int cz)
        {
            var list = new List<Matrix4x4>(_perCell);
            var ox = cx * CellSize;
            var oz = cz * CellSize;

            for (var i = 0; i < _perCell; i++)
            {
                var hx = Hash3(cx, cz, i * 3);
                var hz = Hash3(cx, cz, i * 3 + 1);
                var hr = Hash3(cx, cz, i * 3 + 2);

                var x = ox + hx * CellSize;
                var z = oz + hz * CellSize;

                /* Tidak ada rumput di bawah permukaan air, dan tidak di
                   tebing curam: selain aneh dilihat, bilah di tebing akan
                   menonjol keluar dari lereng. */
                var y = (float)WorldData.TerrainH(x, z);
                if (y < WorldData.WaterLevel + 0.25f) continue;
                var y2 = (float)WorldData.TerrainH(x + 1f, z);
                var y3 = (float)WorldData.TerrainH(x, z + 1f);
                if (Mathf.Abs(y2 - y) > 0.9f || Mathf.Abs(y3 - y) > 0.9f) continue;

                var yaw   = hr * 360f;
                var scale = 0.75f + Hash3(cx, cz, i * 5 + 1) * 0.65f;
                var pos   = new Vector3(x, y - 0.04f, z);   // sedikit tenggelam supaya pangkal tidak mengambang
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

        /* Satu rumpun = 3 bilah meruncing, masing-masing 3 penampang
           (pangkal-lebar, tengah, ujung-runcing). 18 vertex, 12 segitiga:
           cukup murah untuk ribuan instance, cukup berbentuk untuk dibaca
           sebagai rumput. uv.y = tinggi normalized (0..1) untuk gradasi
           warna dan amplitudo angin di shader. */
        static Mesh BuildClump()
        {
            var verts  = new List<Vector3>();
            var norms  = new List<Vector3>();
            var uvs    = new List<Vector2>();
            var tris   = new List<int>();

            for (var b = 0; b < 3; b++)
            {
                var yaw   = b * 120f + b * 17f;
                var tilt  = 14f + b * 6f;
                var h     = 0.30f + b * 0.06f;
                var w     = 0.045f;
                var rot   = Quaternion.Euler(0f, yaw, 0f);
                var lean  = Quaternion.Euler(0f, 0f, tilt);
                var fwd   = rot * lean * Vector3.forward;
                var side  = rot * Vector3.right;

                /* penampang: (tinggi, lebar, lengkung ke depan) */
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
    }
}
