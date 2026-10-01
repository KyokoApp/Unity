using System;
using System.Collections;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
using UnityEngine.Networking;

/// <summary>
/// Updater konten in-game (pola sama seperti launcher Godot lama):
/// APK hanya "peluncur" — saat start, game mengecek manifest di GitHub Release
/// `content-latest`, lalu mengunduh konten yang berubah (tuning.json + asset
/// bundle) ke persistentDataPath. Tanpa instal ulang APK.
/// Offline? Game tetap jalan pakai konten cache / bawaan APK.
/// </summary>
public class ContentUpdater : MonoBehaviour
{
    const string BaseUrl = "https://github.com/KyokoApp/Unity/releases/download/content-latest/";
    const string VersionKey = "ual2.contentVersion";

    PlayerController player;
    GameUI ui;

    string ContentDir { get { return Path.Combine(Application.persistentDataPath, "content"); } }

    [Serializable]
    public class ManifestPack
    {
        public string id;
        public string file;
        public string sha256;
        public long size;
    }

    [Serializable]
    public class Manifest
    {
        public int contentVersion;
        public string appVersion;
        public string apkUrl;
        public string tuningFile;
        public ManifestPack[] packs;
    }

    public void Init(PlayerController p, GameUI gameUi)
    {
        player = p;
        ui = gameUi;
        Directory.CreateDirectory(ContentDir);

        // 1) Default bawaan APK.
        var def = Resources.Load<TextAsset>("Content/tuning");
        if (def != null) Tuning.Apply(def.text, false, ui);

        // 2) Override dari cache unduhan sebelumnya.
        string cachedTuning = Path.Combine(ContentDir, "tuning.json");
        if (File.Exists(cachedTuning)) Tuning.Apply(File.ReadAllText(cachedTuning), false, ui);

        // 3) Bundle yang sudah pernah diunduh.
        LoadCachedBundles();

        // 4) Cek update ke server (non-blocking — game langsung jalan).
        StartCoroutine(CheckRemote());
    }

    void LoadCachedBundles()
    {
        string manifestPath = Path.Combine(ContentDir, "manifest.json");
        if (!File.Exists(manifestPath)) return;
        try
        {
            var m = JsonUtility.FromJson<Manifest>(File.ReadAllText(manifestPath));
            if (m == null || m.packs == null) return;
            foreach (var pack in m.packs)
                TryLoadBundle(Path.Combine(ContentDir, pack.file));
        }
        catch (Exception e)
        {
            Debug.LogWarning("[Updater] Manifest cache rusak: " + e.Message);
        }
    }

    IEnumerator CheckRemote()
    {
        if (ui != null) ui.SetStatus("Memeriksa update konten...", 8f);

        string manifestText;
        using (var req = UnityWebRequest.Get(BaseUrl + "manifest.json"))
        {
            req.timeout = 10;
            yield return req.SendWebRequest();
            if (req.result != UnityWebRequest.Result.Success)
            {
                if (ui != null) ui.SetStatus("Offline — pakai konten lokal", 3f);
                yield break;
            }
            manifestText = req.downloadHandler.text;
        }

        Manifest m = null;
        try { m = JsonUtility.FromJson<Manifest>(manifestText); }
        catch (Exception e) { Debug.LogWarning("[Updater] Manifest tidak valid: " + e.Message); }
        if (m == null)
        {
            if (ui != null) ui.SetStatus("Manifest server tidak valid", 3f);
            yield break;
        }

        // Info bila ada APK versi baru (pemain unduh manual dari Releases).
        if (!string.IsNullOrEmpty(m.appVersion) && IsNewer(m.appVersion, Application.version) && ui != null)
            ui.SetStatus("APK baru v" + m.appVersion + " tersedia di GitHub Releases!", 12f);

        int localVersion = PlayerPrefs.GetInt(VersionKey, 0);
        if (m.contentVersion <= localVersion)
        {
            if (ui != null) ui.SetStatus("Konten sudah terbaru (v" + localVersion + ")", 3f);
            yield break;
        }

        if (ui != null) ui.SetStatus("Mengunduh konten v" + m.contentVersion + "...", 30f);

        // ---- tuning.json ----
        string tuningName = string.IsNullOrEmpty(m.tuningFile) ? "tuning.json" : m.tuningFile;
        using (var req = UnityWebRequest.Get(BaseUrl + tuningName))
        {
            req.timeout = 15;
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success)
            {
                string txt = req.downloadHandler.text;
                File.WriteAllText(Path.Combine(ContentDir, "tuning.json"), txt);
                Tuning.Apply(txt, true, ui);
            }
        }

        // ---- asset bundle packs (inkremental via SHA-256) ----
        if (m.packs != null)
        {
            foreach (var pack in m.packs)
            {
                string local = Path.Combine(ContentDir, pack.file);
                if (File.Exists(local) && Sha256File(local) == pack.sha256)
                {
                    TryLoadBundle(local);
                    continue;
                }

                if (ui != null) ui.SetStatus("Mengunduh pack: " + pack.id + "...", 30f);
                using (var req = UnityWebRequest.Get(BaseUrl + pack.file))
                {
                    req.timeout = 120;
                    yield return req.SendWebRequest();
                    if (req.result != UnityWebRequest.Result.Success)
                    {
                        Debug.LogWarning("[Updater] Gagal unduh " + pack.file + ": " + req.error);
                        continue;
                    }
                    byte[] data = req.downloadHandler.data;
                    if (!string.IsNullOrEmpty(pack.sha256) && Sha256Bytes(data) != pack.sha256)
                    {
                        Debug.LogWarning("[Updater] SHA-256 tidak cocok untuk " + pack.file);
                        continue;
                    }
                    File.WriteAllBytes(local, data);
                    TryLoadBundle(local);
                }
            }
        }

        File.WriteAllText(Path.Combine(ContentDir, "manifest.json"), manifestText);
        PlayerPrefs.SetInt(VersionKey, m.contentVersion);
        PlayerPrefs.Save();
        if (ui != null) ui.SetStatus("Konten diperbarui ke v" + m.contentVersion + " ✔", 6f);
    }

    /// <summary>Muat asset bundle; bila berisi prefab "ContentBoot", spawn di world.</summary>
    void TryLoadBundle(string path)
    {
        if (!File.Exists(path)) return;
        try
        {
            var bundle = AssetBundle.LoadFromFile(path);
            if (bundle == null) return; // platform mismatch (mis. di Editor) — abaikan
            var boot = bundle.LoadAsset<GameObject>("ContentBoot");
            if (boot != null)
            {
                var old = GameObject.Find("ContentBoot(Clone)");
                if (old != null) Destroy(old);
                Instantiate(boot, Vector3.zero, Quaternion.identity);
            }
        }
        catch (Exception e)
        {
            Debug.LogWarning("[Updater] Gagal memuat bundle " + path + ": " + e.Message);
        }
    }

    static bool IsNewer(string remote, string local)
    {
        try
        {
            var r = remote.Split('.');
            var l = local.Split('.');
            for (int i = 0; i < Mathf.Max(r.Length, l.Length); i++)
            {
                int ri = i < r.Length ? int.Parse(r[i]) : 0;
                int li = i < l.Length ? int.Parse(l[i]) : 0;
                if (ri != li) return ri > li;
            }
        }
        catch { }
        return false;
    }

    static string Sha256File(string path)
    {
        return Sha256Bytes(File.ReadAllBytes(path));
    }

    static string Sha256Bytes(byte[] data)
    {
        using (var sha = SHA256.Create())
        {
            var hash = sha.ComputeHash(data);
            var sb = new System.Text.StringBuilder(hash.Length * 2);
            foreach (byte b in hash) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
}

/// <summary>Data tuning yang bisa di-update live dari server (tanpa instal ulang).</summary>
[Serializable]
public class TuningData
{
    public string motd;
    public float walkSpeed;
    public float runSpeed;
    public float sprintMul;
    public float jumpVel;
    public string gridBase;
    public string gridLine;
    public string gridMajor;
    public string fog;
}

public static class Tuning
{
    public static void Apply(string json, bool showMotd, GameUI ui)
    {
        TuningData t = null;
        try { t = JsonUtility.FromJson<TuningData>(json); }
        catch (Exception e) { Debug.LogWarning("[Tuning] JSON tidak valid: " + e.Message); }
        if (t == null) return;

        if (t.walkSpeed > 0f) PlayerController.WalkSpeed = t.walkSpeed;
        if (t.runSpeed > 0f) PlayerController.RunSpeed = t.runSpeed;
        if (t.sprintMul > 0f) PlayerController.SprintMul = t.sprintMul;
        if (t.jumpVel > 0f) PlayerController.JumpVel = t.jumpVel;

        Color cBase, cLine, cMajor, cFog;
        bool okBase = ColorUtility.TryParseHtmlString(t.gridBase, out cBase);
        bool okLine = ColorUtility.TryParseHtmlString(t.gridLine, out cLine);
        bool okMajor = ColorUtility.TryParseHtmlString(t.gridMajor, out cMajor);
        bool okFog = ColorUtility.TryParseHtmlString(t.fog, out cFog);
        if (okBase && okLine && okMajor)
            WorldGrid.ApplyLook(cBase, cLine, cMajor, okFog ? cFog : (Color?)null);

        if (showMotd && !string.IsNullOrEmpty(t.motd) && ui != null)
            ui.SetStatus(t.motd, 8f);
    }
}
