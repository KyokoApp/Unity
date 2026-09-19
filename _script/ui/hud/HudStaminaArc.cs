using Godot;

/// <summary>
/// HudStaminaArc — pengisi stamina (dash / glide / fly) berbentuk SETENGAH
/// lingkaran, digantung di sisi kanan layar, tepat di samping karakter.
///
/// Gaya yang ditiru: cincin stamina Genshin — satu busur tipis + "roda-roda"
/// pembagi, hilang sendiri saat stamina penuh, muncul halus saat dipakai.
///
/// Digambar penuh lewat _Draw (DrawArc/DrawCircle): nol node anak, nol material,
/// nol alokasi per frame, dan MouseFilter = Ignore jadi tidak pernah menyerap
/// sentuhan.
/// </summary>
public partial class HudStaminaArc : Control
{
    [ExportGroup("Bentuk")]
    /// <summary>Jari-jari busur (setengah lingkaran) dalam px.</summary>
    [Export] public float Radius = 42f;
    /// <summary>Tebal garis busur.</summary>
    [Export] public float Thickness = 6f;
    /// <summary>Jumlah "roda" pembagi stamina (Genshin: 5).</summary>
    [Export(PropertyHint.Range, "1,12,1")]
    public int Wheels = 5;
    /// <summary>Kasarnya busur (titik per length).</summary>
    [Export] public int PointCount = 48;

    [ExportGroup("Warna")]
    [Export] public Color FillColor = new Color(0.98f, 0.86f, 0.55f, 0.95f);
    [Export] public Color LowColor = new Color(1f, 0.47f, 0.36f, 0.95f);
    [Export] public Color TrackColor = new Color(1f, 1f, 1f, 0.16f);
    [Export] public Color DividerColor = new Color(0f, 0f, 0f, 0.55f);

    [ExportGroup("Perilaku")]
    /// <summary>Tersisa berapa lama busur tampil setelah stamina berhenti dipakai (detik).</summary>
    [Export] public float StaySeconds = 1.1f;
    /// <summary>Di atas rasio ini (dan sedang tidak memakai stamina) busur disembunyikan.</summary>
    [Export] public float ShowBelowRatio = 0.995f;
    /// <summary>Kecepatan fade & easing (per detik).</summary>
    [Export] public float AnimSpeed = 6f;

    private float _display = 1f;
    private float _target = 1f;
    private float _alpha;
    private float _idle;
    private bool _wantVisible;
    private bool _paused = true;   // sebelum pernah aktif, jangan digambar

    public float DisplayRatio => _display;

    public override void _Ready()
    {
        MouseFilter = MouseFilterEnum.Ignore;
        // Ukuran Control belum tentu benar saat _Ready (anchor baru diterapkan
        // setelah layout) -> tanpa ini garis/busur tidak pernah digambar.
        Resized += QueueRedraw;
        float w = (Radius + Thickness) * 2f;
        float h = Radius + Thickness * 2f + 8f;
        CustomMinimumSize = new Vector2(w, h);
        // Titik pusat busur = tengah-bawah node, jadi busur "bertumpu" di sisi
        // kanan layar dan membuka ke atas, menempel di samping karakter.
        PivotOffset = new Vector2(w * 0.5f, h);
        Size = CustomMinimumSize;
        Visible = false;
        Modulate = new Color(1f, 1f, 1f, 0f);
    }

    /// <summary>
    /// ratio 0..1 (sisa stamina) + sedang dipakai/tidak.
    /// called ~10x/detik dari ScreenSpaceMainUI (bukan tiap frame).
    /// </summary>
    public void UpdateStamina(float ratio, bool consuming)
    {
        _paused = false;
        _target = Mathf.Clamp(ratio, 0f, 1f);

        bool shouldShow = consuming || _target < ShowBelowRatio;
        _wantVisible = shouldShow;
        if (shouldShow)
        {
            _idle = 0f;
            if (!Visible)
            {
                Visible = true;
            }
        }
        if (Mathf.Abs(_display - _target) > 0.002f) QueueRedraw();
    }

    public override void _Process(double delta)
    {
        if (_paused) return;

        float d = (float)delta;
        bool dirty = false;

        if (!_wantVisible)
        {
            _idle += d;
            if (_idle > StaySeconds && _alpha <= 0.001f)
            {
                Visible = false;
                return;
            }
        }

        // Fade in/out halus
        float alphaTarget = _wantVisible ? 1f : 0f;
        if (Mathf.Abs(_alpha - alphaTarget) > 0.004f)
        {
            _alpha = Mathf.MoveToward(_alpha, alphaTarget, d * AnimSpeed);
            Modulate = new Color(1f, 1f, 1f, _alpha);
            dirty = true;
        }

        // Nilai tampilan mengejar nilai sebenarnya (biar drain-nya enak dilihat)
        if (Mathf.Abs(_display - _target) > 0.004f)
        {
            _display = Mathf.MoveToward(_display, _target, d * 4f);
            dirty = true;
        }

        if (dirty) QueueRedraw();
    }

    public override void _Draw()
    {
        if (_alpha <= 0.002f) return;

        Vector2 center = new Vector2(Size.X * 0.5f, Size.Y - Thickness - 2f);
        float begin = Mathf.Pi;                             // sisi kiri
        float full = begin + Mathf.Pi;                      // sisi kanan (lewat atas)

        // Bayangan tipis biar kebaca di langit terang
        DrawArc(center + new Vector2(0f, 1.5f), Radius, begin, full, PointCount,
                new Color(0f, 0f, 0f, 0.35f), Thickness + 2.5f, true);

        // Track kosong (setengah lingkaran penuh)
        DrawArc(center, Radius, begin, full, PointCount, TrackColor, Thickness, true);

        float ratio = Mathf.Clamp(_display, 0f, 1f);
        float end = begin + ratio * Mathf.Pi;
        Color col = ratio > 0.28f ? FillColor : LowColor;

        if (ratio > 0.002f)
        {
            DrawArc(center, Radius, begin, end, PointCount, col, Thickness, true);

            // "Roda" di ujung stamina (ala Genshin)
            Vector2 tip = center + new Vector2(Mathf.Cos(end), Mathf.Sin(end)) * Radius;
            DrawCircle(tip, Thickness * 0.85f, col);
            DrawArc(tip, Thickness * 0.85f, 0f, Mathf.Tau, 20,
                    new Color(1f, 1f, 1f, 0.85f), 1.2f, true);
        }

        // Pembilah antar-roda
        int dividers = Mathf.Max(1, Wheels);
        for (int i = 1; i < dividers; i++)
        {
            float a = begin + Mathf.Pi * i / dividers;
            Vector2 dir = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
            DrawLine(center + dir * (Radius - Thickness * 0.62f),
                     center + dir * (Radius + Thickness * 0.62f),
                     DividerColor, 1.6f, true);
        }
    }
}
