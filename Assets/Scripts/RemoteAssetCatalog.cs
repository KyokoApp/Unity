using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Registry untuk AssetBundle visual/animasi yang diunduh dari GitHub.
/// Asset bawaan Resources tetap menjadi fallback offline; paket remote dengan
/// nama bundle yang sama diprioritaskan saat game berikutnya dimuat.
/// </summary>
public static class RemoteAssetCatalog
{
    sealed class PackEntry
    {
        public string path;
        public AssetBundle bundle;
    }

    static readonly Dictionary<string, PackEntry> packs = new Dictionary<string, PackEntry>();

    public static AssetBundle LoadPack(string id, string path)
    {
        if (string.IsNullOrEmpty(id) || string.IsNullOrEmpty(path)) return null;

        PackEntry current = null;
        if (packs.TryGetValue(id, out current) && current.bundle != null && current.path == path)
            return current.bundle;

        var bundle = AssetBundle.LoadFromFile(path);
        if (bundle == null) return null;

        if (current != null && current.bundle != null)
            current.bundle.Unload(false); // aset yang sedang dipakai tetap hidup sampai dilepas Unity

        packs[id] = new PackEntry { path = path, bundle = bundle };
        return bundle;
    }

    public static T Load<T>(string bundleId, string assetName) where T : Object
    {
        PackEntry entry;
        if (packs.TryGetValue(bundleId, out entry) && entry.bundle != null)
            return entry.bundle.LoadAsset<T>(assetName);
        return null;
    }

    public static T[] LoadAll<T>(string bundleId) where T : Object
    {
        PackEntry entry;
        if (packs.TryGetValue(bundleId, out entry) && entry.bundle != null)
            return entry.bundle.LoadAllAssets<T>();
        return new T[0];
    }
}
