using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

/// <summary>
/// Dipanggil GitHub Actions (game-ci) lewat -executeMethod CiBuild.BuildAll:
///  1. Build paket konten (tuning.json + asset bundle bila ada) -> build/content/
///  2. Tulis manifest.json (versi + SHA-256) untuk updater in-game.
///  3. Build APK Android -> build/Android/UAL2Playground.apk
/// </summary>
public static class CiBuild
{
    const string ApkName = "UAL2Playground.apk";
    const string ApkUrl = "https://github.com/KyokoApp/Unity/releases/download/apk-latest/" + ApkName;

    public static void BuildAll()
    {
        string root = Directory.GetParent(Application.dataPath).FullName;

        // ---- 0) clip lokomosi UAL1 (walk/jog/sprint) -> Resources/UAL1Loco ----
        ExtractLocomotion.Run();

        // ---- versi dari nomor run CI ----
        // unity-builder TIDAK meneruskan GITHUB_RUN_NUMBER ke dalam container,
        // jadi workflow apk-release mengirimnya lewat input customParameters:
        // "-runNumber <n>" (build.sh meneruskannya sebagai argumen CLI editor).
        // Fallback: env GITHUB_RUN_NUMBER (build manual/lokal) lalu 0.
        int run = 0;
        string[] cliArgs = Environment.GetCommandLineArgs();
        for (int i = 0; i < cliArgs.Length - 1; i++)
        {
            int parsedRun;
            if (cliArgs[i] == "-runNumber" && int.TryParse(cliArgs[i + 1], out parsedRun) && parsedRun > 0)
            {
                run = parsedRun;
            }
        }
        if (run <= 0)
        {
            int.TryParse(Environment.GetEnvironmentVariable("GITHUB_RUN_NUMBER") ?? "0", out run);
        }
        if (run < 0) run = 0;
        string appVersion = "1.0." + run;
        PlayerSettings.bundleVersion = appVersion;
        PlayerSettings.Android.bundleVersionCode = Mathf.Max(1, run);
        Debug.Log("[CiBuild] appVersion=" + appVersion + " contentVersion=" + run);

        // ---- 1) paket konten ----
        string contentDir = Path.Combine(root, "build/content");
        Directory.CreateDirectory(contentDir);

        var packsJson = new List<string>();
        string[] bundleNames = AssetDatabase.GetAllAssetBundleNames();
        if (bundleNames.Length > 0)
        {
            BuildPipeline.BuildAssetBundles(contentDir,
                BuildAssetBundleOptions.ChunkBasedCompression, BuildTarget.Android);
            foreach (string n in bundleNames)
            {
                string p = Path.Combine(contentDir, n);
                if (!File.Exists(p)) continue;
                var fi = new FileInfo(p);
                packsJson.Add("    {\"id\": \"" + n + "\", \"file\": \"" + n + "\", \"sha256\": \""
                    + Sha256(p) + "\", \"size\": " + fi.Length + "}");
            }
        }

        File.Copy(Path.Combine(root, "Assets/Resources/Content/tuning.json"),
            Path.Combine(contentDir, "tuning.json"), true);

        // ---- 2) manifest ----
        var sb = new StringBuilder();
        sb.AppendLine("{");
        sb.AppendLine("  \"contentVersion\": " + run + ",");
        sb.AppendLine("  \"appVersion\": \"" + appVersion + "\",");
        sb.AppendLine("  \"apkUrl\": \"" + ApkUrl + "\",");
        sb.AppendLine("  \"tuningFile\": \"tuning.json\",");
        sb.AppendLine("  \"packs\": [");
        sb.AppendLine(string.Join(",\n", packsJson.ToArray()));
        sb.AppendLine("  ]");
        sb.AppendLine("}");
        File.WriteAllText(Path.Combine(contentDir, "manifest.json"), sb.ToString());
        Debug.Log("[CiBuild] Konten siap: " + contentDir);

        // ---- 3) APK ----
        string apkDir = Path.Combine(root, "build/Android");
        Directory.CreateDirectory(apkDir);
        EditorUserBuildSettings.buildAppBundle = false;

        var scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray();
        var opts = new BuildPlayerOptions
        {
            scenes = scenes,
            locationPathName = Path.Combine(apkDir, ApkName),
            target = BuildTarget.Android,
            options = BuildOptions.None
        };

        BuildReport report = BuildPipeline.BuildPlayer(opts);
        if (report.summary.result != BuildResult.Succeeded)
        {
            Debug.LogError("[CiBuild] Build APK GAGAL: " + report.summary.result);
            EditorApplication.Exit(1);
            return;
        }
        Debug.Log("[CiBuild] APK sukses: " + opts.locationPathName
            + " (" + (report.summary.totalSize / (1024 * 1024)) + " MB)");
    }

    static string Sha256(string path)
    {
        using (var sha = SHA256.Create())
        using (var fs = File.OpenRead(path))
        {
            var hash = sha.ComputeHash(fs);
            var sb = new StringBuilder(hash.Length * 2);
            foreach (byte b in hash) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
}
