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

            /* 4. Active Input Handling: DIPERIKSA saja di sini, tidak pernah
                  diubah. Lihat komentar di ValidateInputHandling. */
            ValidateInputHandling(log);

            /* 5. Karakter. Ini informasi penting, bukan error: file .vrm
                  di-gitignore, jadi build CI tidak akan punya karakter. */
            var charPath = Path.Combine(Stage2SceneBuilder.CharFolder, "AureliaChar.vrm");
            if (!File.Exists(charPath))
                log.Add("PERHATIAN: AureliaChar.vrm tidak ada di checkout ini " +
                        "(file-nya memang di-gitignore). APK memakai kapsul placeholder, " +
                        "BUKAN karakter anime. Lihat TANPA-PC.md untuk cara menyertakannya.");

            Debug.Log("[Aurelia] Preprocess build:\n  - " + string.Join("\n  - ", log));
        }

        /* ============================================================
           Active Input Handling

           activeInputHandler: 0 = Input Manager (lama), 1 = Input System
           Package (baru), 2 = Both.

           KENAPA TIDAK DIUBAH DI SINI -- dulu diubah, dan itu yang
           mematikan build. OnPreprocessBuild jalan SETELAH assembly Editor
           selesai dikompilasi. Mengubah activeInputHandler di titik ini
           membuat assembly PLAYER dikompilasi dengan define
           ENABLE_INPUT_SYSTEM sementara assembly EDITOR tidak, sehingga
           class yang sama punya field berbeda di dua sisi:

               Type '[Unity.RenderPipelines.Core.Runtime]
               UnityEngine.Rendering.DebugActionDesc' has an extra field
               'buttonAction' of type 'UnityEngine.InputSystem.InputAction'
               in the player and thus can't be serialized

           lalu build mati dengan:

               Error building player because script class layout is
               incompatible between the editor and the player.

           (persis yang terjadi di build CI ke-3, run 34924201212.)

           Nilai yang benar hidup di ProjectSettings/ProjectSettings.asset
           yang ikut di-commit, jadi sudah benar SEBELUM Unity mengimpor
           project -- Editor dan Player lalu dikompilasi dengan define yang
           sama. Metode ini hanya memverifikasi, dan gagal lebih awal kalau
           nilainya salah.

           Kenapa 0, bukan 2 ("Both") seperti dugaan sebelumnya:
             - tidak ada satu pun skrip di project ini yang memakai API Input
               System baru; semuanya lewat kelas Input lama (CharacterMotor,
               TouchJoystick, CameraRig);
             - Unity sendiri menolak Both di Android: "Active Input Handling
               is set to Both, this is unsupported on Android and might cause
               issues with input and application performance".
           Jadi 0 = Input Manager lama: cukup, didukung Android, konsisten.
           ============================================================ */
        static void ValidateInputHandling(List<string> log)
        {
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

            switch (prop.intValue)
            {
                case 0:
                    log.Add("Active Input Handling = 0 (Input Manager lama) -- sesuai: " +
                            "semua input game ini memakai kelas Input lama.");
                    break;

                case 1:
                    /* Fatal. Gagal di sini jauh lebih murah daripada gagal di
                       HP: dengan Input System saja, CharacterMotor yang
                       memanggil Input.GetAxis melempar InvalidOperationException
                       di frame pertama -- APK terpasang tapi tak bisa dimainkan,
                       dan lognya tidak gampang dibaca. */
                    throw new BuildFailedException(
                        "[Aurelia] Active Input Handling = 1 (Input System Package saja). " +
                        "CharacterMotor/TouchJoystick/CameraRig memakai kelas Input lama dan " +
                        "akan melempar InvalidOperationException saat runtime. Set " +
                        "'activeInputHandler: 0' di ProjectSettings/ProjectSettings.asset.");

                default:
                    log.Add("PERINGATAN: Active Input Handling = " + prop.intValue +
                            " (Both). Unity menandainya tidak didukung di Android; sebaiknya 0. " +
                            "TIDAK diubah di sini -- ubah di ProjectSettings/ProjectSettings.asset.");
                    break;
            }
        }
    }
}
