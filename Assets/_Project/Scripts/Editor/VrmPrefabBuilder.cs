// ============================================================
// VrmPrefabBuilder.cs
//
// MENGAPA FILE INI ADA
// --------------------
// UniVRM sudah punya AssetPostprocessor (VRM.vrmAssetPostprocessor) yang
// otomatis mengubah Assets/Art/Characters/AureliaChar.vrm menjadi
// AureliaChar.prefab begitu file-nya diimpor. Di Editor interaktif itu
// jalan. Di GitHub Actions TIDAK.
//
// Alasannya ada di TextureExtractor.ExtractTextures (UniGLTF):
//
//     // menulis PNG ke disk                     <- SINKRON
//     ...
//     EditorApplication.delayCall += () => {     <- DITUNDA
//         onCompleted(extractor.Textures.Values);
//     };
//
// dan pembuatan prefab (VRMEditorImporterContext.SaveAsAsset) ada di dalam
// onCompleted itu. Di batchmode, BuildPlayer dipanggil sebelum
// EditorApplication.delayCall sempat dijalankan -- tidak ada loop Editor
// yang berdetak di sela-selanya. Buktinya di log build CI ke-4
// (run 34926918799):
//
//     Start importing Assets/Art/Characters/AureliaChar.Textures/KK Teeth...
//     (puluhan tekstur terekstrak -- bagian sinkron JALAN)
//     [Aurelia] - Prefab VRM belum ditemukan di Assets/Art/Characters.
//                 Dipakai capsule placeholder...
//
// Hasilnya: APK jadi, tapi isinya kapsul, bukan karakter.
//
// File ini mengerjakan ulang persis alur UniVRM -- ExtractTextures lalu
// SaveAsAsset -- TANPA menunda apa pun, sehingga aman dipanggil dari
// OnPreprocessBuild. Kodenya disalin dari vrmAssetPostprocessor.cs dan
// VRMEditorImporterContext.cs UniVRM v0.131.2 (tag yang sama dengan yang
// dikunci di Packages/manifest.json), bukan dikarang.
// ============================================================
using System;
using System.Collections.Generic;
using System.IO;
using UniGLTF;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;
using VRM;

namespace RPG.Editor
{
    public static class VrmPrefabBuilder
    {
        public const string VrmFile    = Stage2SceneBuilder.CharFolder + "/AureliaChar.vrm";
        public const string PrefabFile = Stage2SceneBuilder.CharFolder + "/AureliaChar.prefab";
        // Nama folder ini dibentuk UniVRM sebagai "<namaPrefab>.Textures".
        public const string TextureDir = Stage2SceneBuilder.CharFolder + "/AureliaChar.Textures";

        /// <summary>
        /// Pastikan prefab karakter ada. Return true kalau prefab tersedia
        /// (sudah ada, atau baru saja dibangun).
        /// </summary>
        public static bool EnsurePrefab(List<string> log)
        {
            if (!File.Exists(VrmFile))
            {
                log.Add("AureliaChar.vrm tidak ada di " + Stage2SceneBuilder.CharFolder +
                        " -- prefab karakter tidak dibangun, scene memakai kapsul placeholder.");
                return false;
            }

            var existingPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabFile);
            if (existingPrefab != null)
            {
                log.Add("Prefab karakter sudah ada: " + PrefabFile);
                // Tetap convert ke cel-shading kalau masih MToon
                try { ConvertToCelShading(existingPrefab, log); } catch (System.Exception e) { log.Add("Convert cel-shading skip: " + e.Message); }
                return true;
            }

            var vrmPath    = UnityPath.FromUnityPath(VrmFile);
            var prefabPath = UnityPath.FromUnityPath(PrefabFile);

            try
            {
                ExtractTextures(vrmPath, prefabPath, log);

                /* PNG yang baru ditulis harus benar-benar jadi asset dulu
                   sebelum bisa dipakai sebagai externalObjectMap. Di alur
                   UniVRM jeda ini diisi oleh delayCall; di sini diisi
                   Refresh() yang sinkron. */
                AssetDatabase.Refresh();

                var externalTextures = LoadExtractedTextures();
                log.Add("Tekstur karakter terbaca dari disk: " + externalTextures.Count +
                        " file di " + TextureDir);

                BuildPrefab(vrmPath, prefabPath, externalTextures);
            }
            catch (NotVrm0Exception)
            {
                throw new BuildFailedException(
                    "[Aurelia] " + VrmFile + " bukan VRM 0.x. Paket yang terpasang " +
                    "(com.vrmc.univrm) hanya membaca VRM 0.x. Kalau modelnya VRM 1.0, " +
                    "tambahkan 'com.vrmc.vrm' ke Packages/manifest.json.");
            }
            catch (Exception e)
            {
                /* Gagal di sini jauh lebih berguna daripada APK berisi kapsul:
                   pengguna memasang 25 MB, memainkannya, dan mendapati
                   karakternya tidak ada -- tanpa pesan apa pun. */
                throw new BuildFailedException(
                    "[Aurelia] Gagal membangun prefab karakter dari " + VrmFile +
                    ": " + e.GetType().Name + ": " + e.Message + "\n" + e.StackTrace);
            }

            AssetDatabase.Refresh();

            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabFile);
            if (prefab == null)
            {
                throw new BuildFailedException(
                    "[Aurelia] Impor VRM selesai tanpa exception tapi " + PrefabFile +
                    " tetap tidak ada. Scene akan berisi kapsul placeholder, jadi build dihentikan.");
            }

            var meshCount = prefab.GetComponentsInChildren<SkinnedMeshRenderer>(true).Length;
            log.Add("Prefab karakter dibangun: " + PrefabFile +
                    " (" + meshCount + " SkinnedMeshRenderer)");

            // FIX: Convert MToon (Built-in) ke CharCel (URP cel-shading Genshin)
            // MToon 0.x tidak support URP -> magenta di build. Convert ke Aurelia/CharCel
            try
            {
                ConvertToCelShading(prefab, log);
            }
            catch (System.Exception e)
            {
                log.Add("PERINGATAN: Convert ke cel-shading gagal: " + e.Message + " — karakter mungkin magenta");
            }

            return true;
        }

        /* Langkah 1: konversi material + tulis tekstur ke disk.
           Callback-nya sengaja diabaikan karena dipanggil lewat
           EditorApplication.delayCall -- kita ambil teksturnya sendiri
           dari folder hasil ekstraksi. */
        static void ExtractTextures(UnityPath vrmPath, UnityPath prefabPath, List<string> log)
        {
            using (var data = new GlbFileParser(vrmPath.FullPath).Parse())
            using (var context = new VRMImporterContext(new VRMData(data)))
            {
                var editor = new VRMEditorImporterContext(context, prefabPath);
                editor.ConvertAndExtractImages(_ => { });
            }
            log.Add("Tekstur VRM diekstrak (sinkron, tanpa delayCall).");
        }

        static Dictionary<SubAssetKey, UnityEngine.Object> LoadExtractedTextures()
        {
            var map = new Dictionary<SubAssetKey, UnityEngine.Object>();
            if (!AssetDatabase.IsValidFolder(TextureDir)) return map;

            foreach (var guid in AssetDatabase.FindAssets("t:Texture", new[] { TextureDir }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var tex  = AssetDatabase.LoadAssetAtPath<Texture>(path);
                if (tex == null) continue;
                /* UniVRM memakai ToDictionary() yang melempar kalau ada nama
                   ganda; di sini ditimpa saja -- yang penting kuncinya ada. */
                map[new SubAssetKey(tex)] = tex;
            }
            return map;
        }

        // Convert MToon materials ke Aurelia/CharCel (URP cel-shading Genshin)
        static void ConvertToCelShading(GameObject prefab, List<string> log)
        {
            var celShader = Shader.Find("Aurelia/CharCel");
            if (celShader == null)
            {
                log.Add("Shader Aurelia/CharCel tidak ketemu — skip convert cel-shading");
                return;
            }

            int converted = 0;
            var renderers = prefab.GetComponentsInChildren<Renderer>(true);
            foreach (var r in renderers)
            {
                var mats = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    var m = mats[i];
                    if (m == null) continue;
                    // Cek apakah ini MToon (Built-in) atau sudah URP
                    if (m.shader != null && m.shader.name.Contains("MToon"))
                    {
                        var newMat = new Material(celShader);
                        newMat.name = m.name + "_Cel";

                        // Copy base texture & color
                        if (m.HasProperty("_MainTex"))
                        {
                            var tex = m.GetTexture("_MainTex");
                            if (tex != null) newMat.SetTexture("_BaseMap", tex);
                        }
                        if (m.HasProperty("_Color"))
                            newMat.SetColor("_BaseColor", m.GetColor("_Color"));
                        else if (m.HasProperty("_BaseColor"))
                            newMat.SetColor("_BaseColor", m.GetColor("_BaseColor"));
                        else
                            newMat.SetColor("_BaseColor", Color.white);

                        // Shade color dari MToon
                        if (m.HasProperty("_ShadeColor"))
                            newMat.SetColor("_ShadeColor", m.GetColor("_ShadeColor"));
                        else
                            newMat.SetColor("_ShadeColor", new Color(0.78f, 0.82f, 0.90f, 1f));

                        // Shade texture kalau ada
                        if (m.HasProperty("_ShadeTexture"))
                        {
                            var shadeTex = m.GetTexture("_ShadeTexture");
                            if (shadeTex != null) newMat.SetTexture("_ShadeMap", shadeTex);
                        }

                        // Outline
                        if (m.HasProperty("_OutlineWidth"))
                        {
                            float ow = m.GetFloat("_OutlineWidth");
                            // MToon outline width dalam 0..1, convert ke meter
                            newMat.SetFloat("_OutlineWidth", Mathf.Clamp(ow * 0.02f, 0f, 0.05f));
                        }
                        if (m.HasProperty("_OutlineColor"))
                            newMat.SetColor("_OutlineColor", m.GetColor("_OutlineColor"));

                        // Simpan material baru sebagai asset (supaya tidak hilang)
                        var matPath = $"{TextureDir}/{newMat.name}.mat";
                        // Pastikan folder ada -- LEWAT AssetDatabase, bukan
                        // System.IO.Directory.CreateDirectory. Folder yang dibuat diam-diam
                        // dengan CreateDirectory tidak dikenal AssetDatabase, jadi
                        // CreateAsset melempar exception; exception di OnPreprocessBuild
                        // = seluruh build APK berhenti dengan exit code 1.
                        EnsureAssetFolder(TextureDir);
                        // Kalau sudah ada, timpa
                        var existing = AssetDatabase.LoadAssetAtPath<Material>(matPath);
                        if (existing != null)
                        {
                            existing.shader = celShader;
                            existing.CopyPropertiesFromMaterial(newMat);
                            mats[i] = existing;
                        }
                        else
                        {
                            AssetDatabase.CreateAsset(newMat, matPath);
                            mats[i] = newMat;
                        }
                        changed = true;
                        converted++;
                    }
                }
                if (changed)
                {
                    r.sharedMaterials = mats;
                    EditorUtility.SetDirty(r);
                }
            }

            if (converted > 0)
            {
                EditorUtility.SetDirty(prefab);
                // Save prefab changes
                PrefabUtility.SaveAsPrefabAsset(prefab, PrefabFile);
                log.Add($"Cel-shading: {converted} material MToon -> Aurelia/CharCel (Genshin-style)");
            }
            else
            {
                log.Add("Cel-shading: tidak ada material MToon yang perlu di-convert (mungkin sudah URP atau kapsul)");
            }
        }

        /* Pastikan sebuah folder di bawah Assets/ dikenal AssetDatabase.
           Dibuat lewat AssetDatabase.CreateFolder, BUKAN Directory.CreateDirectory:
           folder yang dibuat diam-diam dengan CreateDirectory tidak dikenal
           AssetDatabase, jadi CreateAsset melempar -- dan exception yang lolos dari
           OnPreprocessBuild membunuh seluruh build APK dengan exit code 1.
           Helper ini menelan semua kegagalan sendiri: gagal bikin folder tidak boleh
           lebih fatal daripada gagal build. */
        static void EnsureAssetFolder(string folder)
        {
            try
            {
                if (AssetDatabase.IsValidFolder(folder)) return;
                var normalized = folder.Replace('\\', '/');
                var parent = System.IO.Path.GetDirectoryName(normalized)?.Replace('\\', '/');
                var name = System.IO.Path.GetFileName(normalized);
                if (string.IsNullOrEmpty(parent) || string.IsNullOrEmpty(name)) return;
                if (parent != "Assets" && !AssetDatabase.IsValidFolder(parent))
                {
                    var grand = System.IO.Path.GetDirectoryName(parent)?.Replace('\\', '/');
                    if (!string.IsNullOrEmpty(grand))
                        AssetDatabase.CreateFolder(grand, System.IO.Path.GetFileName(parent));
                }
                if (!AssetDatabase.IsValidFolder(folder))
                    AssetDatabase.CreateFolder(parent, name);
                AssetDatabase.Refresh();
            }
            catch (System.Exception e)
            {
                Debug.LogWarning($"[Aurelia] EnsureAssetFolder({folder}) gagal: {e.Message}");
            }
        }

        /* Langkah 2: bangun GameObject dari VRM lalu simpan sebagai prefab.
           Isinya sama dengan onCompleted di vrmAssetPostprocessor.cs. */
        static void BuildPrefab(UnityPath vrmPath, UnityPath prefabPath,
                                Dictionary<SubAssetKey, UnityEngine.Object> externalObjectMap)
        {
            AssetDatabase.StartAssetEditing();
            try
            {
                var settings = new ImporterContextSettings();

                // Diparse ulang supaya Dispose-nya pasti jalan (sama seperti UniVRM).
                using (var data = new GlbFileParser(vrmPath.FullPath).Parse())
                using (var context = new VRMImporterContext(new VRMData(data),
                                                            externalObjectMap: externalObjectMap,
                                                            settings: settings))
                {
                    var editor = new VRMEditorImporterContext(context, prefabPath);
                    foreach (var textureInfo in context.TextureDescriptorGenerator.Get().GetEnumerable())
                    {
                        TextureImporterConfigurator.Configure(textureInfo, context.TextureFactory.ExternalTextures);
                    }
                    var loaded = context.Load();
                    editor.SaveAsAsset(loaded);
                }
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
            }
        }
    }
}
