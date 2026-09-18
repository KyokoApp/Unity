using Godot;
using System;
using System.Collections.Generic;
using System.Text.Json;

/// <summary>
/// Bootstrapper: memeriksa manifest pembaruan, mengunduh paket aset (.pck)
/// yang berubah saja, lalu memuatnya dan masuk ke scene utama.
///
/// Perbaikan utama dibanding versi lama:
///  1. BUG "stuck di 80MB": HttpRequest.timeout di Godot membatasi TOTAL
///     durasi request (bukan timeout-idle), jadi unduhan 97MB di koneksi
///     lambat selalu dibatalkan sekitar 80MB. Downloader baru tidak punya
///     batas total, hanya STALL timeout (tidak ada byte masuk selama N detik).
///  2. Resume: unduhan memakai file .part + header HTTP Range, sehingga
///     koneksi putus tidak mengulang dari 0 byte.
///  3. Verifikasi SHA256 per pack (sebelumnya hanya ukuran, sehingga tiap
///     update kecil memaksa unduh ulang semuanya). Pack yang identik
///     dilewati -> update hanya mengunduh yang berubah.
///  4. Cleanup otomatis paket usang agar penyimpanan tidak membengkak.
/// </summary>
public partial class Bootstrapper : Control
{
    [Export] public ProgressBar ProgressBar;
    [Export] public Label StatusLabel;
    [Export] public Label DetailLabel;
    [Export] public Label SpeedLabel;
    [Export] public Button RetryButton;
    [Export] public VideoStreamPlayer VideoPlayer;

    // Dibiarkan untuk kompatibilitas dengan bootstrapper.tscn lama.
    [Export] public HttpRequest ManifestRequest;
    [Export] public HttpRequest DownloadRequest;

    [Export] public string FallbackManifestUrl = "https://github.com/KyokoApp/Unity/releases/download/android-apk/version.json";
    [Export] public string GitHubApiReleaseUrl = "https://api.github.com/repos/KyokoApp/Unity/releases/tags/android-apk";
    [Export] public string TargetMainScene = "res://_scenes/main.tscn";

    [ExportGroup("Downloader")]
    [Export] public int MaxAttempts = 6;              // percobaan per file sebelum menyerah (resume tetap jalan)
    [Export] public double StallTimeoutSec = 15.0;    // batal+lanjutkan ulang bila tidak ada byte masuk selama ini
    [Export] public double ConnectTimeoutSec = 20.0;  // batas waktu tunggu koneksi/response header
    [Export] public int MaxRedirects = 5;
    [Export] public bool VerifyHashes = true;         // verifikasi SHA256 bila manifest menyediakan

    private const string StateFilePath = "user://update_state.json";
    private const string LastManifestPath = "user://last_manifest.json";
    private const string ManifestDownloadPath = "user://manifest_dl.json";

    // ---------------------------------------------------------------
    // Data model
    // ---------------------------------------------------------------
    private class PackInfo
    {
        public string Name = "";
        public string Url = "";
        public long Size = 0;
        public string Sha256 = "";
        public bool IsPatch = false;
        public int Order = 0;
    }

    private class ManifestData
    {
        public string Version = "1.0.0";
        public List<PackInfo> Packs = new();
    }

    private class PackStateEntry
    {
        public string Sha256 { get; set; } = "";
        public long Size { get; set; } = 0;
    }

    private class UpdateState
    {
        public Dictionary<string, PackStateEntry> Packs { get; set; } = new();
    }

    private enum Phase { Idle, FetchManifest, Downloading, Loading, WorldBuild, Error }

    // --- SATU layar loading: overlay ini tetap di atas sampai dunia siap dimainkan ---
    private string _threadedScenePath;     // scene utama yang sedang di-load via thread
    private Node _mainSceneInstance;       // instance main.tscn (di root, di bawah overlay ini)
    private double _worldReadyDeadline;    // batas waktu menunggu TerrainManager.Initialized (msec)
    private double _mainSpawnDeadline;     // batas waktu menunggu TerrainManager muncul (msec)
    private const double WorldReadyTimeoutSec = 60.0; // pengaman: jangan kunci user selamanya
    private const double MainSpawnTimeoutSec = 20.0;

    private ManifestData _manifest = new();
    private readonly List<PackInfo> _pendingPacks = new();
    private PackInfo _currentPack;
    private UpdateState _state = new();
    private Phase _phase = Phase.Idle;
    private ResumableDownloader _downloader;
    private long _totalPlanBytes;
    private long _completedPlanBytes;
    private bool _manifestTriedApi;

    // ---------------------------------------------------------------
    // ResumableDownloader: HTTP GET dengan redirect, Range-resume,
    // stall-detector, dan retry backoff. Non-blocking (di-pump per frame).
    // ---------------------------------------------------------------
    private class ResumableDownloader
    {
        public enum DownState { Idle, Running, Done, Failed }

        public DownState State { get; private set; } = DownState.Idle;
        public long BytesSaved { get; private set; }     // byte yang sudah tertulis ke .part
        public long ExpectedTotal { get; private set; }  // total file penuh (bila diketahui)
        public int Attempt { get; private set; }
        public double RetryWaitRemaining { get; private set; }
        public string LastError { get; private set; } = "";

        private readonly string _url;
        private readonly string _tempPath;
        private readonly string _finalPath;
        private readonly string _expectedSha256;
        private readonly long _expectedSize;
        private readonly int _maxAttempts;
        private readonly double _stallTimeout;
        private readonly double _connectTimeout;
        private readonly int _maxRedirects;
        private readonly bool _verifyHash;

        private HttpClient _client;
        private FileAccess _file;
        private string _curHost;
        private int _curPort;
        private string _curPath;
        private TlsOptions _curTls;
        private long _resumeFrom;
        private int _redirects;
        private double _lastProgressMsec;
        private double _phaseStartMsec;
        private double _resumeStartMsec;
        private bool _requestSent;
        private ulong _bodyReceived;
        private long _bodyKnownLength = -1;
        private Step _step = Step.Connect;

        private enum Step { Connect, Request, Response, Body }

        public ResumableDownloader(string url, string userPath, string expectedSha256, long expectedSize,
            int maxAttempts, double stallTimeout, double connectTimeout, int maxRedirects, bool verifyHash = true)
        {
            _url = url;
            _finalPath = userPath;
            _tempPath = userPath + ".part";
            _expectedSha256 = expectedSha256 ?? "";
            _expectedSize = expectedSize;
            _maxAttempts = Math.Max(1, maxAttempts);
            _stallTimeout = stallTimeout;
            _connectTimeout = connectTimeout;
            _maxRedirects = maxRedirects;
            _verifyHash = verifyHash;
        }

        public void Start()
        {
            State = DownState.Running;
            Attempt = 0;
            LastError = "";
            ExpectedTotal = _expectedSize;
            _resumeStartMsec = Time.GetTicksMsec();
            BeginAttempt(resetPosition: false);
        }

        /// <summary>Panggil setiap frame. Mengembalikan true bila masih berjalan.</summary>
        public bool Pump()
        {
            if (State != DownState.Running) return false;

            if (RetryWaitRemaining > 0)
            {
                RetryWaitRemaining -= GetProcessDeltaSafe();
                if (RetryWaitRemaining > 0) return true;
                BeginAttempt(resetPosition: false);
                return true;
            }

            double now = Time.GetTicksMsec();
            double frameBudgetEnd = now + 8.0; // maks ~8ms/frame supaya UI tetap responsif

            try
            {
                while (State == DownState.Running)
                {
                    bool idleWait = false; // tidak ada kemajuan frame ini -> keluar loop (hemat CPU)

                    Error perr = _client.Poll();
                    if (perr != Error.Ok)
                    {
                        FailAttempt("Gagal polling koneksi: " + perr);
                        break;
                    }

                    var status = _client.GetStatus();
                    now = Time.GetTicksMsec();

                    switch (_step)
                    {
                        case Step.Connect:
                        case Step.Request:
                        case Step.Response:
                            if (now - _phaseStartMsec > _connectTimeout * 1000.0)
                            {
                                FailAttempt("Timeout menunggu koneksi/server.");
                                break;
                            }
                            break;
                        case Step.Body:
                            if (now - _lastProgressMsec > _stallTimeout * 1000.0)
                            {
                                FailAttempt("Koneksi macet (stall). Melanjutkan ulang...");
                                break;
                            }
                            break;
                    }
                    if (State != DownState.Running) break;

                    switch (_step)
                    {
                        case Step.Connect:
                            if (status == HttpClient.Status.Connected)
                            {
                                _step = Step.Request;
                            }
                            else if (status == HttpClient.Status.CantConnect ||
                                     status == HttpClient.Status.CantResolve ||
                                     status == HttpClient.Status.TlsHandshakeError ||
                                     status == HttpClient.Status.ConnectionError ||
                                     status == HttpClient.Status.Disconnected)
                            {
                                FailAttempt("Tidak bisa terhubung ke server (" + status + ").");
                            }
                            else
                            {
                                idleWait = true; // masih connect/TLS handshake
                            }
                            break;

                        case Step.Request:
                        {
                            if (_requestSent) { _step = Step.Response; break; }
                            var headers = new List<string>
                            {
                                "User-Agent: GodotEngine-ResumableDownloader",
                                "Accept: */*",
                                "Accept-Encoding: identity",
                                "Connection: close"
                            };
                            if (_resumeFrom > 0)
                            {
                                headers.Add($"Range: bytes={_resumeFrom}-");
                            }
                            Error rerr = _client.Request(HttpClient.Method.Get,
                                string.IsNullOrEmpty(_curPath) ? "/" : _curPath, headers.ToArray());
                            if (rerr != Error.Ok)
                            {
                                FailAttempt("Gagal mengirim request: " + rerr);
                                break;
                            }
                            _requestSent = true;
                            _phaseStartMsec = now;
                            _step = Step.Response;
                            break;
                        }

                        case Step.Response:
                            if (status == HttpClient.Status.ConnectionError ||
                                status == HttpClient.Status.Disconnected)
                            {
                                FailAttempt("Koneksi terputus sebelum respons.");
                                break;
                            }
                            if (_client.HasResponse())
                            {
                                HandleResponse();
                            }
                            else
                            {
                                idleWait = true; // menunggu header respons
                            }
                            break;

                        case Step.Body:
                            if (status != HttpClient.Status.Body && status != HttpClient.Status.Connected)
                            {
                                // Koneksi ditutup server (Connection: close) -> selesai
                                // bila panjang tidak diketahui ATAU kita sudah menerima semuanya.
                                if (_bodyKnownLength < 0 || (long)_bodyReceived >= _bodyKnownLength)
                                {
                                    FinishAttempt();
                                }
                                else
                                {
                                    FailAttempt($"Koneksi putus di tengah ({_bodyReceived}/{_bodyKnownLength} byte).");
                                }
                                break;
                            }

                            byte[] chunk = _client.ReadResponseBodyChunk();
                            if (chunk != null && chunk.Length > 0)
                            {
                                _file.StoreBuffer(chunk);
                                _bodyReceived += (ulong)chunk.Length;
                                BytesSaved = _resumeFrom + (long)_bodyReceived;
                                _lastProgressMsec = now;

                                if (_bodyKnownLength > 0 && (long)_bodyReceived >= _bodyKnownLength)
                                {
                                    FinishAttempt();
                                }
                                // ada data -> lanjutkan loop sampai budget frame habis
                            }
                            else if (_bodyKnownLength >= 0 && (long)_bodyReceived >= _bodyKnownLength)
                            {
                                FinishAttempt();
                            }
                            else
                            {
                                idleWait = true; // belum ada data baru dari socket
                            }
                            break;
                    }

                    if (idleWait) break;
                    if (Time.GetTicksMsec() > frameBudgetEnd) break; // lanjut frame berikutnya
                }
            }
            catch (Exception ex)
            {
                GD.PrintErr("Downloader exception: " + ex);
                FailAttempt("Kesalahan internal: " + ex.Message);
            }

            return State == DownState.Running;
        }

        public void Abort()
        {
            CleanupConnection();
            State = DownState.Failed;
        }

        private void BeginAttempt(bool resetPosition)
        {
            CleanupConnection();
            Attempt++;

            _client = new HttpClient { BlockingModeEnabled = false, ReadChunkSize = 65536 };
            _redirects = 0;
            _requestSent = false;

            if (resetPosition)
            {
                if (FileAccess.FileExists(_tempPath)) DirAccess.RemoveAbsolute(_tempPath);
            }

            _resumeFrom = 0;
            if (FileAccess.FileExists(_tempPath))
            {
                using var peek = FileAccess.Open(_tempPath, FileAccess.ModeFlags.Read);
                if (peek != null) _resumeFrom = (long)peek.GetLength();
            }
            BytesSaved = _resumeFrom;

            if (!ParseUrl(_url, out _curHost, out _curPort, out _curPath, out _curTls))
            {
                FailFinal("URL tidak valid: " + _url);
                return;
            }

            GD.Print($"[Downloader] Attempt {Attempt}/{_maxAttempts} {_url} (resume dari {_resumeFrom} byte)");
            ConnectCurrent();
        }

        private void ConnectCurrent()
        {
            Error err = _client.ConnectToHost(_curHost, _curPort, _curTls);
            _step = Step.Connect;
            _phaseStartMsec = Time.GetTicksMsec();
            _lastProgressMsec = _phaseStartMsec;
            if (err != Error.Ok)
            {
                FailAttempt("ConnectToHost gagal: " + err);
            }
        }

        private void HandleResponse()
        {
            int code = _client.GetResponseCode();
            var respHeaders = _client.GetResponseHeaders();
            _redirects++;

            if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308)
            {
                if (_redirects > _maxRedirects)
                {
                    FailAttempt("Terlalu banyak redirect.");
                    return;
                }
                string location = FindHeader(respHeaders, "Location");
                if (string.IsNullOrEmpty(location))
                {
                    FailAttempt($"Redirect {code} tanpa header Location.");
                    return;
                }
                _client.Close();
                _requestSent = false;

                if (location.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                {
                    if (!ParseUrl(location, out _curHost, out _curPort, out _curPath, out _curTls))
                    {
                        FailAttempt("URL redirect tidak valid: " + location);
                        return;
                    }
                    ConnectCurrent();
                }
                else
                {
                    // Redirect relatif: host/port lama, path baru.
                    _curPath = location;
                    _client.Close();
                    ConnectCurrent();
                }
                return;
            }

            if (code == 416) // Range Not Satisfiable: file lokal mungkin sudah lebih besar/rusak -> mulai bersih
            {
                GD.PrintErr("[Downloader] 416 Range Not Satisfiable - mengulang unduhan dari awal.");
                BeginAttempt(resetPosition: true);
                return;
            }

            if (_resumeFrom > 0 && code == 200)
            {
                // Server mengabaikan Range -> unduh ulang dari 0 (timpa .part).
                GD.Print("[Downloader] Server tidak mendukung resume (200), memulai dari awal.");
                _resumeFrom = 0;
                BytesSaved = 0;
            }
            else if (_resumeFrom > 0 && code == 206)
            {
                GD.Print($"[Downloader] Server menerima resume (206) dari {_resumeFrom} byte.");
            }

            if (code != 200 && code != 206)
            {
                FailAttempt($"HTTP {code} dari server.");
                return;
            }

            _bodyKnownLength = _client.GetResponseBodyLength();
            if (ExpectedTotal <= 0 && _bodyKnownLength > 0)
            {
                ExpectedTotal = _resumeFrom + _bodyKnownLength;
            }

            _file = (_resumeFrom > 0)
                ? FileAccess.Open(_tempPath, FileAccess.ModeFlags.ReadWrite)
                : FileAccess.Open(_tempPath, FileAccess.ModeFlags.Write);
            if (_file == null)
            {
                FailAttempt("Tidak bisa membuka file temp: " + FileAccess.GetOpenError());
                return;
            }
            if (_resumeFrom > 0) _file.SeekEnd();

            _bodyReceived = 0;
            _step = Step.Body;
            _lastProgressMsec = Time.GetTicksMsec();
        }

        private void FinishAttempt()
        {
            CloseFile();
            _client.Close();

            // Verifikasi ukuran bila diketahui
            if (_expectedSize > 0)
            {
                long actual = FileSize(_tempPath);
                if (actual != _expectedSize)
                {
                    FailAttempt($"Ukuran tidak cocok ({actual} != {_expectedSize}).");
                    return;
                }
            }

            // Verifikasi SHA256 bila disediakan manifest
            if (_verifyHash && !string.IsNullOrEmpty(_expectedSha256))
            {
                string actualHash = ComputeSha256(_tempPath);
                if (!string.Equals(actualHash, _expectedSha256, StringComparison.OrdinalIgnoreCase))
                {
                    GD.PrintErr($"[Downloader] SHA256 mismatch: {actualHash} != {_expectedSha256}");
                    // Hash salah sangat mungkin karena .part korup -> buang dan mulai bersih.
                    if (FileAccess.FileExists(_tempPath)) DirAccess.RemoveAbsolute(_tempPath);
                    if (Attempt < _maxAttempts)
                    {
                        RetryWaitRemaining = 1.5 * Attempt;
                        CleanupConnection();
                        return;
                    }
                    FailFinal("Hash tidak cocok setelah beberapa percobaan.");
                    return;
                }
            }

            // Pindahkan .part -> nama final (atomik di user://)
            if (FileAccess.FileExists(_finalPath)) DirAccess.RemoveAbsolute(_finalPath);
            Error rerr = DirAccess.RenameAbsolute(_tempPath, _finalPath);
            if (rerr != Error.Ok)
            {
                FailFinal("Gagal memfinalkan file unduhan: " + rerr);
                return;
            }

            double elapsed = (Time.GetTicksMsec() - _resumeStartMsec) / 1000.0;
            GD.Print($"[Downloader] Selesai {_finalPath} ({BytesSaved} byte, attempt {Attempt}, {elapsed:F1}s)");
            State = DownState.Done;
        }

        private void FailAttempt(string message)
        {
            LastError = message;
            GD.PrintErr($"[Downloader] Attempt {Attempt} gagal: {message}");
            CloseFile();
            _client?.Close();

            if (Attempt >= _maxAttempts)
            {
                FailFinal(message);
                return;
            }
            // Backoff linier: 1.5s, 3s, 4.5s, ... (resume tetap dari .part)
            RetryWaitRemaining = 1.5 * Attempt;
        }

        private void FailFinal(string message)
        {
            LastError = message;
            CleanupConnection();
            State = DownState.Failed;
        }

        private void CleanupConnection()
        {
            CloseFile();
            _client?.Close();
            _client = null;
        }

        private void CloseFile()
        {
            _file?.Close();
            _file = null;
        }

        private static bool ParseUrl(string url, out string host, out int port, out string path, out TlsOptions tls)
        {
            host = ""; port = 80; path = "/"; tls = null;
            try
            {
                var uri = new Uri(url);
                host = uri.Host;
                path = string.IsNullOrEmpty(uri.PathAndQuery) ? "/" : uri.PathAndQuery;
                if (uri.Scheme == Uri.UriSchemeHttps)
                {
                    port = uri.Port > 0 ? uri.Port : 443;
                    tls = TlsOptions.Client();
                }
                else if (uri.Scheme == Uri.UriSchemeHttp)
                {
                    port = uri.Port > 0 ? uri.Port : 80;
                }
                else
                {
                    return false;
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static string FindHeader(string[] headers, string name)
        {
            string prefix = name.ToLowerInvariant() + ":";
            foreach (var h in headers)
            {
                if (h.ToLowerInvariant().StartsWith(prefix))
                    return h.Substring(prefix.Length).Trim();
            }
            return "";
        }

        private static long FileSize(string path)
        {
            using var fa = FileAccess.Open(path, FileAccess.ModeFlags.Read);
            return fa != null ? (long)fa.GetLength() : 0;
        }

        public static string ComputeSha256(string path)
        {
            using var fa = FileAccess.Open(path, FileAccess.ModeFlags.Read);
            if (fa == null) return "";
            var ctx = new HashingContext();
            ctx.Start(HashingContext.HashType.Sha256);
            const int bufSize = 1024 * 1024;
            ulong len = fa.GetLength();
            ulong done = 0;
            while (done < len)
            {
                long chunk = (long)Math.Min((ulong)bufSize, len - done);
                ctx.Update(fa.GetBuffer(chunk));
                done += (ulong)chunk;
            }
            return Convert.ToHexString(ctx.Finish()).ToLowerInvariant();
        }

        private static double GetProcessDeltaSafe()
        {
            // ResumableDownloader bukan Node; aproksimasi delta 1/60 sudah cukup
            // untuk menghitung jeda retry (presisi tinggi tidak diperlukan).
            return 1.0 / 60.0;
        }
    }

    // ---------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------
    public override void _Ready()
    {
        if (RetryButton != null)
        {
            RetryButton.Visible = false;
            RetryButton.Pressed += OnRetryPressed;
        }

        PlayLoadingVideo();
        LoadState();
        StartManifestFetch();
    }

    private double _speedTimer;
    private long _lastSpeedBytes;

    public override void _Process(double delta)
    {
        if (_phase == Phase.WorldBuild)
        {
            PollWorldBuild(delta);
            return;
        }
        if (_downloader == null) return;
        if (_phase != Phase.FetchManifest && _phase != Phase.Downloading) return;

        bool stillRunning = _downloader.Pump();
        UpdateDownloadUi(delta);

        if (!stillRunning)
        {
            if (_downloader.State == ResumableDownloader.DownState.Done)
            {
                if (_phase == Phase.FetchManifest) OnManifestDownloaded();
                else OnPackDownloaded();
            }
            else
            {
                OnDownloaderFailed(_downloader.LastError);
            }
        }
    }

    // ---------------------------------------------------------------
    // UI
    // ---------------------------------------------------------------
    private void UpdateDownloadUi(double delta)
    {
        if (_downloader == null) return;

        if (_downloader.RetryWaitRemaining > 0)
        {
            StatusLabel?.SetText($"Koneksi bermasalah, mencoba lagi dalam {Math.Ceiling(_downloader.RetryWaitRemaining)} dtk (percobaan {_downloader.Attempt}/{MaxAttempts})...");
            return;
        }

        long done = _downloader.BytesSaved;
        long total = _downloader.ExpectedTotal;

        if (_phase == Phase.Downloading)
        {
            double overallDone = _completedPlanBytes + done;
            double pct = _totalPlanBytes > 0 ? overallDone / _totalPlanBytes * 100.0 : 0.0;
            if (ProgressBar != null) ProgressBar.Value = Math.Clamp(pct, 0.0, 100.0);

            double doneMB = overallDone / (1024.0 * 1024.0);
            double totalMB = _totalPlanBytes / (1024.0 * 1024.0);
            int idx = _manifest.Packs.IndexOf(_currentPack) + 1;
            StatusLabel?.SetText($"Mengunduh {_currentPack.Name} (paket {idx}/{_manifest.Packs.Count})");
            DetailLabel?.SetText(total > 0
                ? $"{doneMB:F1} MB / {totalMB:F1} MB [{pct:F0}%]"
                : $"{doneMB:F1} MB");
        }
        else
        {
            DetailLabel?.SetText(done > 0 ? $"{done / 1024.0:F1} KB" : "");
        }

        // Kecepatan unduh rata-rata jendela 0.5 detik
        _speedTimer += delta;
        if (_speedTimer >= 0.5)
        {
            // Saat resume, sampel pertama dimulai dari posisi .part agar
            // kecepatan tidak membaca lonjakan palsu dari byte hasil resume.
            if (_lastSpeedBytes < 0) _lastSpeedBytes = done;
            long speedBytes = Math.Max(0, (long)((done - _lastSpeedBytes) / _speedTimer));
            _lastSpeedBytes = done;
            _speedTimer = 0.0;
            if (SpeedLabel != null)
            {
                SpeedLabel.Text = speedBytes >= 1024 * 1024
                    ? $"{speedBytes / (1024.0 * 1024.0):F2} MB/s"
                    : $"{speedBytes / 1024.0:F1} KB/s";
            }
        }
    }

    private void PlayLoadingVideo()
    {
        string videoPath = "res://videos/loading.ogv";
        if (!FileAccess.FileExists(videoPath)) videoPath = "res://videos/loading.mp4";
        if (FileAccess.FileExists(videoPath) && VideoPlayer != null)
        {
            var stream = GD.Load<VideoStream>(videoPath);
            if (stream != null)
            {
                VideoPlayer.Stream = stream;
                VideoPlayer.Play();
            }
            else
            {
                GD.PrintErr("VideoStream tidak dapat dimuat dari " + videoPath);
            }
        }
    }

    // ---------------------------------------------------------------
    // Manifest
    // ---------------------------------------------------------------
    private void StartManifestFetch()
    {
        _phase = Phase.FetchManifest;
        _manifestTriedApi = false;
        if (RetryButton != null) RetryButton.Visible = false;
        if (ProgressBar != null) ProgressBar.Value = 0;
        if (SpeedLabel != null) SpeedLabel.Text = "";
        DetailLabel?.SetText("");
        StatusLabel?.SetText("Memeriksa pembaruan...");

        BeginDownloader(FallbackManifestUrl, ManifestDownloadPath, "", 0);
    }

    private void BeginDownloader(string url, string userPath, string sha256, long size)
    {
        _downloader = new ResumableDownloader(url, userPath, sha256, size,
            MaxAttempts, StallTimeoutSec, ConnectTimeoutSec, MaxRedirects, VerifyHashes);
        _lastSpeedBytes = -1; // sampel pertama dipakai untuk baseline (resume-aware)
        _speedTimer = 0;
        _downloader.Start();
    }

    private void OnManifestDownloaded()
    {
        string json = ReadTextFile(ManifestDownloadPath);
        if (string.IsNullOrEmpty(json) || !TryParseManifest(json, out _manifest))
        {
            GD.PrintErr("Manifest tidak valid.");
            OnDownloaderFailed("Manifest pembaruan tidak valid.");
            return;
        }

        // Simpan salinan manifest untuk offline mode.
        WriteTextFile(LastManifestPath, json);
        GD.Print($"Manifest v{_manifest.Version}: {_manifest.Packs.Count} paket.");
        PlanDownloads();
    }

    private void OnDownloaderFailed(string message)
    {
        if (_phase == Phase.FetchManifest && !_manifestTriedApi)
        {
            _manifestTriedApi = true;
            GD.Print("Manifest langsung gagal, mencoba endpoint GitHub API...");
            BeginDownloader(GitHubApiReleaseUrl, ManifestDownloadPath, "", 0);
            // Catatan: respons API adalah JSON release (bukan manifest); bila
            // parse gagal, kita jatuh ke offline mode di bawah.
            return;
        }

        if (_phase == Phase.FetchManifest)
        {
            // Offline mode: muat paket lokal bila manifest terakhir lengkap.
            if (TryOfflineContinue()) return;
            ShowError("Gagal memeriksa pembaruan. Periksa koneksi internet. (" + message + ")");
            return;
        }

        // Unduhan gagal penuh: paket lain tetap aman, user bisa Coba Lagi
        // dan resume melanjutkan dari .part (bukan dari 0).
        ShowError($"Unduhan gagal: {message}. Tekan Coba Lagi untuk melanjutkan (tidak mengulang dari awal).");
    }

    private static bool TryParseManifest(string jsonString, out ManifestData manifest)
    {
        manifest = new ManifestData();
        try
        {
            using var doc = JsonDocument.Parse(jsonString);
            var root = doc.RootElement;

            if (root.TryGetProperty("version", out var vProp))
                manifest.Version = vProp.GetString() ?? "1.0.0";

            if (root.TryGetProperty("packs", out var packsProp) && packsProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in packsProp.EnumerateArray())
                {
                    var p = new PackInfo
                    {
                        Name = item.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "",
                        Url = item.TryGetProperty("url", out var u) ? u.GetString() ?? "" : "",
                        Size = item.TryGetProperty("size", out var s) ? s.GetInt64() : 0,
                        Sha256 = item.TryGetProperty("sha256", out var h) ? h.GetString() ?? "" : "",
                        IsPatch = item.TryGetProperty("is_patch", out var ip) && ip.GetBoolean(),
                        Order = item.TryGetProperty("order", out var o) ? o.GetInt32() : 0
                    };
                    if (!string.IsNullOrEmpty(p.Name) && !string.IsNullOrEmpty(p.Url))
                        manifest.Packs.Add(p);
                }
            }
            manifest.Packs.Sort((a, b) => a.Order.CompareTo(b.Order));
            return manifest.Packs.Count > 0;
        }
        catch (Exception ex)
        {
            GD.PrintErr("Gagal parse manifest: " + ex.Message);
            return false;
        }
    }

    // ---------------------------------------------------------------
    // Perencanaan unduhan (inilah inti "update tanpa unduh ulang semua")
    // ---------------------------------------------------------------
    private void PlanDownloads()
    {
        _pendingPacks.Clear();
        _totalPlanBytes = 0;
        _completedPlanBytes = 0;

        foreach (var pack in _manifest.Packs)
        {
            string userPath = $"user://{pack.Name}";
            if (IsPackUpToDate(pack, userPath))
            {
                GD.Print($"[Plan] {pack.Name} sudah mutakhir, dilewati.");
                _completedPlanBytes += PlanSizeOf(pack);
            }
            else
            {
                GD.Print($"[Plan] {pack.Name} perlu diunduh.");
                _pendingPacks.Add(pack);
            }
            _totalPlanBytes += PlanSizeOf(pack);
        }

        if (_pendingPacks.Count == 0)
        {
            StatusLabel?.SetText("Aset sudah mutakhir. Memuat...");
            if (ProgressBar != null) ProgressBar.Value = 100;
            FinishAndLoad();
            return;
        }

        DownloadNextPack();
    }

    private long PlanSizeOf(PackInfo p) => p.Size > 0 ? p.Size : 0;

    private bool IsPackUpToDate(PackInfo pack, string userPath)
    {
        if (!FileAccess.FileExists(userPath)) return false;

        long localSize = 0;
        using (var fa = FileAccess.Open(userPath, FileAccess.ModeFlags.Read))
        {
            if (fa == null) return false;
            localSize = (long)fa.GetLength();
        }
        if (localSize == 0) return false;

        // Jalur cepat: state lokal cocok dengan manifest -> percaya tanpa hash ulang.
        if (_state.Packs.TryGetValue(pack.Name, out var entry))
        {
            bool sizeOk = pack.Size <= 0 || entry.Size == pack.Size;
            bool shaOk = string.IsNullOrEmpty(pack.Sha256) ||
                         string.Equals(entry.Sha256, pack.Sha256, StringComparison.OrdinalIgnoreCase);
            if (sizeOk && shaOk && localSize == entry.Size) return true;
        }

        // State tidak ada/tidak cocok (mis. user dari versi lama):
        // ukuran cocok -> verifikasi hash sekali untuk menghindari unduh ulang.
        if (pack.Size > 0 && localSize != pack.Size) return false;

        if (!string.IsNullOrEmpty(pack.Sha256))
        {
            string localSha = ResumableDownloader.ComputeSha256(userPath);
            if (string.Equals(localSha, pack.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                _state.Packs[pack.Name] = new PackStateEntry { Sha256 = localSha, Size = localSize };
                SaveState();
                return true;
            }
            GD.Print($"[Plan] {pack.Name} hash berbeda (lokal {localSha}), akan diunduh ulang.");
            return false;
        }

        // Tanpa hash di manifest: ukuran cocok sudah cukup.
        return pack.Size <= 0 || localSize == pack.Size;
    }

    // ---------------------------------------------------------------
    // Download queue
    // ---------------------------------------------------------------
    private void DownloadNextPack()
    {
        if (_pendingPacks.Count == 0)
        {
            CleanupStalePacks();
            FinishAndLoad();
            return;
        }

        _currentPack = _pendingPacks[0];
        _pendingPacks.RemoveAt(0);
        _phase = Phase.Downloading;

        string userPath = $"user://{_currentPack.Name}";
        StatusLabel?.SetText($"Mengunduh {_currentPack.Name}...");
        GD.Print($"[Queue] Mengunduh {_currentPack.Name} dari {_currentPack.Url}");

        BeginDownloader(_currentPack.Url, userPath, _currentPack.Sha256, _currentPack.Size);
    }

    private void OnPackDownloaded()
    {
        // Catat ke state agar run berikutnya langsung dilewati.
        _state.Packs[_currentPack.Name] = new PackStateEntry
        {
            Sha256 = _currentPack.Sha256 ?? "",
            Size = _currentPack.Size
        };
        SaveState();

        _completedPlanBytes += PlanSizeOf(_currentPack);
        GD.Print($"[Queue] {_currentPack.Name} selesai & terverifikasi.");

        DownloadNextPack();
    }

    /// <summary>
    /// Hapus .pck/.pck.part yang tidak lagi tercantum di manifest
    /// (mis. patch versi lama) supaya penyimpanan tidak membengkak.
    /// </summary>
    private void CleanupStalePacks()
    {
        var keep = new HashSet<string>();
        foreach (var p in _manifest.Packs) keep.Add(p.Name);

        using var dir = DirAccess.Open("user://");
        if (dir == null) return;
        dir.ListDirBegin();
        string f = dir.GetNext();
        var toDelete = new List<string>();
        while (!string.IsNullOrEmpty(f))
        {
            if ((f.EndsWith(".pck") || f.EndsWith(".pck.part")) && !keep.Contains(f))
                toDelete.Add(f);
            f = dir.GetNext();
        }
        dir.ListDirEnd();

        foreach (var f2 in toDelete)
        {
            GD.Print("[Cleanup] Menghapus paket usang: " + f2);
            DirAccess.RemoveAbsolute("user://" + f2);
        }
    }

    // ---------------------------------------------------------------
    // Muat paket & lanjut ke game
    // ---------------------------------------------------------------
    private void FinishAndLoad()
    {
        StatusLabel?.SetText("Semua aset siap. Memuat game...");
        if (ProgressBar != null) ProgressBar.Value = 100;
        if (SpeedLabel != null) SpeedLabel.Text = "";
        DetailLabel?.SetText("");
        _phase = Phase.Loading;

        // Urutkan sesuai manifest (base dulu, lalu patch) - patch mereplace file base.
        var orderedPaths = new List<string>();
        foreach (var pack in _manifest.Packs)
        {
            string p = $"user://{pack.Name}";
            if (FileAccess.FileExists(p)) orderedPaths.Add(p);
        }

        foreach (var packPath in orderedPaths)
        {
            GD.Print("Memuat paket: " + packPath);
            bool loaded = ProjectSettings.LoadResourcePack(packPath, replaceFiles: true);
            if (!loaded)
            {
                string globalPath = ProjectSettings.GlobalizePath(packPath);
                loaded = !string.IsNullOrEmpty(globalPath) && ProjectSettings.LoadResourcePack(globalPath, replaceFiles: true);
            }
            if (!loaded)
            {
                ShowError($"Gagal memuat paket aset: {packPath}. File mungkin korup.");
                return;
            }
        }

        CallDeferred(MethodName.TransitionToMainScene);
    }

    private void TransitionToMainScene()
    {
        // Dulu: ChangeSceneToFile() -> scene utama dimuat, lalu dunia dibangun di
        // balik loading screen KEDUA di dalam game. Sekarang SATU layar saja:
        // overlay bootstrapper tetap tampil sambil scene utama dimuat (threaded)
        // dan TerrainManager membangun dunia sampai Initialized.
        GD.Print("Memuat scene utama (threaded): " + TargetMainScene);
        _phase = Phase.WorldBuild;
        StatusLabel?.SetText("Membangun dunia...");
        DetailLabel?.SetText("");
        if (SpeedLabel != null) SpeedLabel.Text = "";
        if (ProgressBar != null) ProgressBar.Value = 100;
        _mainSceneInstance = null;
        _threadedScenePath = TargetMainScene;
        ResourceLoader.LoadThreadedRequest(_threadedScenePath);
    }

    private void PollWorldBuild(double delta)
    {
        // Tahap 1: tunggu scene utama selesai dimuat dari thread.
        if (_threadedScenePath != null)
        {
            var status = ResourceLoader.LoadThreadedGetStatus(_threadedScenePath);
            switch (status)
            {
                case ResourceLoader.ThreadLoadStatus.InProgress:
                    return;
                case ResourceLoader.ThreadLoadStatus.Failed:
                case ResourceLoader.ThreadLoadStatus.InvalidResource:
                    _threadedScenePath = null;
                    ShowError("Gagal memuat scene utama: " + TargetMainScene);
                    return;
            }

            // Loaded: instantiate & pasang KE BAWAH overlay ini agar proses
            // pembangunan dunia (beberapa detik) tetap tertutup layar ini.
            PackedScene packed = null;
            try { packed = ResourceLoader.LoadThreadedGet(_threadedScenePath) as PackedScene; }
            catch (Exception ex) { GD.PrintErr("LoadThreadedGet gagal: " + ex.Message); }
            _threadedScenePath = null;
            if (packed == null)
            {
                ShowError("Scene utama tidak valid: " + TargetMainScene);
                return;
            }

            _mainSceneInstance = packed.Instantiate();
            var root = GetTree().Root;
            root.AddChild(_mainSceneInstance);
            GetTree().CurrentScene = _mainSceneInstance;
            // Naikkan overlay ini ke urutan teratas agar menutupi dunia yang sedang dibangun.
            root.MoveChild(this, root.GetChildCount() - 1);

            double nowMs = Time.GetTicksMsec();
            _worldReadyDeadline = nowMs + WorldReadyTimeoutSec * 1000.0;
            _mainSpawnDeadline = nowMs + MainSpawnTimeoutSec * 1000.0;
            return;
        }

        // Tahap 2: tunggu TerrainManager menandai dunia Initialized.
        var tm = Bouncerock.Terrain.TerrainManager.Instance;
        bool worldReady = tm != null &&
            tm.CurrentLoadStatus == Bouncerock.Terrain.TerrainManager.LoadStatuses.Initialized;

        double now = Time.GetTicksMsec();
        if (!worldReady && tm == null && now > _mainSpawnDeadline)
        {
            // Dunia tidak pernah mulai (mis. scene beda) — jangan kunci user.
            GD.PrintErr("[Bootstrapper] TerrainManager tidak ditemukan; membuka layar lebih awal.");
            worldReady = true;
        }
        if (!worldReady && now > _worldReadyDeadline)
        {
            GD.PrintErr("[Bootstrapper] Timeout menunggu dunia siap; membuka layar.");
            worldReady = true;
        }
        if (!worldReady) return;

        FinishLoading();
    }

    private void FinishLoading()
    {
        // Hentikan video loading & matikan loading screen in-game (sekarang jadi
        // jaring pengaman saja — seharusnya sudah tidak pernah terlihat).
        if (VideoPlayer != null)
        {
            VideoPlayer.Stop();
            VideoPlayer.Visible = false;
        }
        if (Bouncerock.UI.GlobalUIManager.Instance != null &&
            Bouncerock.UI.GlobalUIManager.Instance.LoadingUI != null)
        {
            Bouncerock.UI.GlobalUIManager.Instance.LoadingUI.Visible = false;
        }
        _phase = Phase.Idle;
        QueueFree();
    }

    // ---------------------------------------------------------------
    // Offline & state
    // ---------------------------------------------------------------
    private bool TryOfflineContinue()
    {
        string json = ReadTextFile(LastManifestPath);
        if (string.IsNullOrEmpty(json) || !TryParseManifest(json, out var offlineManifest))
            return false;

        foreach (var pack in offlineManifest.Packs)
        {
            string p = $"user://{pack.Name}";
            if (!IsPackUpToDate(pack, p))
            {
                GD.Print("[Offline] Paket belum lengkap untuk mode offline: " + pack.Name);
                return false;
            }
        }

        _manifest = offlineManifest;
        StatusLabel?.SetText("Mode Offline: memuat aset lokal...");
        PlanDownloads(); // semuanya up-to-date -> langsung FinishAndLoad
        return true;
    }

    private void LoadState()
    {
        string json = ReadTextFile(StateFilePath);
        if (string.IsNullOrEmpty(json)) { _state = new UpdateState(); return; }
        try
        {
            _state = JsonSerializer.Deserialize<UpdateState>(json) ?? new UpdateState();
        }
        catch
        {
            _state = new UpdateState();
        }
    }

    private void SaveState()
    {
        try
        {
            string json = JsonSerializer.Serialize(_state, new JsonSerializerOptions { WriteIndented = false });
            WriteTextFile(StateFilePath + ".tmp", json);
            if (FileAccess.FileExists(StateFilePath)) DirAccess.RemoveAbsolute(StateFilePath);
            DirAccess.RenameAbsolute(StateFilePath + ".tmp", StateFilePath);
        }
        catch (Exception ex)
        {
            GD.PrintErr("Gagal menyimpan state: " + ex.Message);
        }
    }

    private static string ReadTextFile(string path)
    {
        if (!FileAccess.FileExists(path)) return "";
        using var fa = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        return fa?.GetAsText() ?? "";
    }

    private static void WriteTextFile(string path, string content)
    {
        using var fa = FileAccess.Open(path, FileAccess.ModeFlags.Write);
        fa?.StoreString(content);
    }

    // ---------------------------------------------------------------
    // Error / retry
    // ---------------------------------------------------------------
    private void ShowError(string message)
    {
        _phase = Phase.Error;
        StatusLabel?.SetText(message);
        if (SpeedLabel != null) SpeedLabel.Text = "";
        if (RetryButton != null) RetryButton.Visible = true;
    }

    private void OnRetryPressed()
    {
        if (RetryButton != null) RetryButton.Visible = false;
        PlayLoadingVideo();

        if (_phase == Phase.Error && _manifest.Packs.Count > 0 && _pendingPacks.Count > 0)
        {
            // Lanjutkan antrean unduhan (resume dari .part).
            _phase = Phase.Downloading;
            StatusLabel?.SetText("Melanjutkan unduhan...");
            if (_currentPack != null)
            {
                _pendingPacks.Insert(0, _currentPack);
                _currentPack = null;
            }
            DownloadNextPack();
        }
        else
        {
            StartManifestFetch();
        }
    }
}
