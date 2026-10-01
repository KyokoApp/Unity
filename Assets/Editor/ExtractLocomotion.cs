using System.IO;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Ekstrak clip lokomosi UAL1 (Walk_Loop / Jog_Fwd_Loop / Sprint_Loop) dari
/// Assets/UAL1/UAL1_Standard.fbx menjadi .anim mandiri di
/// Assets/Resources/UAL1Loco/ supaya bisa dimuat runtime lewat
/// Resources.LoadAll.
///
/// Kenapa begini? FBX UAL1 (24 MB, berisi seluruh library + model) sengaja
/// ditaruh DI LUAR Resources — kalau tidak, seluruh isinya ikut ter-pack ke
/// APK. Yang dibutuhkan runtime hanya 3 clip lokomosi, jadi CiBuild.BuildAll
/// memanggil Run() sebelum build: clip disalin (Object.Instantiate menjaga
/// data muscle Humanoid → otomatis retarget ke mannequin UAL2 & Mannequin F)
/// dan hanya salinan kecil itu yang masuk APK.
///
/// Folder hasil (Assets/Resources/UAL1Loco/) di-gitignore: dibangkitkan ulang
/// setiap build CI, jangan pernah di-commit.
///
/// Catatan: UAL1_Standard.fbx adalah varian IN-PLACE (bukan _RM/root-motion)
/// — cocok untuk gerakan yang dikendalikan kode.
/// </summary>
public static class ExtractLocomotion
{
    const string FbxPath = "Assets/UAL1/UAL1_Standard.fbx";
    const string OutDir = "Assets/Resources/UAL1Loco";

    // nama take di FBX (tanpa prefix "Armature|") → nama clip hasil ekstraksi
    static readonly string[,] Map =
    {
        { "Walk_Loop",    "UAL1_Walk_Loop" },
        { "Jog_Fwd_Loop", "UAL1_Jog_Loop" },
        { "Sprint_Loop",  "UAL1_Sprint_Loop" },
    };

    [MenuItem("Assets/Ekstrak Clip Lokomosi UAL1")]
    public static void Run()
    {
        if (!File.Exists(FbxPath))
        {
            Debug.LogWarning("[ExtractLoco] " + FbxPath + " tidak ada — lokomosi memakai fallback UAL2 (Walk_Fwd_Loop).");
            return;
        }

        Directory.CreateDirectory(OutDir);

        var assets = AssetDatabase.LoadAllAssetsAtPath(FbxPath);
        int copied = 0;
        for (int i = 0; i < Map.GetLength(0); i++)
        {
            string take = Map[i, 0];
            string outName = Map[i, 1];

            AnimationClip src = FindTake(assets, take);
            if (src == null)
            {
                Debug.LogError("[ExtractLoco] Take tidak ditemukan di FBX: " + take);
                continue;
            }

            string outPath = OutDir + "/" + outName + ".anim";
            if (AssetDatabase.LoadAssetAtPath<AnimationClip>(outPath) != null)
                AssetDatabase.DeleteAsset(outPath);

            // Instantiate (bukan CopySerialized) menjaga kurva muscle Humanoid.
            var inst = Object.Instantiate(src);
            inst.name = outName;
            AssetDatabase.CreateAsset(inst, outPath);
            copied++;
        }

        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("[ExtractLoco] " + copied + " clip lokomosi UAL1 siap di " + OutDir);
    }

    static AnimationClip FindTake(Object[] assets, string take)
    {
        foreach (var a in assets)
        {
            var clip = a as AnimationClip;
            if (clip == null || clip.name.StartsWith("__preview__")) continue;
            string n = clip.name;
            int bar = n.LastIndexOf('|');
            if (bar >= 0) n = n.Substring(bar + 1);
            if (n == take) return clip;
        }
        return null;
    }
}
