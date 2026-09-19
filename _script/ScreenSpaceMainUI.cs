using Godot;

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
        // Boot window: world/main character belum tentu terdaftar. Jangan NRE.
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
