using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Memuat seluruh isi Universal Animation Library 2 [Standard] (Quaternius, CC0)
/// dari folder Resources/UAL2: model mannequin + 43 animation clip,
/// PLUS 3 clip lokomosi UAL1 (UAL1_Walk/Jog/Sprint_Loop) dari Resources/UAL1Loco
/// yang diekstrak ExtractLocomotion saat build CI.
/// Kunci clip memakai nama take tanpa prefix "Armature|".
/// </summary>
public class AnimLibrary
{
    public GameObject ModelUAL2 { get; private set; }
    public GameObject ModelMannequinF { get; private set; }

    readonly Dictionary<string, AnimationClip> clips = new Dictionary<string, AnimationClip>();
    public readonly List<string> Keys = new List<string>();

    public AnimLibrary()
    {
        ModelUAL2 = Resources.Load<GameObject>("UAL2/UAL2_Standard");
        ModelMannequinF = Resources.Load<GameObject>("UAL2/Mannequin_F");

        foreach (var c in Resources.LoadAll<AnimationClip>("UAL2"))
        {
            if (c == null) continue;
            if (c.name.StartsWith("__preview__")) continue;

            string key = c.name;
            int bar = key.LastIndexOf('|');
            if (bar >= 0) key = key.Substring(bar + 1);

            if (!clips.ContainsKey(key))
            {
                clips[key] = c;
                Keys.Add(key);
            }
        }

        // Lokomosi UAL1 (walk/jog/sprint) — diekstrak dari Assets/UAL1/UAL1_Standard.fbx
        // saat build CI oleh ExtractLocomotion. Tidak ada folder ini (mis. Play di editor
        // tanpa menjalankan Ekstrak dulu)? PlayerController fallback ke Walk_Fwd_Loop UAL2.
        foreach (var c in Resources.LoadAll<AnimationClip>("UAL1Loco"))
        {
            if (c == null || c.name.StartsWith("__preview__")) continue;
            if (!clips.ContainsKey(c.name))
            {
                clips[c.name] = c;
                Keys.Add(c.name);
            }
        }
        Keys.Sort();
    }

    public int Count { get { return Keys.Count; } }

    public AnimationClip Get(string key)
    {
        AnimationClip c;
        if (!clips.TryGetValue(key, out c) || c == null)
        {
            Debug.LogWarning("[UAL2] Clip tidak ditemukan: " + key);
            return null;
        }
        return c;
    }

    /// <summary>Ambil clip tanpa warning bila tidak ada (untuk probe opsional tiap frame).</summary>
    public AnimationClip Find(string key)
    {
        AnimationClip c;
        clips.TryGetValue(key, out c);
        return c;
    }

    /// <summary>Animasi dianggap looping bila namanya berakhiran "_Loop" (konvensi resmi UAL2).</summary>
    public static bool IsLoop(string key)
    {
        return key.EndsWith("_Loop");
    }
}
