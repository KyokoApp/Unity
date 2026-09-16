using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    /* ============================================================
       WATER PLANE — permukaan air.

       Satu quad DATAR 1 segmen (4 verteks) yang mengikuti karakter.
       SEMUA gelombang dihitung di fragment shader dari posisi dunia
       + waktu (lihat AureliaWater.shader).

       PERBAIKAN BUG Tahap 5: dulu quad 8x8 (81 verteks) dengan
       displacement di VERTEX. Di atas bentang 1.400 m itu 1 verteks
       tiap 175 m untuk gelombang sepanjang ~110 m — undersampling
       parah, gelombangnya terlihat acak. Sekarang quad polos +
       normal fragment: benar DAN lebih murah.

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
            // Satu quad: gelombang tidak butuh tessellasi karena murni
            // dihitung di fragment (normal analitik).
            var verts = new Vector3[]
            {
                new Vector3(-0.5f, 0f, -0.5f), new Vector3(0.5f, 0f, -0.5f),
                new Vector3(-0.5f, 0f,  0.5f), new Vector3(0.5f, 0f,  0.5f),
            };
            var uvs = new Vector2[]
            {
                new Vector2(0f, 0f), new Vector2(1f, 0f),
                new Vector2(0f, 1f), new Vector2(1f, 1f),
            };
            // winding sama dengan TerrainMesh: normal harus +Y
            var tris = new int[] { 0, 2, 1, 2, 3, 1 };
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
