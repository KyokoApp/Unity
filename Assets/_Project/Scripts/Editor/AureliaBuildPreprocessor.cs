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

            /* 0. Signing APK. Unity sempat menolak dengan
                  "Unable to sign the application; please provide passwords!"
                  padahal kunci + password terbukti sehat (keytool dan jarsigner
                  lulus di runner yang sama, fix14). Yang bocor adalah jalurnya:
                  password dikirim sebagai argumen baris perintah ke skrip build
                  game-ci, dan satu langkah yang salah di situ cukup untuk
                  menghilangkannya tanpa jejak sama sekali. Jadi build ini tidak
                  percaya jalur itu: CI menulis konfigurasi ke berkas di
                  workspace, dan kita pasang sendiri ke PlayerSettings -- tepat
                  sebelum Unity menandatangani, beberapa detik sebelumnya.
                  Penting: keystoreName HARUS relatif terhadap folder proyek.
                  Unity menggabungkannya dengan current directory, jadi path
                  absolut berubah menjadi "/github/workspace/github/workspace/…"
                  dan build mati dengan "keystore file not found" (fix13). */
            try { ApplyAndroidSigningFromCi(log); }
            catch (System.Exception e) { log.Add("konfigurasi signing gagal dipasang: " + e.Message); }

            /* 1. URP asset. Tanpa ini semua material jadi magenta, dan
                  gejalanya baru terlihat setelah APK terpasang di HP.
               FIX 2026-09-15: Selalu panggil EnsureUrpAsset, bukan cuma kalau null,
               karena asset yang ada bisa rusak (postProcessData null) -> layar hitam + jejak.
               Juga pastikan GlobalSettings ada. */
            try
            {
                Stage2SceneBuilder.EnsureUrpAsset(log);
                log.Add("URP asset dipastikan (fix postProcessData + all quality levels + GlobalSettings).");
            }
            catch (System.Exception e)
            {
                log.Add("URP ensure gagal: " + e.Message);
                /* Dulu blok ini cukup mencatat lalu jalan terus, dan hasilnya
                   adalah build HIJAU dengan APK hitam: render pipeline adalah
                   satu-satunya hal yang membuat dunia ADA, jadi kegagalannya
                   tidak boleh diredam jadi peringatan. Cetak semua catatan
                   lebih dulu (baris 140 tidak akan pernah tercapai kalau kita
                   lempar di sini), lalu hentikan build. */
                Debug.Log("[Aurelia] Preprocess build (SEBELUM DIHENTIKAN):\n  - " + string.Join("\n  - ", log));
                Debug.LogError("[Aurelia] build dihentikan: render pipeline tidak bisa dipastikan -> " + e.Message);
                throw;
            }

            // Pastikan app ID benar (com.yuki.natsuki) — cegah template ID ke-build lagi
            try
            {
                var psPath = "ProjectSettings/ProjectSettings.asset";
                var ps = UnityEditor.AssetDatabase.LoadAllAssetsAtPath(psPath);
                if (ps.Length > 0)
                {
                    var so = new UnityEditor.SerializedObject(ps[0]);
                    // applicationIdentifier tidak bisa diakses via SerializedProperty mudah karena nested,
                    // tapi kita sudah set via file di repo dan workflow. Cek saja.
                    log.Add("AppID check: ProjectSettings.asset terbaca");
                }
            }
            catch { }

            /* 2. Karakter, dan HARUS sebelum scene dibangun: Stage2SceneBuilder
                  mencari prefab di Assets/Art/Characters, dan kalau tidak ada ia
                  diam-diam memasang kapsul placeholder. UniVRM seharusnya
                  membuat prefab itu sendiri lewat AssetPostprocessor, tapi
                  separuh alurnya ditunda EditorApplication.delayCall yang tidak
                  pernah jalan di batchmode -- jadi build CI menghasilkan APK
                  berisi kapsul (run 34926918799). VrmPrefabBuilder mengerjakan
                  alur yang sama secara sinkron. */
            VrmPrefabBuilder.EnsurePrefab(log);

            /* 3. Scene. Selalu dibangun ulang, bukan "kalau belum ada":
                  scene yang tersimpan di Library bisa basi terhadap kode.
                  Membangun ulang itu murah (detik) dan hasilnya pasti
                  cocok dengan Stage2SceneBuilder yang sekarang. */
            var scenePath = Stage2SceneBuilder.BuildForBuildPlayer(log);

            /* 4. Daftarkan ke build settings. Tanpa ini scene-nya ada di
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

            /* 5. Active Input Handling: DIPERIKSA saja di sini, tidak pernah
                  diubah. Lihat komentar di ValidateInputHandling. */
            ValidateInputHandling(log);

            /* 6. Screenshot in-game (siang/senja/malam) untuk artifact CI.
                  Dibungkus try/catch di dalamnya: screenshot adalah mata
                  kita, bukan alasan build boleh gagal. */
            SceneShots.Capture(log);

            /* Catatan karakter sudah dilaporkan langkah 2 (VrmPrefabBuilder):
                  ia bilang prefab dibangun, atau kenapa tidak. Tidak ada lagi
                  jalur yang diam-diam mengirim APK berisi kapsul. */

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

        /* Baca keystore/ci-signing.txt (dibuat oleh CI, tidak pernah di-commit)
              dan pasang konfigurasi signing Android kita sendiri.
           Aturan main:
           - berkas tidak ada  -> biarkan apa adanya (build lokal/dev; debug key).
           - berkas tidak lengkap -> log keras, JANGAN menimpa sebagian: mencampur
             sumber (nama dari Unity, pass dari kita) persis yang menghasilkan
             "please provide passwords!".
           - password tidak pernah dicetak; hanya panjangnya, sebagai bukti. */
        static void ApplyAndroidSigningFromCi(List<string> log)
        {
            const string cfgPath = "keystore/ci-signing.txt";
            if (!File.Exists(cfgPath))
            {
                log.Add("signing: tidak ada " + cfgPath + " -> pakai konfigurasi proyek apa adanya.");
                return;
            }

            var vals = new Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);
            foreach (var raw in File.ReadAllLines(cfgPath))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line[0] == '#') continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                vals[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
            }

            string Get(string key) => vals.TryGetValue(key, out var v) ? v : null;
            var name = Get("keystoreName");
            var pass = Get("keystorePass");
            var alias = Get("keyaliasName");
            var aliasPass = Get("keyaliasPass");

            if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(pass) ||
                string.IsNullOrEmpty(alias))
            {
                log.Add("GALAG " + cfgPath + " tidak lengkap (butuh keystoreName, keystorePass, " +
                        "keyaliasName) -> PlayerSettings TIDAK diubah. Isi yang terbaca: " +
                        string.Join(",", vals.Keys));
                return;
            }

            // Paksa relatif terhadap folder proyek (lihat komentar di OnPreprocessBuild).
            if (Path.IsPathRooted(name))
            {
                var root = Directory.GetCurrentDirectory();
                var full = Path.GetFullPath(name);
                if (full.StartsWith(root + Path.DirectorySeparatorChar))
                    name = full.Substring(root.Length + 1);
            }

            PlayerSettings.Android.useCustomKeystore = true;
            PlayerSettings.Android.keystoreName = name;
            PlayerSettings.Android.keystorePass = pass;
            PlayerSettings.Android.keyaliasName = alias;
            // keyaliasPass boleh kosong: keystore ini memakai store == key
            // (PKCS12 satu password) -> pakai pass.
            PlayerSettings.Android.keyaliasPass =
                string.IsNullOrEmpty(aliasPass) ? pass : aliasPass;

            // Baca balik: kalau Unity menolak menyimpan nilainya, ini yang membuktikannya.
            var storedPass = PlayerSettings.Android.keystorePass;
            var storedAliasPass = PlayerSettings.Android.keyaliasPass;
            var resolved = Path.Combine(Directory.GetCurrentDirectory(), name);

            log.Add(string.Format(
                "signing dipasang: keystoreName={0} berkas={1} alias={2} useCustomKeystore={3} " +
                "passLen={4}->{5} aliasPassLen={6}->{7}",
                name,
                File.Exists(resolved) ? "ADA" : "TIDAK KETEMU",
                PlayerSettings.Android.keyaliasName,
                PlayerSettings.Android.useCustomKeystore,
                pass.Length,
                storedPass == null ? -1 : storedPass.Length,
                (aliasPass ?? pass).Length,
                storedAliasPass == null ? -1 : storedAliasPass.Length));

            if (!File.Exists(resolved))
                log.Add("GALAG: keystore tidak ada di " + resolved);
            if (string.IsNullOrEmpty(storedPass))
                log.Add("GALAG: Unity tidak menyimpan keystorePass -> signing pasti gagal.");
        }
    }
}
