// ============================================================
// VrmCharacterImportSettings.cs
//
// Menyetel impor tekstur & mesh karakter VRM supaya muat di Android
// TANPA mengubah file .vrm-nya dan tanpa mengubah tampilannya.
//
// Kenapa lewat AssetPostprocessor, bukan lewat edit file .vrm:
// tekstur di dalam .vrm tetap utuh (jadi master-nya tidak rusak),
// sementara Unity menyimpan versi terkompresi ASTC khusus Android.
// Di Editor kamu tetap melihat tekstur resolusi penuh.
//
// Tidak bergantung UniVRM — hanya pakai API UnityEditor, jadi file ini
// tetap terkompilasi sebelum UniVRM dipasang.
// ============================================================
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace RPG.Editor
{
    public class VrmCharacterImportSettings : AssetPostprocessor
    {
        // Folder tempat karakter tinggal. Semua aset di bawahnya dikenai aturan ini.
        public const string CharacterRoot = "Assets/Art/Characters";

        // ---- knob yang boleh kamu ubah --------------------------------
        // Ukuran maksimum tekstur di build Android. 0 = jangan dikecilkan.
        //   4096 -> 2 tekstur 4096x4096 milik model ini = ~15 MB (ASTC 6x6)
        //   2048 -> ~3,8 MB, sedikit lebih lembut kalau kamera dekat sekali
        // Default 0 supaya tampilan benar-benar tidak berubah.
        const int AndroidMaxTextureSize = 0;

        // ASTC 6x6 = 3,56 bit/piksel. Nyaris tidak bisa dibedakan dari sumbernya
        // untuk tekstur toon bergaris tegas seperti ini. Naik ke 4x4 kalau mau
        // lebih tajam lagi (8 bit/piksel, ~2x memorinya).
        const TextureImporterFormat AndroidFormat = TextureImporterFormat.ASTC_6x6;

        // Mipmap streaming: Unity hanya memuat mip level yang sedang terlihat.
        // Ini penghemat RAM terbesar untuk 43 tekstur.
        const bool UseMipmapStreaming = true;

        // ------------------------------------------------------------
        // Hook tekstur — jalan otomatis saat UniVRM menulis PNG hasil ekstrak
        // ------------------------------------------------------------
        void OnPostprocessTexture(Texture2D texture)
        {
            var path = assetPath;
            if (!IsCharacterAsset(path)) return;

            var ti = (TextureImporter)assetImporter;
            if (ti == null) return;

            var name = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
            bool isNormal = name.Contains("normal") || name.Contains("_nrm");

            ti.textureType       = isNormal ? TextureImporterType.NormalMap : TextureImporterType.Default;
            ti.sRGBTexture       = !isNormal;
            ti.mipmapEnabled     = true;
            ti.alphaIsTransparency = !isNormal;
            ti.streamingMipmaps  = UseMipmapStreaming;
            ti.npotScale         = TextureImporterNPOTScale.None;   // semua tekstur model ini sudah POT
            ti.filterMode        = FilterMode.Bilinear;
            ti.wrapMode          = TextureWrapMode.Repeat;

            // Kompresi khusus Android. Platform lain dibiarkan default.
            var android = new TextureImporterPlatformSettings
            {
                name           = "Android",
                overridden     = true,
                format         = AndroidFormat,
                maxTextureSize = AndroidMaxTextureSize > 0
                                     ? AndroidMaxTextureSize
                                     : Mathf.Max(texture.width, texture.height),
                resizeAlgorithm = TextureResizeAlgorithm.Mitchell,
            };
            ti.SetPlatformTextureSettings(android);

            // Editor juga disetel, supaya yang terlihat di Scene view tidak
            // jauh beda dari yang nanti muncul di HP.
            var editor = new TextureImporterPlatformSettings
            {
                name           = "Standalone",
                overridden     = true,
                format         = TextureImporterFormat.RGBA32,
                maxTextureSize = 4096,
            };
            ti.SetPlatformTextureSettings(editor);
        }

        // ------------------------------------------------------------
        // Laporan biaya — Tools > Aurelia > Laporkan biaya karakter
        // ------------------------------------------------------------
        [MenuItem("Tools/Aurelia/Laporkan biaya karakter")]
        public static void ReportCharacterCost()
        {
            var sb = new StringBuilder();
            sb.AppendLine("=== BIAYA KARAKTER (setelah impor) ===");

            // --- mesh
            var meshes = LoadAssets<Mesh>(CharacterRoot);
            int totalTris = 0, totalVerts = 0, maxSub = 0;
            foreach (var m in meshes)
            {
                for (int s = 0; s < m.subMeshCount; s++)
                    totalTris += (int)(m.GetIndexCount(s) / 3);
                totalVerts += m.vertexCount;
                maxSub = Mathf.Max(maxSub, m.subMeshCount);
            }
            sb.AppendLine($"mesh            : {meshes.Count} aset");
            sb.AppendLine($"  segitiga      : {totalTris:N0}   (target mobile 20rb-40rb per karakter)");
            sb.AppendLine($"  verteks       : {totalVerts:N0}   (target mobile 25rb-50rb)");
            sb.AppendLine($"  submesh maks  : {maxSub}   (= draw call minimum untuk badan)");

            // --- tekstur
            var texs = LoadAssets<Texture2D>(CharacterRoot);
            long srcPx = 0, dstBytes = 0;
            foreach (var t in texs)
            {
                srcPx += (long)t.width * t.height;
                // GetRuntimeMemorySizeLong ada di UnityEngine.Profiling.Profiler,
                // BUKAN di UnityEditor.EditorUtility. (Stub harness dulu salah
                // menaruhnya di EditorUtility, jadi kompilasi lokal hijau sementara
                // Unity asli menolak -- sekarang stub-nya sudah dikoreksi.)
                dstBytes += UnityEngine.Profiling.Profiler.GetRuntimeMemorySizeLong(t);
            }
            sb.AppendLine($"tekstur         : {texs.Count} aset, {srcPx / 1_000_000.0:F1} MP sumber");
            sb.AppendLine($"  memori GPU    : {dstBytes / 1024f / 1024f:F1} MB");
            sb.AppendLine($"  (tanpa ASTC ini akan jadi {srcPx * 4 / 1024f / 1024f:F0} MB)");

            // --- tulang
            var prefabs = AssetDatabase.FindAssets($"t:Prefab", new[] { CharacterRoot })
                                       .Select(AssetDatabase.GUIDToAssetPath)
                                       .Select(AssetDatabase.LoadAssetAtPath<GameObject>)
                                       .Where(p => p != null).ToList();
            foreach (var p in prefabs)
            {
                var all = p.GetComponentsInChildren<Transform>(true);
                var rends = p.GetComponentsInChildren<SkinnedMeshRenderer>(true);
                int maxBones = rends.Length == 0 ? 0 : rends.Max(r => r.bones == null ? 0 : r.bones.Length);
                int blend = rends.Length == 0 ? 0 : rends.Max(r => r.sharedMesh == null ? 0 : r.sharedMesh.blendShapeCount);
                sb.AppendLine($"prefab '{p.name}': {all.Length} transform, {rends.Length} SkinnedMeshRenderer, " +
                              $"max {maxBones} tulang per renderer, {blend} blendshape");
                sb.AppendLine($"  draw call karakter ini ~{rends.Sum(r => r.sharedMesh == null ? 0 : r.sharedMesh.subMeshCount)}");
            }

            sb.AppendLine();
            sb.AppendLine(maxSub > 8
                ? "CATATAN: jumlah material 43 adalah warisan model sumber (lapisan wajah"
                : "CATATAN: jumlah material wajar.");
            sb.AppendLine("terpisah: alis, bulu mata, mata putih, iris, gigi, lidah).");
            sb.AppendLine("Itu TIDAK bisa digabung jadi atlas tanpa merusak wajah, jadi");
            sb.AppendLine("biarkan. URP SRP Batcher sudah memangkas biaya state change-nya.");

            Debug.Log(sb.ToString());
        }

        // ------------------------------------------------------------
        // Paksa setel ulang — Tools > Aurelia > Setel ulang impor tekstur
        // (pakai kalau kamu mengubah konstanta di atas setelah impor)
        // ------------------------------------------------------------
        [MenuItem("Tools/Aurelia/Setel ulang impor tekstur karakter")]
        public static void ReimportCharacterTextures()
        {
            var paths = AssetDatabase.FindAssets("t:Texture2D", new[] { CharacterRoot })
                                     .Select(AssetDatabase.GUIDToAssetPath).ToArray();
            if (paths.Length == 0)
            {
                Debug.LogWarning($"Tidak ada tekstur di {CharacterRoot}. " +
                                 "Impor dulu file .vrm-nya lewat UniVRM.");
                return;
            }
            try
            {
                AssetDatabase.StartAssetEditing();
                foreach (var p in paths) AssetDatabase.ImportAsset(p, ImportAssetOptions.ForceUpdate);
            }
            finally { AssetDatabase.StopAssetEditing(); }
            Debug.Log($"[Aurelia] {paths.Length} tekstur karakter diimpor ulang dengan setelan Android.");
        }

        // ------------------------------------------------------------
        static bool IsCharacterAsset(string path) =>
            path != null && path.Replace('\\', '/').StartsWith(CharacterRoot + "/");

        static List<T> LoadAssets<T>(string folder) where T : Object
        {
            var typeName = typeof(T) == typeof(Texture2D) ? "t:Texture2D" : "t:Mesh";
            return AssetDatabase.FindAssets(typeName, new[] { folder })
                                .Select(AssetDatabase.GUIDToAssetPath)
                                .SelectMany(p => AssetDatabase.LoadAllAssetsAtPath(p).OfType<T>())
                                .ToList();
        }
    }
}
