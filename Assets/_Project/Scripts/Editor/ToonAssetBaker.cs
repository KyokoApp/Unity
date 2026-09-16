using System.IO;
using UnityEditor;
using UnityEngine;

namespace RPG.Editor
{
    /* ============================================================
       TOON ASSET BAKER — konversi material permanen (SESUATU YANG
       DILIHAT) sebagai pendamping ToonCharacterSetup (runtime).

       Cara pakai:
         1. Di Project, pilih material (boleh banyak sekaligus).
         2. Menu: Aurelia/Toon/Bake Selected Materials To Toon.
         3. Material "*_Toon.mat" muncul di sebelah aslinya.

       Kenapa dua jalur? ToonCharacterSetup menukar material SAAT
       BERMAIN — prefab VRM mana pun langsung jadi toon tanpa
       disentuh. Tapi hasilnya tidak terlihat di Inspector dan tidak
       ikut ke build lain. Baker ini untuk material yang mau
       dikunci permanen (properti, NPC, senjata): sekali klik, aset
       .mat beneran, bisa diutak-atik manual setelahnya.

       Aturan konversi SAMA dengan runtime:
         opaque -> Aurelia/Toon (outline) | transparan/cutout ->
         Aurelia/ToonLite (tanpa outline) — lihat ToonCharacterSetup
         untuk alasannya.
       ============================================================ */
    public static class ToonAssetBaker
    {
        const string ToonShader = "Aurelia/Toon";
        const string LiteShader = "Aurelia/ToonLite";

        [MenuItem("Aurelia/Toon/Bake Selected Materials To Toon")]
        public static void BakeSelected()
        {
            var toon = Shader.Find(ToonShader);
            var lite = Shader.Find(LiteShader);
            if (toon == null || lite == null)
            {
                Debug.LogError("[ToonBaker] shader Aurelia/Toon tidak ketemu. " +
                               "Pastikan folder Assets/_Project/Shaders ada di proyek.");
                return;
            }
            var n = 0;
            foreach (var o in Selection.objects)
            {
                var src = o as Material;
                if (src == null) continue;
                if (src.shader != null && src.shader.name.StartsWith("Aurelia/Toon"))
                    continue;
                if (BakeOne(src, toon, lite)) n++;
            }
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log($"[ToonBaker] {n} material selesai di-bake.");
        }

        static bool BakeOne(Material src, Shader toon, Shader lite)
        {
            var path = AssetDatabase.GetAssetPath(src);
            if (string.IsNullOrEmpty(path)) return false;   // bukan aset (mis. bawaan scene)

            var transparent = src.renderQueue >= 3000 ||
                (src.HasProperty("_Color") && src.GetColor("_Color").a < 0.99f);
            var dst = new Material(transparent ? lite : toon);

            if (src.HasProperty("_MainTex"))
                dst.SetTexture("_BaseMap", src.GetTexture("_MainTex"));
            dst.SetColor("_BaseColor",
                src.HasProperty("_Color") ? src.GetColor("_Color") : Color.white);
            if (src.HasProperty("_EmissionColor"))
                dst.SetColor("_EmissionColor", src.GetColor("_EmissionColor"));
            dst.SetFloat("_Cull",
                src.HasProperty("_CullMode") ? src.GetFloat("_CullMode") : 2f);
            if (transparent)
            {
                dst.SetFloat("_Surface", 1f);
                dst.SetFloat("_SrcBlend", 5f);    // SrcAlpha
                dst.SetFloat("_DstBlend", 10f);   // OneMinusSrcAlpha
                dst.SetFloat("_ZWrite", 0f);
                dst.renderQueue = 3000;
            }
            else
            {
                dst.SetFloat("_Surface", 0f);
                dst.renderQueue = -1;
            }

            var dir = Path.GetDirectoryName(path).Replace('\\', '/');
            var outPath = dir + "/" + Path.GetFileNameWithoutExtension(path) + "_Toon.mat";
            if (outPath == path) return false;
            AssetDatabase.DeleteAsset(outPath);   // tulis ulang kalau sudah ada
            AssetDatabase.CreateAsset(dst, outPath);
            return true;
        }
    }
}
