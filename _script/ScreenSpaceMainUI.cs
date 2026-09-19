using Godot;
using Bouncerock.Terrain;

/// <summary>
/// ScreenSpaceMainUI — pengatur HUD in-game.
///
/// Versi Android-only: teks-teks penjelasan ("Distance from start:", "Record:",
/// "Time:", "MOJO", skor &amp; multiplier) sudah dibuang dari layar. Yang tersisa:
///   • satu angka jarak di tengah atas (itu memang skor di endless runner),
///   • garis darah tipis di tepi bawah layar (HudHealthLine),
///   • setengah lingkaran stamina di samping karakter (HudStaminaArc),
///     yang baru muncul saat stamina dipakai — persis seperti game mobile.
///
/// HUD di-update 10x/detik dan SetText hanya saat nilainya berubah:
/// tiap SetText memicu layout ulang + alokasi string (sampah GC per frame
/// di HP). Node lama tidak dihapus dari adegan lewat kode ini — cukup jangan
/// direferensikan lagi (bloknya sudah dibuang dari main.tscn).
/// </summary>
public partial class ScreenSpaceMainUI : Control
{
    [Export] public Label Distance;
    [Export] public HudHealthLine HealthLine;
    [Export] public HudStaminaArc StaminaArc;

    private const double UiUpdateInterval = 0.1;
    private double _uiAccum;
    private double _bootWait;

    private string _lastDistanceText = "";
    private float _record;
    private double _recordFlash;

    public override void _Ready()
    {
        // Seluruh HUD tidak boleh menyerap sentuhan.
        MouseFilter = MouseFilterEnum.Ignore;

        _record = GameManager.Instance != null ? GameManager.Instance.Record : 0f;
    }

    public override void _Process(double delta)
    {
        _uiAccum += delta;
        if (_uiAccum < UiUpdateInterval) return;
        _uiAccum = 0.0;

        GameManager gm = GameManager.Instance;
        MainCharacter ch = gm != null ? gm.GetMainCharacter() : null;

        // Kalau dunia/karakter belum siap, TULISKAN di layar apa yang menahan.
        // Tanpa ini gejalanya cuma layar biru kosong dan tidak bisa ditebak
        // bagian mana yang macet (dan pesan ini hilang sendiri saat sehat).
        string waiting = DescribeBootState(ch);
        if (waiting != null)
        {
            _bootWait += UiUpdateInterval;
            if (Distance != null)
            {
                string txt = "Menunggu " + waiting + " (" + (int)_bootWait + "s)";
                if (txt != _lastDistanceText)
                {
                    Distance.Text = txt;
                    _lastDistanceText = txt;
                }
            }
            return;
        }
        _bootWait = 0.0;
        if (gm == null || ch == null) return;

        float dist = gm.StartingPoint.DistanceTo(ch.GlobalPosition);
        UpdateDistance(dist);
        UpdateVitality(ch);
        UpdateRecord(dist);

        if (_recordFlash > 0.0)
        {
            _recordFlash -= UiUpdateInterval;
            if (_recordFlash <= 0.0 && Distance != null)
            {
                Distance.Modulate = Colors.White;
            }
        }
    }

    /// <summary>null = semuanya siap; selain itu: nama bagian yang masih macet.</summary>
    private string DescribeBootState(MainCharacter ch)
    {
        if (GameManager.Instance == null) return "GameManager";
        TerrainManager tm = TerrainManager.Instance;
        if (tm == null) return "generator dunia";
        if (tm.CurrentLoadStatus != TerrainManager.LoadStatuses.Initialized)
            return "chunk dunia: " + tm.CurrentLoadStatus;
        if (tm.ChunkCount == 0)
            return tm.GenerationErrors > 0
                ? "chunk dunia: 0 aktif, " + tm.GenerationErrors + " error generator"
                : "chunk dunia: belum ada di sekitar kamera";
        if (ch == null) return "karakter";
        return null;
    }

    private void UpdateDistance(float distMeters)
    {
        if (Distance == null) return;
        string txt = Mathf.FloorToInt(distMeters) + " m";
        if (txt != _lastDistanceText)
        {
            Distance.Text = txt;
            _lastDistanceText = txt;
        }
    }

    private void UpdateVitality(MainCharacter ch)
    {
        HealthLine?.SetRatio(ch.HealthRatio);
        StaminaArc?.UpdateStamina(ch.ActionRatio, ch.IsConsumingStamina);
    }

    private void UpdateRecord(float distMeters)
    {
        if (distMeters <= _record) return;

        _record = distMeters;
        if (GameManager.Instance != null)
        {
            GameManager.Instance.Record = distMeters;
        }
        // Beri sinyal singkat, bukan label permanen di layar.
        _recordFlash = 2.0;
        if (Distance != null)
        {
            Distance.Text = Mathf.FloorToInt(distMeters) + " m  ·  REKOR BARU";
            _lastDistanceText = Distance.Text;
            Distance.Modulate = new Color(1f, 0.92f, 0.62f, 1f);
        }
    }
}
