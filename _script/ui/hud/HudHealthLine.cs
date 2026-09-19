using Godot;

/// <summary>
/// HudHealthLine — bar darah model "satu garis di bawah layar" (ala Genshin).
///
/// Sengaja TANPA panel, TANPA label, TANPA ikon: garis tipis full-width yang
/// menempel di tepi bawah layar, plus sedikit glow. Warna bergeser hijau ->
/// kuning -> merah, dan ada flash putih singkat saat darah berkurang.
///
/// Kontrol ini selalu MouseFilter = Ignore supaya TIDAK pernah menahan
/// sentuhan (penting: seluruh input game ini berbasis _Input/_GuiInput di
/// bawahnya).
/// </summary>
public partial class HudHealthLine : Control
{
    /// <summary>Tebal garis dalam px (basis resolusi UI).</summary>
    [Export] public float LineHeight = 5f;
    /// <summary>Jarak garis dari tepi bawah layar.</summary>
    [Export] public float BottomMargin = 6f;
    /// <summary>Margin kiri-kanan supaya garis tidak menyentuh sudut layar.</summary>
    [Export] public float SideMargin = 24f;

    [ExportGroup("Warna")]
    [Export] public Color ColorHealthy = new Color(0.52f, 0.86f, 0.56f, 0.95f);
    [Export] public Color ColorHurt = new Color(0.95f, 0.80f, 0.35f, 0.95f);
    [Export] public Color ColorCritical = new Color(0.93f, 0.36f, 0.31f, 0.98f);
    [Export] public Color TrackColor = new Color(0f, 0f, 0f, 0.42f);

    /// <summary>Seberapa cepat nilai tampilan mengejar nilai sebenarnya (px-ratio/detik).</summary>
    [Export] public float EaseSpeed = 3.0f;

    private float _display = 1f;
    private float _target = 1f;
    private float _flash;
    private const float FlashTime = 0.30f;

    /// <summary>Rasio yang benar-benar digambar (0..1) — tersedia untuk debug/overlay.</summary>
    public float DisplayRatio => _display;

    public override void _Ready()
    {
        MouseFilter = MouseFilterEnum.Ignore;
        SetAnchorsPreset(LayoutPreset.FullRect);
        _display = _target;
        QueueRedraw();
    }

    /// <summary>Isi 0..1. Turun mendadak -> flash; naik -> easing halus tanpa flash.</summary>
    public void SetRatio(float ratio)
    {
        ratio = Mathf.Clamp(ratio, 0f, 1f);
        if (ratio < _target - 0.0005f)
        {
            _flash = FlashTime;
        }
        _target = ratio;
    }

    public override void _Process(double delta)
    {
        float d = (float)delta;
        bool dirty = false;

        if (Mathf.Abs(_display - _target) > 0.001f)
        {
            _display = Mathf.MoveToward(_display, _target, d * EaseSpeed);
            dirty = true;
        }
        if (_flash > 0f)
        {
            _flash = Mathf.Max(0f, _flash - d);
            dirty = true;
        }
        if (dirty) QueueRedraw();
    }

    public override void _Draw()
    {
        float w = Size.X;
        float h = Size.Y;
        if (w <= 1f || h <= 1f) return;

        float usable = Mathf.Max(0f, w - SideMargin * 2f);
        Vector2 origin = new Vector2(SideMargin, h - BottomMargin - LineHeight);
        Rect2 track = new Rect2(origin, new Vector2(usable, LineHeight));

        // Glow lembut di belakang garis (2x lebih lebar, alpha kecil) — murah, 1 draw call.
        DrawRect(new Rect2(origin - new Vector2(0f, LineHeight * 0.6f),
                           new Vector2(usable, LineHeight * 2.2f)),
                 new Color(0f, 0f, 0f, 0.18f));

        // Track (bagian kosong)
        DrawRect(track, TrackColor);
        // Garis pemisah 1px di atas track supaya terbaca di latar terang
        DrawRect(new Rect2(origin - new Vector2(0f, 1f), new Vector2(usable, 1f)),
                 new Color(1f, 1f, 1f, 0.10f));

        float fillW = usable * Mathf.Clamp(_display, 0f, 1f);
        if (fillW < 0.5f) return;

        Color baseCol = CurrentColor();
        if (_flash > 0f)
        {
            baseCol = baseCol.Lerp(Colors.White, 0.75f * (_flash / FlashTime));
        }
        Color tipCol = baseCol.Lightened(0.22f);

        // Fill dengan gradien kiri->kanan lewat vertex color (tanpa alokasi shader/material).
        // Catatan API: di C# draw_polygon() memakai array biasa (Vector2[]/Color[]),
        // bukan PackedVector2Array/PackedColorArray seperti di GDScript.
        Vector2[] pts = new Vector2[]
        {
            origin,
            origin + new Vector2(fillW, 0f),
            origin + new Vector2(fillW, LineHeight),
            origin + new Vector2(0f, LineHeight),
        };
        Color[] cols = new Color[] { baseCol, tipCol, tipCol, baseCol };
        // Godot 4 tidak lagi menerima daftar indeks di draw_polygon (itu API 3.x);
        // urutannya saja yang harus searah jarum jam, quad ini cembung jadi aman.
        DrawPolygon(pts, cols);

        // Ujung kanan terang (indikator "sekarang")
        DrawRect(new Rect2(origin + new Vector2(Mathf.Max(0f, fillW - 2f), 0f),
                           new Vector2(2f, LineHeight)),
                 new Color(1f, 1f, 1f, 0.8f));
    }

    private Color CurrentColor()
    {
        if (_display >= 0.55f)
        {
            // 0.55..1.0 -> Hurt..Healthy
            float t = Mathf.InverseLerp(0.55f, 1f, _display);
            return ColorHurt.Lerp(ColorHealthy, t);
        }
        // 0..0.55 -> Critical..Hurt
        float k = Mathf.InverseLerp(0f, 0.55f, _display);
        return ColorCritical.Lerp(ColorHurt, k);
    }
}
