using Godot;
using System;
using System.Text.Json;
using System.Collections.Generic;

public partial class Bootstrapper : Control
{
    [Export] public ProgressBar ProgressBar;
    [Export] public Label StatusLabel;
    [Export] public Label DetailLabel;
    [Export] public Label SpeedLabel;
    [Export] public Button RetryButton;
    [Export] public VideoStreamPlayer VideoPlayer;
    [Export] public HttpRequest ManifestRequest;
    [Export] public HttpRequest DownloadRequest;

    [Export] public string FallbackManifestUrl = "https://github.com/KyokoApp/Unity/releases/download/android-apk/version.json";
    [Export] public string GitHubApiReleaseUrl = "https://api.github.com/repos/KyokoApp/Unity/releases/tags/android-apk";
    [Export] public string TargetMainScene = "res://_scenes/main.tscn";

    private class PackInfo
    {
        public string Name { get; set; } = "";
        public string Url { get; set; } = "";
        public long Size { get; set; } = 0;
        public string Sha256 { get; set; } = "";
        public bool IsPatch { get; set; } = false;
        public int Order { get; set; } = 0;
    }

    private class ManifestData
    {
        public string Version { get; set; } = "1.0.0";
        public List<PackInfo> Packs { get; set; } = new();
    }

    private ManifestData _manifest = new();
    private readonly List<PackInfo> _pendingPacks = new();
    private PackInfo _currentDownloadingPack = null;
    private long _downloadStartTime = 0;
    private long _lastBytes = 0;
    private double _speedUpdateTimer = 0.0;
    private bool _isDownloading = false;

    public override void _Ready()
    {
        RetryButton.Visible = false;
        RetryButton.Pressed += OnRetryPressed;

        ManifestRequest.RequestCompleted += OnManifestRequestCompleted;
        DownloadRequest.RequestCompleted += OnDownloadRequestCompleted;

        PlayLoadingVideo();
        StartUpdateCheck();
    }

    public override void _Process(double delta)
    {
        if (!_isDownloading || _currentDownloadingPack == null) return;

        int downloaded = DownloadRequest.GetDownloadedBytes();
        int bodySize = DownloadRequest.GetBodySize();
        long totalSize = bodySize > 0 ? bodySize : _currentDownloadingPack.Size;

        if (totalSize > 0)
        {
            double percent = (double)downloaded / totalSize * 100.0;
            ProgressBar.Value = Math.Clamp(percent, 0.0, 100.0);

            double downloadedMB = downloaded / (1024.0 * 1024.0);
            double totalMB = totalSize / (1024.0 * 1024.0);
            DetailLabel.Text = $"Mengunduh aset: {downloadedMB:F1} MB / {totalMB:F1} MB [{percent:F0}%]";
        }
        else
        {
            double downloadedMB = downloaded / (1024.0 * 1024.0);
            DetailLabel.Text = $"Mengunduh: {downloadedMB:F1} MB";
        }

        _speedUpdateTimer += delta;
        if (_speedUpdateTimer >= 0.5)
        {
            long now = (long)Time.GetTicksMsec();
            long timeDiff = now - _downloadStartTime;
            if (timeDiff > 0 && downloaded > _lastBytes)
            {
                double speedBps = (downloaded - _lastBytes) / (_speedUpdateTimer);
                if (speedBps >= 1024 * 1024)
                {
                    SpeedLabel.Text = $"{speedBps / (1024 * 1024):F2} MB/s";
                }
                else
                {
                    SpeedLabel.Text = $"{speedBps / 1024:F1} KB/s";
                }
            }
            _lastBytes = downloaded;
            _speedUpdateTimer = 0.0;
        }
    }

    private void StartUpdateCheck()
    {
        RetryButton.Visible = false;
        ProgressBar.Value = 0;
        SpeedLabel.Text = "";
        DetailLabel.Text = "";
        StatusLabel.Text = "Memeriksa pembaruan...";

        // Try downloading manifest via direct GitHub release asset URL first
        string[] headers = new string[] { "User-Agent: GodotEngine-Downloader" };
        Error err = ManifestRequest.Request(FallbackManifestUrl, headers);
        if (err != Error.Ok)
        {
            GD.PrintErr($"Gagal mengirim request manifest: {err}");
            ShowError("Gagal memeriksa pembaruan. Periksa koneksi internet.");
        }
    }

    private void OnManifestRequestCompleted(long result, long responseCode, string[] headers, byte[] body)
    {
        GD.Print($"Manifest request completed: result={result}, responseCode={responseCode}");

        if (result == (long)HttpRequest.Result.Success && responseCode == 200 && body != null && body.Length > 0)
        {
            try
            {
                string jsonString = System.Text.Encoding.UTF8.GetString(body);
                ParseManifestAndProcess(jsonString);
                return;
            }
            catch (Exception ex)
            {
                GD.PrintErr($"Error parsing manifest JSON: {ex.Message}");
            }
        }

        // If direct release download fails (e.g. 404 or auth on private repo), try GitHub API
        if (ManifestRequest.GetMeta("tried_api", false).AsBool() == false)
        {
            GD.Print("Direct manifest request failed. Trying GitHub API endpoint...");
            ManifestRequest.SetMeta("tried_api", true);
            string[] apiHeaders = new string[] {
                "User-Agent: GodotEngine-Downloader",
                "Accept: application/vnd.github.v3+json"
            };
            Error err = ManifestRequest.Request(GitHubApiReleaseUrl, apiHeaders);
            if (err == Error.Ok) return;
        }

        // If network failed but local PCK already exists, attempt to load local pack
        string localPckPath = "user://assets_v1.pck";
        if (FileAccess.FileExists(localPckPath))
        {
            GD.Print("Offline mode: Found existing assets_v1.pck, continuing with local pack.");
            StatusLabel.Text = "Mode Offline: Memuat aset lokal...";
            LoadPacksAndProceed(new List<string> { localPckPath });
            return;
        }

        ShowError($"Gagal menghubungkan ke server pembaruan (HTTP {responseCode}).");
    }

    private void ParseManifestAndProcess(string jsonString)
    {
        try
        {
            using var doc = JsonDocument.Parse(jsonString);
            var root = doc.RootElement;

            _manifest = new ManifestData();
            if (root.TryGetProperty("version", out var vProp))
                _manifest.Version = vProp.GetString() ?? "1.0.0";

            if (root.TryGetProperty("packs", out var packsProp) && packsProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in packsProp.EnumerateArray())
                {
                    var p = new PackInfo
                    {
                        Name = item.GetProperty("name").GetString() ?? "",
                        Url = item.GetProperty("url").GetString() ?? "",
                        Size = item.TryGetProperty("size", out var sProp) ? sProp.GetInt64() : 0,
                        Sha256 = item.TryGetProperty("sha256", out var hProp) ? hProp.GetString() ?? "" : "",
                        IsPatch = item.TryGetProperty("is_patch", out var patchProp) && patchProp.GetBoolean(),
                        Order = item.TryGetProperty("order", out var oProp) ? oProp.GetInt32() : 0
                    };
                    _manifest.Packs.Add(p);
                }
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"Failed to parse manifest: {ex.Message}");
            ShowError("Format manifest pembaruan tidak valid.");
            return;
        }

        // Sort packs by Order ascending (Base pack first, then patch 1, patch 2, etc.)
        _manifest.Packs.Sort((a, b) => a.Order.CompareTo(b.Order));

        // Check which packs need download
        _pendingPacks.Clear();
        var packsToLoad = new List<string>();

        foreach (var pack in _manifest.Packs)
        {
            string userPath = $"user://{pack.Name}";
            bool needsDownload = true;

            if (FileAccess.FileExists(userPath))
            {
                using var fa = FileAccess.Open(userPath, FileAccess.ModeFlags.Read);
                if (fa != null)
                {
                    long existingSize = (long)fa.GetLength();
                    // If size matches (or size not specified), pack is valid
                    if (pack.Size <= 0 || existingSize == pack.Size)
                    {
                        needsDownload = false;
                        packsToLoad.Add(userPath);
                        GD.Print($"Pack {pack.Name} already up to date ({existingSize} bytes).");
                    }
                    else
                    {
                        GD.Print($"Pack {pack.Name} size mismatch: local {existingSize} vs manifest {pack.Size}. Re-downloading.");
                    }
                }
            }

            if (needsDownload)
            {
                _pendingPacks.Add(pack);
            }
        }

        if (_pendingPacks.Count > 0)
        {
            DownloadNextPack(packsToLoad);
        }
        else
        {
            StatusLabel.Text = "Aset sudah mutakhir. Memuat...";
            ProgressBar.Value = 100;
            LoadPacksAndProceed(packsToLoad);
        }
    }

    private void DownloadNextPack(List<string> packsToLoad)
    {
        if (_pendingPacks.Count == 0)
        {
            StatusLabel.Text = "Semua aset selesai diunduh. Memuat game...";
            ProgressBar.Value = 100;
            DetailLabel.Text = "";
            SpeedLabel.Text = "";
            LoadPacksAndProceed(packsToLoad);
            return;
        }

        _currentDownloadingPack = _pendingPacks[0];
        _pendingPacks.RemoveAt(0);

        string savePath = $"user://{_currentDownloadingPack.Name}";

        // Reuse a local copy that still matches the manifest hash. Saves the player a full
        // re-download of the 100+ MB base pack on every launch.
        if (IsLocalPackValid(_currentDownloadingPack, savePath))
        {
            GD.Print($"Local copy of {_currentDownloadingPack.Name} is already valid, skipping download.");
            DownloadNextPack(packsToLoad);
            return;
        }

        DownloadRequest.DownloadFile = savePath;

        StatusLabel.Text = $"Mengunduh {_currentDownloadingPack.Name}...";
        ProgressBar.Value = 0;
        _isDownloading = true;
        _downloadStartTime = (long)Time.GetTicksMsec();
        _lastBytes = 0;
        _speedUpdateTimer = 0.0;

        string[] headers = new string[] { "User-Agent: GodotEngine-Downloader" };
        GD.Print($"Downloading {_currentDownloadingPack.Name} from {_currentDownloadingPack.Url} to {savePath}");

        Error err = DownloadRequest.Request(_currentDownloadingPack.Url, headers);
        if (err != Error.Ok)
        {
            _isDownloading = false;
            GD.PrintErr($"Gagal memulai unduhan: {err}");
            ShowError($"Gagal mengunduh {_currentDownloadingPack.Name}.");
        }
    }

    private void OnDownloadRequestCompleted(long result, long responseCode, string[] headers, byte[] body)
    {
        _isDownloading = false;
        GD.Print($"Download completed: result={result}, responseCode={responseCode}");

        if (result != (long)HttpRequest.Result.Success || responseCode != 200)
        {
            ShowError($"Gagal mengunduh file aset (Status: {responseCode}). Koneksi terputus.");
            return;
        }

        string downloadedFilePath = $"user://{_currentDownloadingPack.Name}";
        if (!FileAccess.FileExists(downloadedFilePath))
        {
            ShowError("File hasil unduhan tidak ditemukan di penyimpanan lokal.");
            return;
        }

        using var fa = FileAccess.Open(downloadedFilePath, FileAccess.ModeFlags.Read);
        if (fa == null || fa.GetLength() == 0)
        {
            ShowError("File hasil unduhan kosong atau rusak.");
            return;
        }

        long downloadedBytes = (long)fa.GetLength();
        if (_currentDownloadingPack.Size > 0 && downloadedBytes != _currentDownloadingPack.Size)
        {
            ShowError($"Ukuran file tidak cocok (Diterima {downloadedBytes}B, diharapkan {_currentDownloadingPack.Size}B).");
            return;
        }

        // Size alone is not integrity: a truncated or tampered download that happens to match
        // the byte count used to be accepted and then loaded with LoadResourcePack(replaceFiles:true).
        // The manifest already carries a sha256 per pack, so verify against it before loading.
        if (!string.IsNullOrEmpty(_currentDownloadingPack.Sha256))
        {
            StatusLabel.Text = $"Memeriksa integritas {_currentDownloadingPack.Name}...";
            string actual = ComputeSha256Hex(downloadedFilePath);
            if (string.IsNullOrEmpty(actual))
            {
                ShowError($"Gagal menghitung checksum {_currentDownloadingPack.Name}.");
                return;
            }
            if (!string.Equals(actual, _currentDownloadingPack.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                GD.PrintErr($"SHA256 mismatch for {_currentDownloadingPack.Name}: expected {_currentDownloadingPack.Sha256}, got {actual}");
                // Remove the bad file so the retry starts from a clean slate.
                DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(downloadedFilePath));
                ShowError($"File {_currentDownloadingPack.Name} rusak (checksum tidak cocok). Coba unduh ulang.");
                return;
            }
        }
        else
        {
            GD.PrintErr($"Manifest tidak menyertakan sha256 untuk {_currentDownloadingPack.Name}; integritas TIDAK diverifikasi.");
        }

        GD.Print($"Successfully verified {_currentDownloadingPack.Name} ({downloadedBytes} bytes).");

        // Prepare list of packs to load
        var packsToLoad = new List<string>();
        foreach (var p in _manifest.Packs)
        {
            string pPath = $"user://{p.Name}";
            if (FileAccess.FileExists(pPath))
            {
                packsToLoad.Add(pPath);
            }
        }

        // Continue next pack if any
        DownloadNextPack(packsToLoad);
    }

    private void LoadPacksAndProceed(List<string> packPaths)
    {
        StatusLabel.Text = "Memuat paket aset...";
        ProgressBar.Value = 100;

        // Sequential pack loading: Base pack first, then patch packs to overwrite/extend resources
        foreach (var packPath in packPaths)
        {
            GD.Print($"Loading resource pack: {packPath}");
            // ProjectSettings.LoadResourcePack supports user:// or globalized OS paths
            bool loaded = ProjectSettings.LoadResourcePack(packPath, replaceFiles: true);
            if (!loaded)
            {
                // Fallback using globalized path
                string globalPath = ProjectSettings.GlobalizePath(packPath);
                GD.Print($"Retrying LoadResourcePack with globalized path: {globalPath}");
                loaded = ProjectSettings.LoadResourcePack(globalPath, replaceFiles: true);
            }

            if (!loaded)
            {
                ShowError($"Gagal memuat paket aset: {packPath}. Silakan unduh ulang.");
                return;
            }
            GD.Print($"Successfully loaded pack: {packPath}");
        }

        StatusLabel.Text = "Aset berhasil dimuat. Membuka game...";

        // Small delay or deferred call to ensure scene change runs cleanly
        CallDeferred(MethodName.TransitionToMainScene);
    }

    private void TransitionToMainScene()
    {
        GD.Print($"Switching to main scene: {TargetMainScene}");
        Error err = GetTree().ChangeSceneToFile(TargetMainScene);
        if (err != Error.Ok)
        {
            ShowError($"Gagal membuka scene utama '{TargetMainScene}'. Error: {err}");
        }
    }

    /// <summary>
    /// Streams a file through SHA-256 without loading it whole into memory (a base pack is
    /// 100+ MB, which matters on phones). Returns lowercase hex, or "" on failure.
    /// </summary>
    private static string ComputeSha256Hex(string godotPath)
    {
        string absPath = ProjectSettings.GlobalizePath(godotPath);
        if (!System.IO.File.Exists(absPath))
        {
            GD.PrintErr($"ComputeSha256Hex: no such file {absPath}");
            return "";
        }

        try
        {
            using var fs = new System.IO.FileStream(
                absPath,
                System.IO.FileMode.Open,
                System.IO.FileAccess.Read,
                System.IO.FileShare.Read,
                65536,
                System.IO.FileOptions.SequentialScan);

            using var sha = System.Security.Cryptography.SHA256.Create();
            byte[] hash = sha.ComputeHash(fs);

            var sb = new System.Text.StringBuilder(hash.Length * 2);
            foreach (byte b in hash)
            {
                sb.Append(b.ToString("x2"));
            }
            return sb.ToString();
        }
        catch (Exception ex)
        {
            GD.PrintErr($"ComputeSha256Hex failed for {absPath}: {ex.Message}");
            return "";
        }
    }

    /// <summary>
    /// True when the local copy exists and matches both the manifest size and sha256.
    /// A pack with no hash in the manifest is treated as "unknown", i.e. not reusable,
    /// so we always re-download rather than trust an unverifiable file.
    /// </summary>
    private static bool IsLocalPackValid(PackInfo pack, string godotPath)
    {
        if (string.IsNullOrEmpty(pack.Sha256)) return false;
        if (!FileAccess.FileExists(godotPath)) return false;

        using var fa = FileAccess.Open(godotPath, FileAccess.ModeFlags.Read);
        if (fa == null) return false;
        if (pack.Size > 0 && (long)fa.GetLength() != pack.Size) return false;
        fa.Close();

        return string.Equals(ComputeSha256Hex(godotPath), pack.Sha256, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Starts the loading-screen video. This block was copy-pasted verbatim into both
    /// _Ready() and OnRetryPressed(); it now lives in one place.
    /// </summary>
    private void PlayLoadingVideo()
    {
        if (VideoPlayer == null) return;
        if (VideoPlayer.IsPlaying()) return;

        // .ogv is what CI produces (Godot's Theora stream); .mp4 is only a fallback.
        string videoPath = "res://videos/loading.ogv";
        if (!FileAccess.FileExists(videoPath)) videoPath = "res://videos/loading.mp4";
        if (!FileAccess.FileExists(videoPath)) return;

        var stream = GD.Load<VideoStream>(videoPath);
        if (stream == null)
        {
            GD.PrintErr($"Could not load {videoPath} as a VideoStream.");
            return;
        }

        VideoPlayer.Stream = stream;
        VideoPlayer.Play();
    }

    private void ShowError(string message)
    {
        StatusLabel.Text = message;
        SpeedLabel.Text = "";
        RetryButton.Visible = true;
    }

    private void OnRetryPressed()
    {
        PlayLoadingVideo();
        StartUpdateCheck();
    }
}
