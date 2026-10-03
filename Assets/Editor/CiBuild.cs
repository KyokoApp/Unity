using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

/// <summary>Build APK Android untuk game PoolRooms mandiri.</summary>
public static class CiBuild
{
    const string ApkName = "PoolRooms.apk";

    public static void BuildAll()
    {
        string root = Directory.GetParent(Application.dataPath).FullName;
        RemoveUnusedGeneratedResources(root);

        int run = ReadRunNumber();
        string appVersion = "2.0." + run;
        PlayerSettings.bundleVersion = appVersion;
        PlayerSettings.Android.bundleVersionCode = Mathf.Max(1, run);
        Debug.Log("[CiBuild] PoolRooms appVersion=" + appVersion);

        string apkDir = Path.Combine(root, "build/Android");
        Directory.CreateDirectory(apkDir);
        EditorUserBuildSettings.buildAppBundle = false;

        string[] scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray();
        var options = new BuildPlayerOptions
        {
            scenes = scenes,
            locationPathName = Path.Combine(apkDir, ApkName),
            target = BuildTarget.Android,
            options = BuildOptions.None
        };

        BuildReport report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
        {
            Debug.LogError("[CiBuild] Build APK gagal: " + report.summary.result);
            EditorApplication.Exit(1);
            return;
        }

        Debug.Log("[CiBuild] APK siap: " + options.locationPathName
            + " (" + (report.summary.totalSize / (1024 * 1024)) + " MB)");
    }

    /// <summary>Jaga agar cache CI lama tidak memasukkan asset world/avatar ke APK ROOM.</summary>
    public static void PrepSim()
    {
        string root = Directory.GetParent(Application.dataPath).FullName;
        RemoveUnusedGeneratedResources(root);
        Debug.Log("[CiBuild] PoolRooms siap untuk PlayMode tests; environment dibangun saat runtime.");
    }

    static int ReadRunNumber()
    {
        int run = 0;
        string[] args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
        {
            int parsed;
            if (args[i] == "-runNumber" && int.TryParse(args[i + 1], out parsed) && parsed > 0)
                run = parsed;
        }
        if (run <= 0)
            int.TryParse(Environment.GetEnvironmentVariable("GITHUB_RUN_NUMBER") ?? "0", out run);
        return Mathf.Max(0, run);
    }

    static void RemoveUnusedGeneratedResources(string root)
    {
        string[] legacyFolders =
        {
            Path.Combine(root, "Assets/Resources/WorldGen"),
            Path.Combine(root, "Assets/Resources/UAL1Loco"),
            Path.Combine(root, "Assets/Resources/UAL2"),
            Path.Combine(root, "Assets/Resources/Content")
        };
        bool changed = false;
        for (int i = 0; i < legacyFolders.Length; i++)
        {
            if (!Directory.Exists(legacyFolders[i])) continue;
            Directory.Delete(legacyFolders[i], true);
            changed = true;
        }
        if (changed) AssetDatabase.Refresh();
    }
}
