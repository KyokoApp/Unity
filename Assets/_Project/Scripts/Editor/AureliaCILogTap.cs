// ============================================================
// AureliaCILogTap.cs
//
// KENAPA FILE INI ADA
// -------------------
// Enam build CI berturut-turut mati dengan satu-satunya pesan:
//
//     Build failed with exit code 1
//
// tanpa sebab apa pun. Alasannya mekanis, dan sudah dipastikan dari sumber
// game-ci (cli: dist/platforms/ubuntu/steps/build.sh): Unity dijalanakan dengan
//
//     unity-editor -logfile /dev/stdout ... <customParameters>
//
// jadi SELURUH output editor hanya pergi ke stdout langkah Actions. Unity tidak
// menulis Editor.log ke disk kalau -logfile dipakai, dan mencoba menimpanya
// lewat customParameters terbukti TIDAK berhasil -- yang menang yang pertama
// (dicoba di run v0.2.0-cel-fix7 dan fix8: Logs/AureliaEditor.log tidak pernah
// dibuat). Log mentah Actions sendiri tidak selalu bisa diambil alat otomatis
// (diarahkan ke blob storage).
//
// Jalan keluar yang tidak bergantung pada siapa pun: tempel telinga sendiri ke
// logger Unity. Application.logMessageReceivedThreaded menangkap SETIAP pesan
// yang lewat Debug.Log / LogError / LogException -- termasuk "Shader error",
// pesan IL2CPP, dan output Gradle yang dilempar BuildPlayer -- dan ditulis ke
// Logs/AureliaUnity.log di akar project. Folder itu ada di dalam mount
// container (dockerWorkspacePath=/github/workspace), jadi berkasnya sampai ke
// host, tempat langkah "Kumpulkan bukti kegagalan" mengubah baris-barisnya
// menjadi ANOTASI.
//
// Yang TIDAK ditangkap: pesan yang terbit SEBELUM domain script Editor kami
// dimuat (mis. "Scripts have compiler errors"). Untuk itu ada jaring kedua di
// workflow: ada/tidaknya Library/ScriptAssemblies/RPG.*.dll.
//
// Kelas ini tidak boleh ikut ke dalam build player; [InitializeOnLoad] saja
// sudah Editor-only, tapi seluruh berkas dibungkus #if UNITY_EDITOR supaya
// tidak pernah masuk IL2CPP.
// ============================================================
#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace RPG.Editor
{
    public static class AureliaCILogTap
    {
        internal static StreamWriter Writer;
        internal static long Bytes;
        internal static readonly object Gate = new object();
        const long MaxBytes = 24L * 1024 * 1024;   // cukup untuk satu build lengkap

        internal static void Write(string level, string message, string stack = null)
        {
            var w = Writer;
            if (w == null) return;
            lock (Gate)
            {
                if (Bytes > MaxBytes) return;
                try
                {
                    var line = $"[{DateTime.Now:HH:mm:ss}] {level}: {message}";
                    if (!string.IsNullOrEmpty(stack) && level != "Log") line += "\n" + stack;
                    w.WriteLine(line);
                    Bytes += line.Length + 1;
                }
                catch
                {
                    // disk penuh / stream ditutup saat shutdown: abaikan.
                    // Tap log tidak boleh menjadi penyebab build gagal.
                }
            }
        }

        internal static void Close()
        {
            lock (Gate)
            {
                try { Writer?.Flush(); Writer?.Dispose(); } catch { }
                Writer = null;
            }
        }
    }

    /* [InitializeOnLoad] = static ctor dijalankan setiap kali domain script Editor
       dimuat, termasuk di "unity-editor -batchmode -quit -executeMethod ...".
       Kelas ini harus top-level dan Editor-only: itu titik paling awal yang masih
       milik kita. */
    [InitializeOnLoad]
    public static class AureliaCILogTapInstaller
    {
        static AureliaCILogTapInstaller()
        {
            try
            {
                var root = Directory.GetParent(Application.dataPath)?.FullName
                           ?? Directory.GetCurrentDirectory();
                var dir = Path.Combine(root, "Logs");
                Directory.CreateDirectory(dir);
                var file = Path.Combine(dir, "AureliaUnity.log");

                // Append, bukan Create: domain reload (impor paket, perubahan skrip)
                // mengulang InitializeOnLoad, dan log dari fase sebelumnya jangan hilang.
                AureliaCILogTap.Writer = new StreamWriter(file, true) { AutoFlush = true };
                AureliaCILogTap.Bytes = new FileInfo(file).Length;

                Application.logMessageReceivedThreaded += OnLogMessage;
                AppDomain.CurrentDomain.ProcessExit += (s, e) => AureliaCILogTap.Close();
                EditorApplication.quitting += AureliaCILogTap.Close;

                AureliaCILogTap.Write("INFO",
                    $"[Aurelia] LogTap terpasang: {file} " +
                    $"(batch={Application.isBatchMode}, unity={Application.unityVersion}, " +
                    $"target={EditorUserBuildSettings.activeBuildTarget})");
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[Aurelia] LogTap tidak terpasang: {e.GetType().Name}: {e.Message}");
                AureliaCILogTap.Writer = null;
            }
        }

        static void OnLogMessage(string condition, string stackTrace, LogType type)
        {
            if (AureliaCILogTap.Writer == null) return;
            // Log startup kita sendiri jangan ditulis dua kali (hook terpasang sebelum Write).
            if (type == LogType.Log && condition != null &&
                condition.StartsWith("[Aurelia] LogTap terpasang")) return;
            AureliaCILogTap.Write(type.ToString(), condition, stackTrace);
        }
    }
}
#endif
