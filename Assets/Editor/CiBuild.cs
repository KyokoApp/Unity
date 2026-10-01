using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using UnityEditor;
using UnityEditor.Android;
using UnityEditor.Build.Reporting;
using UnityEngine;

/// <summary>
/// Dipanggil GitHub Actions (game-ci) lewat -executeMethod CiBuild.BuildAll:
///  1. Build paket konten (tuning.json + asset bundle bila ada) -> build/content/
///  2. Tulis manifest.json (versi + SHA-256) untuk updater in-game.
///  3. Build APK Android -> build/Android/Arpg.apk
/// </summary>
public static class CiBuild
{
    const string ApkName = "Arpg.apk";
    const string ApkReleaseBaseUrl = "https://github.com/KyokoApp/Unity/releases/download/apk-latest/";

    public static void BuildAll()
    {
        string root = Directory.GetParent(Application.dataPath).FullName;

        // Nama tampilan, ikon Android, dan signing release tetap stabil.
        PlayerSettings.productName = "Arpg";
        PlayerSettings.Android.forceInternetPermission = true;
        PlayerSettings.Android.useCustomKeystore = true;
        ApplyAndroidSigningArguments(root);
        ConfigureAndroidIcons();

        // ---- 0) clip lokomosi UAL1 (walk/jog/sprint) -> Resources/UAL1Loco ----
        ExtractLocomotion.Run();

        // ---- 0b) world nature glTF (Kenney CC0) -> Mesh/Material/Prefab ----
        ImportWorld.Run();
        ConfigureAssetBundles();

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
        string apkAssetName = "Arpg-" + appVersion + ".apk";
        string apkUrl = ApkReleaseBaseUrl + apkAssetName;
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
                string sha = Sha256(p);
                string versionedFile = n + "-" + sha + ".bundle";
                string versionedPath = Path.Combine(contentDir, versionedFile);
                File.Copy(p, versionedPath, true);
                var fi = new FileInfo(versionedPath);
                packsJson.Add("    {\"id\": \"" + n + "\", \"file\": \"" + versionedFile + "\", \"sha256\": \""
                    + sha + "\", \"size\": " + fi.Length + "}");
            }
        }

        string tuningSource = Path.Combine(root, "Assets/Resources/Content/tuning.json");
        string tuningSha = Sha256(tuningSource);
        string tuningFile = "tuning-" + tuningSha + ".json";
        string tuningPath = Path.Combine(contentDir, tuningFile);
        File.Copy(tuningSource, tuningPath, true);
        var tuningInfo = new FileInfo(tuningPath);

        // ---- 2) APK ----
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
        string apkPath = opts.locationPathName;
        var apkInfo = new FileInfo(apkPath);
        if (!apkInfo.Exists)
        {
            Debug.LogError("[CiBuild] APK tidak ditemukan setelah build: " + apkPath);
            EditorApplication.Exit(1);
            return;
        }

        // APK hash/ukuran ikut manifest konten supaya tombol update di game
        // hanya memasang file resmi yang benar-benar cocok dengan release ini.
        var manifest = new StringBuilder();
        manifest.AppendLine("{");
        manifest.AppendLine("  \"contentVersion\": " + run + ",");
        manifest.AppendLine("  \"appVersion\": \"" + appVersion + "\",");
        manifest.AppendLine("  \"apkUrl\": \"" + apkUrl + "\",");
        manifest.AppendLine("  \"apkSha256\": \"" + Sha256(apkPath) + "\",");
        manifest.AppendLine("  \"apkSize\": " + apkInfo.Length + ",");
        manifest.AppendLine("  \"tuningFile\": \"" + tuningFile + "\",");
        manifest.AppendLine("  \"tuningSha256\": \"" + tuningSha + "\",");
        manifest.AppendLine("  \"tuningSize\": " + tuningInfo.Length + ",");
        manifest.AppendLine("  \"packs\": [");
        manifest.AppendLine(string.Join(",\n", packsJson.ToArray()));
        manifest.AppendLine("  ]");
        manifest.AppendLine("}");
        File.WriteAllText(Path.Combine(contentDir, "manifest.json"), manifest.ToString());

        Debug.Log("[CiBuild] APK sukses: " + apkPath
            + " (" + (report.summary.totalSize / (1024 * 1024)) + " MB)");
        Debug.Log("[CiBuild] Konten + manifest siap: " + contentDir);
    }

    static void ApplyAndroidSigningArguments(string projectRoot)
    {
        // BuildMethod kustom melewati AndroidSettings.Apply milik builder default;
        // GameCI tetap mengirim flag ke Editor, jadi terapkan sendiri sebelum BuildPlayer.
        string[] args = Environment.GetCommandLineArgs();
        string keystore = PlayerSettings.Android.keystoreName;
        string keystorePass = PlayerSettings.Android.keystorePass;
        string aliasName = PlayerSettings.Android.keyaliasName;
        string aliasPass = PlayerSettings.Android.keyaliasPass;
        SetIfPresent(ref keystore, FindArgument(args, "-androidKeystoreName", "--androidKeystoreName"));
        SetIfPresent(ref keystorePass, FindArgument(args, "-androidKeystorePass", "-androidKeystorePassword", "--androidKeystorePassword"));
        SetIfPresent(ref aliasName, FindArgument(args, "-androidKeyaliasName", "-androidKeyAlias", "--androidKeyAlias"));
        SetIfPresent(ref aliasPass, FindArgument(args, "-androidKeyaliasPass", "-androidKeyAliasPassword", "--androidKeyAliasPassword"));
        PlayerSettings.Android.keystoreName = keystore;
        PlayerSettings.Android.keystorePass = keystorePass;
        PlayerSettings.Android.keyaliasName = aliasName;
        PlayerSettings.Android.keyaliasPass = aliasPass;

        if (string.IsNullOrEmpty(keystore)
            || string.IsNullOrEmpty(PlayerSettings.Android.keystorePass)
            || string.IsNullOrEmpty(PlayerSettings.Android.keyaliasName)
            || string.IsNullOrEmpty(PlayerSettings.Android.keyaliasPass))
            throw new InvalidOperationException("Signing release Android tidak tersedia. Isi empat secrets ANDROID_KEYSTORE_* di GitHub Actions.");

        string fullPath = Path.IsPathRooted(keystore) ? keystore : Path.Combine(projectRoot, keystore);
        if (!File.Exists(fullPath))
            throw new FileNotFoundException("Keystore signing Android tidak ditemukan di workspace.", fullPath);
        PlayerSettings.Android.keystoreName = fullPath;
    }

    static void SetIfPresent(ref string setting, string value)
    {
        if (!string.IsNullOrEmpty(value)) setting = value;
    }

    static string FindArgument(string[] args, params string[] names)
    {
        for (int i = 0; i < args.Length; i++)
        {
            for (int n = 0; n < names.Length; n++)
            {
                if (args[i] == names[n] && i + 1 < args.Length) return args[i + 1];
                string prefix = names[n] + "=";
                if (args[i].StartsWith(prefix, StringComparison.Ordinal)) return args[i].Substring(prefix.Length);
            }
        }
        return null;
    }

    static void ConfigureAndroidIcons()
    {
        var icon = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Branding/ArpgIcon.png");
        if (icon == null) throw new InvalidOperationException("Ikon Android hilang: Assets/Branding/ArpgIcon.png");

        SetSingleLayerIcons(AndroidPlatformIconKind.Legacy, icon);
        SetSingleLayerIcons(AndroidPlatformIconKind.Round, icon);

        // Unity adaptive icon memiliki dua layer. Ikon CC0 dipakai sebagai kedua layer,
        // sehingga hasil tetap konsisten dan ter-mask pada launcher Android modern.
        var adaptive = PlayerSettings.GetPlatformIcons(BuildTargetGroup.Android, AndroidPlatformIconKind.Adaptive);
        for (int i = 0; i < adaptive.Length; i++)
            adaptive[i].SetTextures(new[] { icon, icon });
        PlayerSettings.SetPlatformIcons(BuildTargetGroup.Android, AndroidPlatformIconKind.Adaptive, adaptive);
    }

    static void SetSingleLayerIcons(PlatformIconKind kind, Texture2D texture)
    {
        var icons = PlayerSettings.GetPlatformIcons(BuildTargetGroup.Android, kind);
        for (int i = 0; i < icons.Length; i++) icons[i].SetTexture(texture);
        PlayerSettings.SetPlatformIcons(BuildTargetGroup.Android, kind, icons);
    }

    static void ConfigureAssetBundles()
    {
        TagAssetBundle("Assets/Resources/UAL2/UAL2_Standard.fbx", "arpg-character");
        TagAssetBundle("Assets/Resources/UAL2/Mannequin_F.fbx", "arpg-character");
        const string locoRoot = "Assets/Resources/UAL1Loco";
        if (Directory.Exists(locoRoot))
        {
            string[] locoGuids = AssetDatabase.FindAssets("t:AnimationClip", new[] { locoRoot });
            foreach (string guid in locoGuids)
                TagAssetBundle(AssetDatabase.GUIDToAssetPath(guid), "arpg-character");
        }

        const string worldRoot = "Assets/Resources/WorldGen";
        if (Directory.Exists(worldRoot))
        {
            string[] guids = AssetDatabase.FindAssets(string.Empty, new[] { worldRoot });
            foreach (string guid in guids)
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                string extension = Path.GetExtension(path).ToLowerInvariant();
                if (extension == ".prefab" || extension == ".mat" || extension == ".asset" || extension == ".png")
                    TagAssetBundle(path, "arpg-world");
            }
        }

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[CiBuild] AssetBundle tags: arpg-character + arpg-world (fallback Resources tetap disertakan di APK).");
    }

    static void TagAssetBundle(string path, string bundleName)
    {
        var importer = AssetImporter.GetAtPath(path);
        if (importer == null) return;
        if (importer.assetBundleName == bundleName && string.IsNullOrEmpty(importer.assetBundleVariant)) return;
        importer.assetBundleName = bundleName;
        importer.assetBundleVariant = string.Empty;
        AssetDatabase.WriteImportSettingsIfDirty(path);
    }

    /// <summary>Dipanggil job sim-test CI: siapkan aset generated sebelum tes PlayMode.</summary>
    public static void PrepSim()
    {
        ExtractLocomotion.Run();
        ImportWorld.Run();
        Debug.Log("[CiBuild] PrepSim selesai: UAL1Loco + WorldGen siap untuk tes PlayMode.");
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
