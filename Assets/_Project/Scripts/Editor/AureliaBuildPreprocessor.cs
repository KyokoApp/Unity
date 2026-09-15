// ============================================================
// AureliaBuildPreprocessor.cs
//
// Jalan OTOMATIS sebelum setiap build player (termasuk build dari
// GitHub Actions lewat game-ci/unity-builder).
//
// KENAPA FILE INI ADA
// -------------------
// Scene tidak ikut di repo -- sengaja, karena scene yang memuat
// instance prefab VRM akan menyeret model berlisensi
// Redistribution_Prohibited ke dalam git (lihat
// Assets/Art/Characters/LISENSI.md). Konsekuensinya: checkout CI
// tidak punya scene SAMA SEKALI, dan EditorBuildSettings.scenes
// kosong. Build APK tanpa file ini akan menghasilkan APK kosong
// atau gagal, tanpa pesan yang jelas.
//
// Jadi build-nya yang membangun scene-nya sendiri, tepat sebelum
// dikemas. Metode yang dipanggil sama persis dengan yang dipanggil
// menu Tools > Aurelia, jadi hasilnya identik antara build lokal
// dan build CI -- tidak ada jalur khusus CI yang tidak pernah diuji.
//
// Ini IPreprocessBuildWithReport, bukan [MenuItem] atau
// [InitializeOnLoad], karena ia memang hanya perlu jalan saat ada
// build -- tidak tiap kali Editor dibuka.
// ============================================================
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace RPG.Editor
{
    public class AureliaBuildPreprocessor : IPreprocessBuildWithReport
    {
        // Jalankan sebelum preprocessor lain yang mungkin memeriksa scene.
        public int callbackOrder => -100;

        public void OnPreprocessBuild(BuildReport report)
        {
            var log = new List<string>();

            /* 1. URP asset. Tanpa ini semua material jadi magenta, dan
                  gejalanya baru terlihat setelah APK terpasang di HP. */
            var hadUrp = UnityEngine.Rendering.GraphicsSettings.defaultRenderPipeline != null;
            if (!hadUrp)
            {
                Stage2SceneBuilder.EnsureUrpAsset();
                log.Add("URP asset dibuat dan dipasang (sebelumnya belum ada).");
            }

            /* 2. Scene. Selalu dibangun ulang, bukan "kalau belum ada":
                  scene yang tersimpan di Library bisa basi terhadap kode.
                  Membangun ulang itu murah (detik) dan hasilnya pasti
                  cocok dengan Stage2SceneBuilder yang sekarang. */
            var scenePath = Stage2SceneBuilder.BuildForBuildPlayer(log);

            /* 3. Daftarkan ke build settings. Tanpa ini scene-nya ada di
                  disk tapi tidak ikut dikemas. */
            if (!string.IsNullOrEmpty(scenePath) && File.Exists(scenePath))
            {
                EditorBuildSettings.scenes = new[]
                {
                    new EditorBuildSettingsScene(scenePath, true)
                };
                log.Add($"Scene terdaftar di build settings: {scenePath}");
            }
            else
            {
                /* Jangan diam-diam menghasilkan APK kosong. Lebih baik
                   build gagal dengan pesan yang bisa dibaca. */
                throw new BuildFailedException(
                    "[Aurelia] Scene gagal dibangun di " + scenePath +
                    ". APK tidak akan punya isi. Lihat log di atas.");
            }

            /* 4. Active Input Handling harus "Both" atau CharacterMotor
                  melempar InvalidOperationException saat runtime -- di HP,
                  setelah build selesai, tanpa cara mudah melihat lognya. */
            WarnIfInputHandlingSalah(log);

            /* 5. Karakter. Ini informasi penting, bukan error: file .vrm
                  di-gitignore, jadi build CI tidak akan punya karakter. */
            var charPath = Path.Combine(Stage2SceneBuilder.CharFolder, "AureliaChar.vrm");
            if (!File.Exists(charPath))
                log.Add("PERHATIAN: AureliaChar.vrm tidak ada di checkout ini " +
                        "(file-nya memang di-gitignore). APK memakai kapsul placeholder, " +
                        "BUKAN karakter anime. Lihat TANPA-PC.md untuk cara menyertakannya.");

            Debug.Log("[Aurelia] Preprocess build:\n  - " + string.Join("\n  - ", log));
        }

        static void WarnIfInputHandlingSalah(List<string> log)
        {
            /* activeInputHandler: 0 = Input Manager (lama), 1 = Input System
               Package (baru), 2 = Both. Dibaca dari ProjectSettings karena
               tidak ada API publik yang bisa di-set dari skrip. */
            const string key = "activeInputHandler";
            var serialized = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            if (serialized.Length == 0)
            {
                log.Add("ProjectSettings.asset tidak terbaca; Active Input Handling tidak bisa diverifikasi.");
                return;
            }
            var so = new SerializedObject(serialized[0]);
            var prop = so.FindProperty(key);
            if (prop == null)
            {
                log.Add("Properti 'activeInputHandler' tidak ditemukan; dilewati.");
                return;
            }
            if (prop.intValue != 2)
            {
                log.Add($"PERINGATAN: Active Input Handling = {prop.intValue} (harus 2 = Both). " +
                        "CharacterMotor memakai kelas Input lama dan akan melempar " +
                        "InvalidOperationException saat runtime.");
                /* Diubah otomatis, bukan cuma diperingatkan: build CI tidak
                   ada orangnya untuk membaca peringatan. */
                prop.intValue = 2;
                so.ApplyModifiedPropertiesWithoutUndo();
                log.Add("  -> sudah diubah ke Both secara otomatis.");
            }
        }
    }
}
