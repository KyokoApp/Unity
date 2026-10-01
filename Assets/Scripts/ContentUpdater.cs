using System;
using System.Collections;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
using UnityEngine.Networking;

/// <summary>
/// Updater visual in-game: mengecek manifest GitHub `content-latest`, mengunduh
/// tuning/AssetBundle bertanda SHA-256, dan menawarkan APK baru lewat installer
/// Android bila versi aplikasi berubah. Konten cache dan Resources menjadi fallback offline.
/// </summary>
public class ContentUpdater : MonoBehaviour
{
    const string BaseUrl = "https://github.com/KyokoApp/Unity/releases/download/content-latest/";
    const string VersionKey = "ual2.contentVersion";

    PlayerController player;
    GameUI ui;
    bool apkUpdateInProgress;

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
        public string apkSha256;
        public long apkSize;
        public string tuningFile;
        public string tuningSha256;
        public long tuningSize;
        public ManifestPack[] packs;
    }

    /// <summary>Dipanggil sebelum dunia dibuat supaya tuning dan visual cache aktif sejak frame pertama.</summary>
    public static void LoadCachedBootstrapData()
    {
        string contentDir = Path.Combine(Application.persistentDataPath, "content");
        Directory.CreateDirectory(contentDir);
        var def = Resources.Load<TextAsset>("Content/tuning");
        if (def != null) Tuning.Apply(def.text, false, null);
        ApplyCachedTuning(contentDir, null);
        LoadCachedBundlesForGame();
    }

    static void ApplyCachedTuning(string contentDir, GameUI gameUi)
    {
        string tuningName = "tuning.json";
        string expectedSha = null;
        long expectedSize = 0;
        string manifestPath = Path.Combine(contentDir, "manifest.json");
        if (File.Exists(manifestPath))
        {
            try
            {
                var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(manifestPath));
                if (manifest != null && !string.IsNullOrEmpty(manifest.tuningFile))
                {
                    if (!IsSafeFileName(manifest.tuningFile)) return;
                    tuningName = manifest.tuningFile;
                    expectedSha = manifest.tuningSha256;
                    expectedSize = manifest.tuningSize;
                }
            }
            catch (Exception e) { Debug.LogWarning("[Updater] Tidak bisa membaca manifest tuning cache: " + e.Message); }
        }

        string path = Path.Combine(contentDir, tuningName);
        if (!File.Exists(path)) return;
        try
        {
            byte[] data = File.ReadAllBytes(path);
            bool legacyTuning = tuningName == "tuning.json" && string.IsNullOrEmpty(expectedSha);
            if ((!IsSha256(expectedSha) && !legacyTuning)
                || (expectedSize > 0 && data.LongLength != expectedSize)
                || (IsSha256(expectedSha) && !string.Equals(Sha256Bytes(data), expectedSha, StringComparison.OrdinalIgnoreCase)))
            {
                Debug.LogWarning("[Updater] Cache tuning tidak lolos verifikasi hash/ukuran.");
                return;
            }
            Tuning.Apply(System.Text.Encoding.UTF8.GetString(data), false, gameUi);
        }
        catch (Exception e) { Debug.LogWarning("[Updater] Cache tuning tidak bisa dibaca: " + e.Message); }
    }

    public void Init(PlayerController p, GameUI gameUi)
    {
        player = p;
        ui = gameUi;
        Directory.CreateDirectory(ContentDir);

        // Terapkan ulang setelah material WorldGrid dibuat agar palet/fog ikut diterapkan;
        // nilai density/speed yang sama sudah dipakai lebih awal saat membangun dunia.
        var def = Resources.Load<TextAsset>("Content/tuning");
        if (def != null) Tuning.Apply(def.text, false, ui);
        ApplyCachedTuning(ContentDir, ui);

        // Cache bundle sudah dimuat sebelum dunia dibangun; muat prefab ContentBoot bila ada.
        LoadCachedBundles();

        // Cek update ke server tanpa memblokir permainan.
        StartCoroutine(CheckRemote());
    }

    /// <summary>Load paket tersimpan sebelum AnimLibrary/world dibuat, agar visual remote dipakai saat boot.</summary>
    public static void LoadCachedBundlesForGame()
    {
        string contentDir = Path.Combine(Application.persistentDataPath, "content");
        string manifestPath = Path.Combine(contentDir, "manifest.json");
        if (!File.Exists(manifestPath)) return;
        try
        {
            var m = JsonUtility.FromJson<Manifest>(File.ReadAllText(manifestPath));
            if (m == null || m.packs == null) return;
            foreach (var pack in m.packs)
            {
                if (pack == null || string.IsNullOrEmpty(pack.id) || !IsSafeFileName(pack.id)
                    || string.IsNullOrEmpty(pack.file) || !IsSafeFileName(pack.file) || !IsSha256(pack.sha256)) continue;
                string path = FindCachedPackPath(contentDir, pack);
                if (string.IsNullOrEmpty(path)) continue;
                RemoteAssetCatalog.LoadPack(pack.id, path);
            }
        }
        catch (Exception e)
        {
            Debug.LogWarning("[Updater] Paket cache tidak bisa dipakai: " + e.Message);
        }
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
            {
                if (pack == null || string.IsNullOrEmpty(pack.id) || !IsSafeFileName(pack.id)
                    || string.IsNullOrEmpty(pack.file) || !IsSafeFileName(pack.file) || !IsSha256(pack.sha256)) continue;
                string path = FindCachedPackPath(ContentDir, pack);
                if (!string.IsNullOrEmpty(path)) TryLoadBundle(pack.id, path);
            }
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

        // Tawarkan unduh dan pemasangan APK dari dalam game jika metadata rilis tepercaya lengkap.
        if (!string.IsNullOrEmpty(m.appVersion) && IsNewer(m.appVersion, Application.version))
        {
            if (ui != null && IsTrustedApkUrl(m.apkUrl) && IsSha256(m.apkSha256))
            {
                ui.ShowAppUpdate(m.appVersion, delegate
                {
                    if (!apkUpdateInProgress) StartCoroutine(DownloadAndInstallApk(m));
                });
                ui.SetStatus("APK v" + m.appVersion + " tersedia — ketuk tombol update", 10f);
            }
            else if (ui != null)
                ui.SetStatus("APK baru v" + m.appVersion + " tersedia, tetapi metadata unduh belum lengkap", 10f);
        }

        int localVersion = PlayerPrefs.GetInt(VersionKey, 0);
        if (m.contentVersion <= localVersion)
        {
            if (ui != null) ui.SetStatus("Konten sudah terbaru (v" + localVersion + ")", 3f);
            yield break;
        }

        if (ui != null) ui.SetStatus("Mengunduh konten v" + m.contentVersion + "...", 30f);

        bool downloadComplete = true;
        string downloadedTuningText = null;

        // ---- tuning.json ----
        string tuningName = string.IsNullOrEmpty(m.tuningFile) ? "tuning.json" : m.tuningFile;
        if (!IsSafeFileName(tuningName))
        {
            if (ui != null) ui.SetStatus("Manifest server tidak valid", 3f);
            yield break;
        }
        using (var req = UnityWebRequest.Get(BaseUrl + tuningName))
        {
            req.timeout = 15;
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success)
            {
                byte[] tuningBytes = req.downloadHandler.data ?? new byte[0];
                bool hasTuningHash = IsSha256(m.tuningSha256);
                bool legacyTuning = string.IsNullOrEmpty(m.tuningSha256) && tuningName == "tuning.json";
                bool invalidTuning = (!hasTuningHash && !legacyTuning)
                    || (m.tuningSize > 0 && tuningBytes.LongLength != m.tuningSize)
                    || (hasTuningHash && !string.Equals(Sha256Bytes(tuningBytes), m.tuningSha256, StringComparison.OrdinalIgnoreCase));
                if (invalidTuning)
                {
                    downloadComplete = false;
                    Debug.LogWarning("[Updater] Ukuran atau SHA-256 tuning tidak cocok.");
                }
                else
                {
                    downloadedTuningText = System.Text.Encoding.UTF8.GetString(tuningBytes);
                    File.WriteAllBytes(Path.Combine(ContentDir, tuningName), tuningBytes);
                }
            }
            else
            {
                downloadComplete = false;
                Debug.LogWarning("[Updater] Gagal unduh tuning.json: " + req.error);
            }
        }

        // ---- asset bundle packs (inkremental via SHA-256) ----
        if (m.packs != null)
        {
            foreach (var pack in m.packs)
            {
                if (pack == null || string.IsNullOrEmpty(pack.id) || !IsSafeFileName(pack.id)
                    || string.IsNullOrEmpty(pack.file) || !IsSafeFileName(pack.file) || !IsSha256(pack.sha256))
                {
                    downloadComplete = false;
                    Debug.LogWarning("[Updater] Entri asset pack tidak lengkap atau tidak aman di manifest.");
                    continue;
                }

                string local = FindCachedPackPath(ContentDir, pack);
                if (!string.IsNullOrEmpty(local))
                {
                    TryLoadBundle(pack.id, local);
                    continue;
                }

                local = GetPackCachePath(ContentDir, pack);
                string partial = local + ".download";
                try { if (File.Exists(partial)) File.Delete(partial); }
                catch (Exception e)
                {
                    downloadComplete = false;
                    Debug.LogWarning("[Updater] Tidak bisa menyiapkan cache pack " + pack.id + ": " + e.Message);
                    continue;
                }

                if (ui != null) ui.SetStatus("Mengunduh pack: " + pack.id + "...", 30f);
                using (var req = UnityWebRequest.Get(BaseUrl + pack.file))
                {
                    req.timeout = 120;
                    req.downloadHandler = new DownloadHandlerFile(partial);
                    yield return req.SendWebRequest();
                    if (req.result != UnityWebRequest.Result.Success || !File.Exists(partial))
                    {
                        downloadComplete = false;
                        Debug.LogWarning("[Updater] Gagal unduh " + pack.file + ": " + req.error);
                        try { if (File.Exists(partial)) File.Delete(partial); } catch { }
                        continue;
                    }
                }

                var downloadedPack = new FileInfo(partial);
                if ((pack.size > 0 && downloadedPack.Length != pack.size)
                    || !string.Equals(Sha256File(partial), pack.sha256, StringComparison.OrdinalIgnoreCase))
                {
                    downloadComplete = false;
                    Debug.LogWarning("[Updater] Ukuran atau SHA-256 tidak cocok untuk " + pack.file);
                    try { File.Delete(partial); } catch { }
                    continue;
                }

                try
                {
                    if (File.Exists(local)) File.Delete(local);
                    File.Move(partial, local);
                }
                catch (Exception e)
                {
                    downloadComplete = false;
                    Debug.LogWarning("[Updater] Tidak bisa menyimpan pack " + pack.id + ": " + e.Message);
                    continue;
                }
                TryLoadBundle(pack.id, local);
            }
        }

        if (!downloadComplete)
        {
            // Jangan tandai versinya selesai: coba lagi saat aplikasi dibuka berikutnya.
            if (ui != null) ui.SetStatus("Update konten belum lengkap — akan dicoba lagi", 6f);
            yield break;
        }

        File.WriteAllText(Path.Combine(ContentDir, "manifest.json"), manifestText);
        PlayerPrefs.SetInt(VersionKey, m.contentVersion);
        PlayerPrefs.Save();
        if (downloadedTuningText != null) Tuning.Apply(downloadedTuningText, true, ui);
        if (ui != null) ui.SetStatus("Konten diperbarui ke v" + m.contentVersion + " ✔", 6f);
    }

    IEnumerator DownloadAndInstallApk(Manifest manifest)
    {
        if (manifest == null || !IsTrustedApkUrl(manifest.apkUrl) || !IsSha256(manifest.apkSha256))
        {
            if (ui != null) ui.SetAppUpdateMessage("METADATA UPDATE TIDAK VALID");
            yield break;
        }

        apkUpdateInProgress = true;
        string updateDir = Path.Combine(Application.persistentDataPath, "updates");
        string apkPath = Path.Combine(updateDir, "Arpg.apk");
        string partialPath = apkPath + ".download";
        Directory.CreateDirectory(updateDir);

        bool cached = File.Exists(apkPath)
            && (manifest.apkSize <= 0 || new FileInfo(apkPath).Length == manifest.apkSize)
            && string.Equals(Sha256File(apkPath), manifest.apkSha256, StringComparison.OrdinalIgnoreCase);

        if (!cached)
        {
            try { if (File.Exists(partialPath)) File.Delete(partialPath); }
            catch (Exception e)
            {
                apkUpdateInProgress = false;
                if (ui != null) ui.SetAppUpdateMessage("TIDAK BISA MENYIAPKAN PENYIMPANAN APK");
                Debug.LogWarning("[Updater] Tidak bisa membersihkan file APK sementara: " + e.Message);
                yield break;
            }

            if (ui != null) ui.SetAppUpdateMessage("MENGUNDUH APK... 0%");
            using (var req = UnityWebRequest.Get(manifest.apkUrl))
            {
                req.timeout = 240;
                req.downloadHandler = new DownloadHandlerFile(partialPath);
                var operation = req.SendWebRequest();
                while (!operation.isDone)
                {
                    if (ui != null) ui.SetAppUpdateProgress(req.downloadProgress);
                    yield return null;
                }

                if (req.result != UnityWebRequest.Result.Success || !File.Exists(partialPath))
                {
                    string error = req.error;
                    apkUpdateInProgress = false;
                    if (ui != null) ui.SetAppUpdateMessage("GAGAL MENGUNDUH — COBA LAGI");
                    Debug.LogWarning("[Updater] Gagal mengunduh APK: " + error);
                    try { if (File.Exists(partialPath)) File.Delete(partialPath); } catch { }
                    yield break;
                }
            }

            var downloaded = new FileInfo(partialPath);
            if ((manifest.apkSize > 0 && downloaded.Length != manifest.apkSize)
                || !string.Equals(Sha256File(partialPath), manifest.apkSha256, StringComparison.OrdinalIgnoreCase))
            {
                apkUpdateInProgress = false;
                if (ui != null) ui.SetAppUpdateMessage("VERIFIKASI APK GAGAL — COBA LAGI");
                Debug.LogWarning("[Updater] Ukuran atau SHA-256 APK tidak cocok; file sementara dibuang.");
                try { File.Delete(partialPath); } catch { }
                yield break;
            }

            try
            {
                if (File.Exists(apkPath)) File.Delete(apkPath);
                File.Move(partialPath, apkPath);
            }
            catch (Exception e)
            {
                apkUpdateInProgress = false;
                if (ui != null) ui.SetAppUpdateMessage("TIDAK BISA MENYIMPAN APK — COBA LAGI");
                Debug.LogWarning("[Updater] Gagal menyimpan APK yang sudah diunduh: " + e.Message);
                yield break;
            }
        }

        if (ui != null) ui.SetAppUpdateMessage("MEMBUKA PEMASANG APK...");
        OpenAndroidInstaller(apkPath);
        apkUpdateInProgress = false;
    }

    static bool IsTrustedApkUrl(string url)
    {
        Uri uri;
        return Uri.TryCreate(url, UriKind.Absolute, out uri)
            && uri.Scheme == Uri.UriSchemeHttps
            && string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase)
            && uri.AbsolutePath.StartsWith("/KyokoApp/Unity/releases/download/", StringComparison.OrdinalIgnoreCase);
    }

    static bool IsSha256(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
        for (int i = 0; i < value.Length; i++)
            if (!Uri.IsHexDigit(value[i])) return false;
        return true;
    }

    static bool IsSafeFileName(string value)
    {
        if (string.IsNullOrEmpty(value) || value == "." || value == ".."
            || value.IndexOf('/') >= 0 || value.IndexOf('\\') >= 0) return false;
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (!(char.IsLetterOrDigit(c) || c == '.' || c == '_' || c == '-')) return false;
        }
        return true;
    }

    static string GetPackCachePath(string contentDir, ManifestPack pack)
    {
        if (pack == null || !IsSafeFileName(pack.id) || !IsSha256(pack.sha256)) return null;
        return Path.Combine(contentDir, pack.id + "-" + pack.sha256.ToLowerInvariant() + ".bundle");
    }

    static string FindCachedPackPath(string contentDir, ManifestPack pack)
    {
        if (pack == null || !IsSafeFileName(pack.file) || !IsSha256(pack.sha256)) return null;
        string versionedPath = GetPackCachePath(contentDir, pack);
        string[] candidates = { versionedPath, Path.Combine(contentDir, pack.file) }; // file kedua: cache versi lama
        foreach (string path in candidates)
        {
            if (string.IsNullOrEmpty(path) || !File.Exists(path)) continue;
            try
            {
                if (string.Equals(Sha256File(path), pack.sha256, StringComparison.OrdinalIgnoreCase)) return path;
            }
            catch (Exception e) { Debug.LogWarning("[Updater] Cache pack tidak terbaca: " + e.Message); }
        }
        return null;
    }

    void OpenAndroidInstaller(string apkPath)
    {
        if (!File.Exists(apkPath))
        {
            if (ui != null) ui.SetAppUpdateMessage("FILE APK TIDAK DITEMUKAN — COBA LAGI");
            return;
        }
#if UNITY_ANDROID && !UNITY_EDITOR
        try
        {
            using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using (var activity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
            using (var buildVersion = new AndroidJavaClass("android.os.Build$VERSION"))
            {
                string packageName = activity.Call<string>("getPackageName");
                int apiLevel = buildVersion.GetStatic<int>("SDK_INT");
                if (apiLevel >= 26)
                {
                    using (var packageManager = activity.Call<AndroidJavaObject>("getPackageManager"))
                    {
                        if (!packageManager.Call<bool>("canRequestPackageInstalls"))
                        {
                            using (var intent = new AndroidJavaObject("android.content.Intent", "android.settings.MANAGE_UNKNOWN_APP_SOURCES"))
                            using (var uriClass = new AndroidJavaClass("android.net.Uri"))
                            using (var settingsUri = uriClass.CallStatic<AndroidJavaObject>("parse", "package:" + packageName))
                            {
                                intent.Call("setData", settingsUri);
                                activity.Call("startActivity", intent);
                            }
                            if (ui != null) ui.SetAppUpdateMessage("IZINKAN PEMASANGAN DARI ARPG, LALU KETUK LAGI");
                            return;
                        }
                    }
                }

                string contentUri = "content://" + packageName + ".apkprovider/apk/Arpg.apk";
                using (var uriClass = new AndroidJavaClass("android.net.Uri"))
                using (var uri = uriClass.CallStatic<AndroidJavaObject>("parse", contentUri))
                using (var intent = new AndroidJavaObject("android.content.Intent", "android.intent.action.VIEW"))
                {
                    intent.Call("setDataAndType", uri, "application/vnd.android.package-archive");
                    intent.Call("addFlags", 0x00000001); // FLAG_GRANT_READ_URI_PERMISSION
                    intent.Call("addFlags", 0x10000000); // FLAG_ACTIVITY_NEW_TASK
                    activity.Call("startActivity", intent);
                }
            }
        }
        catch (Exception e)
        {
            if (ui != null) ui.SetAppUpdateMessage("GAGAL MEMBUKA PEMASANG APK");
            Debug.LogWarning("[Updater] Tidak bisa membuka installer Android: " + e.Message);
        }
#else
        if (ui != null) ui.SetAppUpdateMessage("PEMASANGAN APK HANYA TERSEDIA DI ANDROID");
#endif
    }

    /// <summary>Muat asset bundle ke katalog; prefab "ContentBoot" tetap bisa menambah konten world.</summary>
    void TryLoadBundle(string id, string path)
    {
        if (!File.Exists(path)) return;
        try
        {
            var bundle = RemoteAssetCatalog.LoadPack(id, path);
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
        using (var sha = SHA256.Create())
        using (var stream = File.OpenRead(path))
            return ToHex(sha.ComputeHash(stream));
    }

    static string Sha256Bytes(byte[] data)
    {
        using (var sha = SHA256.Create())
            return ToHex(sha.ComputeHash(data));
    }

    static string ToHex(byte[] hash)
    {
        var sb = new System.Text.StringBuilder(hash.Length * 2);
        foreach (byte b in hash) sb.Append(b.ToString("x2"));
        return sb.ToString();
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
    public float grassDensity;
    public float treeDensity;
}

/// <summary>Parameter dunia yang bisa di-tune live (tanpa instal ulang APK).</summary>
public static class WorldTuning
{
    public static float GrassDensity = 1f;
    public static float TreeDensity = 1f;
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
        if (t.grassDensity > 0f) WorldTuning.GrassDensity = Mathf.Clamp(t.grassDensity, 0.1f, 2f);
        if (t.treeDensity > 0f) WorldTuning.TreeDensity = Mathf.Clamp(t.treeDensity, 0.1f, 2f);

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
