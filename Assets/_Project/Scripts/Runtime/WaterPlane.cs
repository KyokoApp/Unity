using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       WATER PLANE — permukaan air.

       Sesuai DESAIN.md §4: "Air — shader, bukan mesh. Referensi sudah
       ada di world-data.mjs." Jadi di sini hanya satu quad besar yang
       mengikuti karakter, dan semua gerakannya dikerjakan di shader
       dari posisi dunia + waktu.

       Kenapa quad mengikuti karakter dan bukan satu plane 3 km:
       satu plane 3 km pada y=0 akan menutupi seluruh dunia dan
       membuang fill-rate di tempat yang tidak terlihat. Quad 2x radius
       streaming sudah menutup semua yang bisa terlihat.

       Posisinya di-SNAP ke kelipatan ukuran quad. Tanpa ini, quad yang
       mengikuti karakter akan membuat pola gelombang "berenang" mundur
       saat karakter berjalan — artefak klasik yang sangat terlihat.
       ============================================================ */
    [DisallowMultipleComponent]
    [ExecuteAlways]
    public class WaterPlane : MonoBehaviour
    {
        [Header("Target")]
        public Transform Target;

        [Header("Ukuran")]
        [Tooltip("Panjang sisi quad dalam meter. Harus >= 2x jangkauan pandang.")]
        public float Size = 1400f;

        [Header("Tampilan")]
        public Material WaterMaterial;
        [Tooltip("Offset kecil ke atas supaya tidak z-fighting dengan dasar air yang persis di y=0.")]
        public float HeightBias = 0.02f;

        Mesh _mesh;

        void Awake()
        {
            if (Target == null)
            {
                var motor = FindFirstObjectByType<CharacterMotor>();
                if (motor != null) Target = motor.transform;
            }
            EnsureMesh();
            var mr = GetComponent<MeshRenderer>();
            if (mr == null) mr = gameObject.AddComponent<MeshRenderer>();
            if (WaterMaterial != null) mr.sharedMaterial = WaterMaterial;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
            var mf = GetComponent<MeshFilter>();
            if (mf == null) mf = gameObject.AddComponent<MeshFilter>();
            mf.sharedMesh = _mesh;
        }

        void EnsureMesh()
        {
            if (_mesh != null) return;
            /* 8x8 subdivisi. Cukup untuk memberi gelombang skala besar sesuatu
               untuk digerakkan di vertex shader tanpa membuat quad polos. */
            const int N = 8;
            var verts = new Vector3[(N + 1) * (N + 1)];
            var uvs = new Vector2[verts.Length];
            var tris = new int[N * N * 6];
            for (var j = 0; j <= N; j++)
            for (var i = 0; i <= N; i++)
            {
                verts[j * (N + 1) + i] = new Vector3(i / (float)N - 0.5f, 0f, j / (float)N - 0.5f);
                uvs[j * (N + 1) + i] = new Vector2(i / (float)N, j / (float)N);
            }
            var t = 0;
            for (var j = 0; j < N; j++)
            for (var i = 0; i < N; i++)
            {
                var a = j * (N + 1) + i; var b = a + 1; var c = a + N + 1; var d = c + 1;
                // winding sama dengan TerrainMesh: normal harus +Y
                tris[t++] = a; tris[t++] = c; tris[t++] = b;
                tris[t++] = c; tris[t++] = d; tris[t++] = b;
            }
            _mesh = new Mesh { name = "WaterQuad", vertices = verts, uv = uvs, triangles = tris };
            _mesh.RecalculateNormals();
            _mesh.RecalculateBounds();
        }

        void LateUpdate()
        {
            if (Target == null) return;
            var p = Target.position;
            // snap ke kelipatan Size supaya shader (yang memakai posisi dunia)
            // tidak terlihat bergeser saat quad mengikuti karakter
            var sx = Mathf.Round(p.x / Size) * Size;
            var sz = Mathf.Round(p.z / Size) * Size;
            transform.position = new Vector3(sx, (float)WorldData.WaterLevel + HeightBias, sz);
            transform.localScale = new Vector3(Size, 1f, Size);
        }

        void OnDestroy() { ObjectUtil.SafeDestroy(_mesh); }
    }
}
