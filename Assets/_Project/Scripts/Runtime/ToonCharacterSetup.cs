using System.Collections.Generic;
using UnityEngine;

namespace RPG.Runtime
{
    /* ============================================================
       TOON CHARACTER SETUP — konversi material VRM -> toon dalam
       SATU LANGKAH, saat runtime.

       Kenapa runtime, bukan mengedit prefab: scene dibangun ulang
       dari prefab setiap build — perubahan material di scene TIDAK
       bertahan. Komponen ini dipasang builder di root karakter dan
       menukar material di Awake, jadi berlaku untuk prefab VRM
       mana pun, selamanya.

       Aturan konversi (heuristik + eksplisit):
       - Opaque     -> Aurelia/Toon (dengan outline)
       - Transparan -> Aurelia/ToonLite (TANPA outline — outline di
         alis/bulu mata/iris justru merusak wajah)
       - Cutout     -> Aurelia/Toon + alpha clip (bayangan rambut
         mengikuti lubang alpha)
       - _MainTex -> _BaseMap, _Color -> _BaseColor, _EmissionColor
         + _Cutoff + _CullMode ikut disalin kalau ada.
       - Material bernama *hair* dapat specular boost, *eye* dapat
         glint boost (heuristik nama — aman kalau tidak cocok).

       Material ASLI tidak diubah (diganti di instance scene saja),
       jadi prefab + file .vrm tetap perawan dan konversi bisa
       diulang kapan saja.
       ============================================================ */
    [DisallowMultipleComponent]
    public class ToonCharacterSetup : MonoBehaviour
    {
        [Header("Sumber")]
        [Tooltip("Root karakter. Kosong = GameObject ini.")]
        public Transform CharacterRoot;

        [Header("Ramp")]
        [Tooltip("Tekstur ramp 1D. Kosong = prosedural murni (tanpa aset).")]
        public Texture RampTexture;

        [Header("Outline (material opaque)")]
        public Color OutlineColor = new Color(0.08f, 0.07f, 0.10f, 1f);
        [Range(0f, 0.05f)] public float OutlineWidth = 0.008f;
        [Tooltip("Outline nyala. Dimatikan QualityApplier di preset Rendah.")]
        public bool OutlineEnabled = true;

        [Header("Transparan")]
        [Tooltip("Material transparan tetap menulis depth (seperti MToon wajah) — " +
                 "mencegah bulu mata/alis tembus rambut. Matikan kalau ada halo.")]
        public bool TransparentZWrite = true;

        struct Slot
        {
            public Renderer Renderer;
            public int Index;
            public bool Opaque;
            public Material ToonMat;
        }

        readonly List<Slot> _slots = new List<Slot>();
        Shader _toon;
        Shader _lite;

        static readonly int BaseMapId = Shader.PropertyToID("_BaseMap");
        static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
        static readonly int RampMapId = Shader.PropertyToID("_RampMap");
        static readonly int RampStrId = Shader.PropertyToID("_RampStrength");
        static readonly int OutlineColorId = Shader.PropertyToID("_OutlineColor");
        static readonly int OutlineWidthId = Shader.PropertyToID("_OutlineWidth");
        static readonly int SpecStrId = Shader.PropertyToID("_SpecStrength");
        static readonly int SpecPowId = Shader.PropertyToID("_SpecPower");
        static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");
        static readonly int SurfaceId = Shader.PropertyToID("_Surface");
        static readonly int SrcBlendId = Shader.PropertyToID("_SrcBlend");
        static readonly int DstBlendId = Shader.PropertyToID("_DstBlend");
        static readonly int ZWriteId = Shader.PropertyToID("_ZWrite");
        static readonly int CullId = Shader.PropertyToID("_Cull");
        static readonly int AlphaClipId = Shader.PropertyToID("_AlphaClip");
        static readonly int CutoffId = Shader.PropertyToID("_Cutoff");

        void Awake()
        {
            if (CharacterRoot == null) CharacterRoot = transform;
            Convert();
        }

        /* Dipanggil QualityApplier saat preset berubah. */
        public void SetOutlineEnabled(bool on)
        {
            OutlineEnabled = on;
            if (_toon == null || _lite == null) return;
            foreach (var s in _slots)
            {
                if (!s.Opaque || s.ToonMat == null) continue;
                s.ToonMat.shader = on ? _toon : _lite;
            }
        }

        public int ConvertedCount => _slots.Count;

        public void Convert()
        {
            _slots.Clear();
            _toon = Shader.Find("Aurelia/Toon");
            _lite = Shader.Find("Aurelia/ToonLite");
            if (_toon == null || _lite == null)
            {
                Debug.LogWarning("[Toon] shader Aurelia/Toon tidak ketemu — konversi dilewati.");
                return;
            }
            if (CharacterRoot == null) return;

            var renderers = CharacterRoot.GetComponentsInChildren<Renderer>(true);
            foreach (var r in renderers)
            {
                var mats = r.sharedMaterials;
                if (mats == null || mats.Length == 0) continue;
                var swapped = false;
                for (var i = 0; i < mats.Length; i++)
                {
                    var m = mats[i];
                    if (m == null) continue;
                    // Idempoten: lewati yang sudah toon.
                    if (m.shader != null && m.shader.name.StartsWith("Aurelia/Toon"))
                    {
                        ApplyRamp(m);
                        continue;
                    }
                    var kind = Classify(m);
                    var useLite = kind != Kind.Opaque || !OutlineEnabled;
                    var nm = new Material(useLite ? _lite : _toon);
                    nm.name = m.name + "_Toon";
                    CopySurface(m, nm, kind);
                    ApplyRamp(nm);
                    ApplyHeuristics(m, nm);
                    mats[i] = nm;
                    swapped = true;
                    _slots.Add(new Slot
                        { Renderer = r, Index = i, Opaque = kind == Kind.Opaque, ToonMat = nm });
                }
                if (swapped) r.sharedMaterials = mats;
            }
            Debug.Log($"[Toon] {_slots.Count} material dikonversi ke toon.");
        }

        enum Kind { Opaque, Cutout, Transparent }

        static Kind Classify(Material m)
        {
            // MToon (VRM): _BlendMode 0=opaque 1=cutout 2=transparan 3=transparan+ZWrite.
            if (m.HasProperty("_BlendMode"))
            {
                var b = m.GetFloat("_BlendMode");
                if (b >= 1.5f) return Kind.Transparent;
                if (b >= 0.5f) return Kind.Cutout;
                return Kind.Opaque;
            }
            // Fallback generik: queue + alpha.
            if (m.renderQueue >= 3000) return Kind.Transparent;
            if (m.HasProperty("_Color") && m.GetColor("_Color").a < 0.99f)
                return Kind.Transparent;
            return Kind.Opaque;
        }

        void CopySurface(Material src, Material dst, Kind kind)
        {
            if (src.HasProperty("_MainTex"))
                dst.SetTexture(BaseMapId, src.GetTexture("_MainTex"));
            dst.SetColor(BaseColorId,
                src.HasProperty("_Color") ? src.GetColor("_Color") : Color.white);
            if (src.HasProperty("_EmissionColor"))
                dst.SetColor(EmissionId, src.GetColor("_EmissionColor"));

            var cull = src.HasProperty("_CullMode") ? src.GetFloat("_CullMode") : 2f;
            dst.SetFloat(CullId, cull);

            if (kind == Kind.Opaque)
            {
                dst.SetFloat(SurfaceId, 0f);
                dst.SetFloat(SrcBlendId, 1f);    // One
                dst.SetFloat(DstBlendId, 0f);    // Zero
                dst.SetFloat(ZWriteId, 1f);
                dst.SetFloat(AlphaClipId, 0f);
                dst.renderQueue = -1;
            }
            else if (kind == Kind.Cutout)
            {
                dst.SetFloat(SurfaceId, 0f);
                dst.SetFloat(SrcBlendId, 1f);
                dst.SetFloat(DstBlendId, 0f);
                dst.SetFloat(ZWriteId, 1f);
                dst.SetFloat(AlphaClipId, 1f);
                dst.SetFloat(CutoffId,
                    src.HasProperty("_Cutoff") ? src.GetFloat("_Cutoff") : 0.5f);
                dst.renderQueue = 2450;
            }
            else
            {
                dst.SetFloat(SurfaceId, 1f);
                dst.SetFloat(SrcBlendId, 5f);    // SrcAlpha
                dst.SetFloat(DstBlendId, 10f);   // OneMinusSrcAlpha
                dst.SetFloat(ZWriteId, TransparentZWrite ? 1f : 0f);
                dst.SetFloat(AlphaClipId, 0f);
                dst.renderQueue = 3000;
            }

            dst.SetColor(OutlineColorId, OutlineColor);
            dst.SetFloat(OutlineWidthId, OutlineWidth);
        }

        void ApplyRamp(Material m)
        {
            if (RampTexture != null)
            {
                m.SetTexture(RampMapId, RampTexture);
                m.SetFloat(RampStrId, 1f);
            }
            else m.SetFloat(RampStrId, 0f);
        }

        /* Heuristik nama material — hanya menguatkan, tidak mengubah. */
        static void ApplyHeuristics(Material src, Material dst)
        {
            var n = src.name.ToLowerInvariant();
            if (n.Contains("hair") || n.Contains("rambut"))
            {
                dst.SetFloat(SpecStrId, 1.0f);
                dst.SetFloat(SpecPowId, 60f);
            }
            if (n.Contains("eye") || n.Contains("iris") || n.Contains("pupil") ||
                n.Contains("cornea") || n.Contains("mata"))
            {
                dst.SetFloat(SpecStrId, 1.2f);
                dst.SetFloat(SpecPowId, 90f);
            }
        }
    }
}
