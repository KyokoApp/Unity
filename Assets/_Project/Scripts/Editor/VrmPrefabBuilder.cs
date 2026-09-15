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

            if (AssetDatabase.LoadAssetAtPath<GameObject>(PrefabFile) != null)
            {
                log.Add("Prefab karakter sudah ada: " + PrefabFile);
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
