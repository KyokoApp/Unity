using Godot;
using System;
using Bouncerock.Terrain;

public partial class GraphicsSettingsManager : CanvasLayer
{
    public static GraphicsSettingsManager Instance { get; private set; }

    private Control settingsPanel;
    private Button toggleButton;

    // Overlay diagnosa (bisa dimatikan dari panel Setting → Debug Overlay)
    private PanelContainer debugPanel;
    private Label debugLabel;
    private double _dbgAccum;

    // Presets
    public enum QualityPreset { Low, Medium, High, Ultra, Custom }
    public QualityPreset CurrentPreset { get; private set; } = QualityPreset.Medium;

    // Settings values
    public float RenderScale { get; set; } = 0.9f;
    public bool FogEnabled { get; set; } = true;
    public float FogDensity { get; set; } = 0.005f;
    public bool ShadowEnabled { get; set; } = true;
    public int ShadowFilterQuality { get; set; } = 1; // 0: low/off, 1: mid, 2: high
    public int ViewDistanceChunks { get; set; } = 3; // 2=low (~250m), 3=mid (~400m), 4=high (~500m), 5=ultra (~700m)
    public bool VfxEnabled { get; set; } = true;

    // UI elements references
    private OptionButton presetOption;
    private HSlider resSlider;
    private Label resValueLabel;
    private CheckBox fogCheck;
    private CheckBox shadowCheck;
    private OptionButton shadowQualityOption;
    private HSlider viewDistSlider;
    private Label viewDistValueLabel;
    private CheckBox vfxCheck;

    public override void _Ready()
    {
        Instance = this;
        Layer = 120; // Above gameplay UI

        CreateUI();
        ApplyPreset(QualityPreset.Medium);
    }

    private void CreateUI()
    {
        // 1. Gear Icon Button at Top-Left (below compass)
        toggleButton = new Button();
        toggleButton.Text = "⚙";
        toggleButton.Name = "SettingsGearButton";
        toggleButton.Position = new Vector2(30, 200);
        toggleButton.CustomMinimumSize = new Vector2(55, 55);
        toggleButton.FocusMode = Control.FocusModeEnum.None;
        
        // Clean anime/modern style for gear button
        var btnStyle = new StyleBoxFlat();
        btnStyle.BgColor = new Color(1f, 1f, 1f, 0.25f);
        btnStyle.CornerRadiusBottomLeft = 25;
        btnStyle.CornerRadiusBottomRight = 25;
        btnStyle.CornerRadiusTopLeft = 25;
        btnStyle.CornerRadiusTopRight = 25;
        btnStyle.BorderWidthBottom = 2;
        btnStyle.BorderWidthLeft = 2;
        btnStyle.BorderWidthRight = 2;
        btnStyle.BorderWidthTop = 2;
        btnStyle.BorderColor = new Color(1f, 1f, 1f, 0.75f);
        toggleButton.AddThemeStyleboxOverride("normal", btnStyle);
        toggleButton.AddThemeStyleboxOverride("hover", btnStyle);
        toggleButton.AddThemeStyleboxOverride("pressed", btnStyle);
        toggleButton.AddThemeFontSizeOverride("font_size", 26);
        toggleButton.AddThemeColorOverride("font_color", Colors.White);
        toggleButton.Pressed += OnToggleSettingsPressed;
        AddChild(toggleButton);

        // 2. Settings Panel Modal (Responsive centered dialog)
        settingsPanel = new Panel();
        settingsPanel.Name = "GraphicsSettingsPanel";
        settingsPanel.Visible = false;
        settingsPanel.AnchorsPreset = (int)Control.LayoutPreset.FullRect;
        settingsPanel.AnchorLeft = 0.15f;
        settingsPanel.AnchorRight = 0.85f;
        settingsPanel.AnchorTop = 0.08f;
        settingsPanel.AnchorBottom = 0.92f;
        settingsPanel.OffsetLeft = 0;
        settingsPanel.OffsetTop = 0;
        settingsPanel.OffsetRight = 0;
        settingsPanel.OffsetBottom = 0;

        var panelStyle = new StyleBoxFlat();
        panelStyle.BgColor = new Color(0.08f, 0.10f, 0.16f, 0.92f);
        panelStyle.CornerRadiusBottomLeft = 14;
        panelStyle.CornerRadiusBottomRight = 14;
        panelStyle.CornerRadiusTopLeft = 14;
        panelStyle.CornerRadiusTopRight = 14;
        panelStyle.BorderWidthBottom = 2;
        panelStyle.BorderWidthLeft = 2;
        panelStyle.BorderWidthRight = 2;
        panelStyle.BorderWidthTop = 2;
        panelStyle.BorderColor = new Color(0.4f, 0.7f, 1.0f, 0.6f);
        settingsPanel.AddThemeStyleboxOverride("panel", panelStyle);
        AddChild(settingsPanel);

        // Overlay diagnosa kecil di pojok kiri atas. Menunjukkan apakah
        // sentuhan terdaftar, vektor analog, kamera, dan status init karakter
        // — berguna untuk memverifikasi masalah input di device.
        GameSettings.EnsureLoaded();
        debugPanel = new PanelContainer();
        debugPanel.Name = "DebugOverlay";
        var dbgStyle = new StyleBoxFlat();
        dbgStyle.BgColor = new Color(0f, 0f, 0f, 0.55f);
        dbgStyle.CornerRadiusBottomLeft = 8;
        dbgStyle.CornerRadiusBottomRight = 8;
        dbgStyle.CornerRadiusTopLeft = 8;
        dbgStyle.CornerRadiusTopRight = 8;
        debugPanel.AddThemeStyleboxOverride("panel", dbgStyle);
        debugPanel.Position = new Vector2(20, 270);
        debugLabel = new Label();
        debugLabel.Text = "debug...";
        debugLabel.AddThemeFontSizeOverride("font_size", 14);
        debugLabel.AddThemeColorOverride("font_color", new Color(0.75f, 1f, 0.75f, 1f));
        debugPanel.AddChild(debugLabel);
        debugPanel.Visible = GameSettings.DebugOverlay;
        AddChild(debugPanel);

        // Scrollable container
        var scroll = new ScrollContainer();
        scroll.AnchorsPreset = (int)Control.LayoutPreset.FullRect;
        scroll.OffsetLeft = 20;
        scroll.OffsetTop = 20;
        scroll.OffsetRight = -20;
        scroll.OffsetBottom = -20;
        settingsPanel.AddChild(scroll);

        var vbox = new VBoxContainer();
        vbox.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        vbox.AddThemeConstantOverride("separation", 12);
        scroll.AddChild(vbox);

        // Title and Close button
        var titleRow = new HBoxContainer();
        var titleLabel = new Label();
        titleLabel.Text = "GRAPHICS & OPTIMIZATION";
        titleLabel.AddThemeFontSizeOverride("font_size", 20);
        titleLabel.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        titleRow.AddChild(titleLabel);

        var closeBtn = new Button();
        closeBtn.Text = "✕";
        closeBtn.CustomMinimumSize = new Vector2(36, 36);
        closeBtn.Pressed += () => settingsPanel.Visible = false;
        titleRow.AddChild(closeBtn);
        vbox.AddChild(titleRow);

        // Preset selector
        var presetRow = new HBoxContainer();
        var presetLabel = new Label { Text = "Quality Preset:" };
        presetLabel.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        presetOption = new OptionButton();
        presetOption.CustomMinimumSize = new Vector2(160, 38);
        presetOption.AddItem("Low (Max FPS)", 0);
        presetOption.AddItem("Medium (Balanced)", 1);
        presetOption.AddItem("High (Fidelity)", 2);
        presetOption.AddItem("Ultra (Max Detail)", 3);
        presetOption.AddItem("Custom", 4);
        presetOption.Selected = 1;
        var popup = presetOption.GetPopup();
        if (popup != null)
        {
            popup.TransparentBg = false;
            popup.AddThemeFontSizeOverride("font_size", 18);
        }
        presetOption.ItemSelected += (idx) => ApplyPreset((QualityPreset)idx);
        presetRow.AddChild(presetLabel);
        presetRow.AddChild(presetOption);
        vbox.AddChild(presetRow);

        // Resolution Scale (FSR)
        var resRow = new VBoxContainer();
        var resHeader = new HBoxContainer();
        var resTitle = new Label { Text = "Resolution Scale (FSR):" };
        resTitle.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        resValueLabel = new Label { Text = "90%" };
        resHeader.AddChild(resTitle);
        resHeader.AddChild(resValueLabel);
        resSlider = new HSlider { MinValue = 0.5, MaxValue = 1.0, Step = 0.05, Value = 0.9 };
        resSlider.ValueChanged += (val) => {
            RenderScale = (float)val;
            resValueLabel.Text = $"{(int)(RenderScale * 100)}%";
            GetViewport().Scaling3DScale = RenderScale;
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        resRow.AddChild(resHeader);
        resRow.AddChild(resSlider);
        vbox.AddChild(resRow);

        // Render Distance (Chunks / Max Distance)
        var viewDistRow = new VBoxContainer();
        var viewDistHeader = new HBoxContainer();
        var viewDistTitle = new Label { Text = "Render Distance (Limit):" };
        viewDistTitle.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        viewDistValueLabel = new Label { Text = "3 Chunks (~360m)" };
        viewDistHeader.AddChild(viewDistTitle);
        viewDistHeader.AddChild(viewDistValueLabel);
        viewDistSlider = new HSlider { MinValue = 2, MaxValue = 5, Step = 1, Value = 3 };
        viewDistSlider.ValueChanged += (val) => {
            ViewDistanceChunks = (int)val;
            int approxMeters = ViewDistanceChunks * 120;
            viewDistValueLabel.Text = $"{ViewDistanceChunks} Chunks (~{approxMeters}m)";
            ApplyViewDistance();
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        viewDistRow.AddChild(viewDistHeader);
        viewDistRow.AddChild(viewDistSlider);
        vbox.AddChild(viewDistRow);

        // Fog
        var fogRow = new HBoxContainer();
        fogCheck = new CheckBox { Text = "Atmospheric Fog (Far Occlusion)" };
        fogCheck.ButtonPressed = true;
        fogCheck.Toggled += (toggled) => {
            FogEnabled = toggled;
            ApplyFog();
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        fogRow.AddChild(fogCheck);
        vbox.AddChild(fogRow);

        // Shadows
        var shadowRow = new HBoxContainer();
        shadowCheck = new CheckBox { Text = "Sun & Environment Shadows" };
        shadowCheck.ButtonPressed = true;
        shadowCheck.Toggled += (toggled) => {
            ShadowEnabled = toggled;
            ApplyShadows();
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        shadowRow.AddChild(shadowCheck);
        vbox.AddChild(shadowRow);

        // Shadow Quality
        var shadowQRow = new HBoxContainer();
        var shadowQTitle = new Label { Text = "Shadow Filter Quality:" };
        shadowQTitle.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        shadowQualityOption = new OptionButton();
        shadowQualityOption.AddItem("Soft (Low)", 0);
        shadowQualityOption.AddItem("Medium", 1);
        shadowQualityOption.AddItem("High", 2);
        shadowQualityOption.Selected = 1;
        shadowQualityOption.ItemSelected += (idx) => {
            ShadowFilterQuality = (int)idx;
            ApplyShadows();
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        shadowQRow.AddChild(shadowQTitle);
        shadowQRow.AddChild(shadowQualityOption);
        vbox.AddChild(shadowQRow);

        // VFX
        var vfxRow = new HBoxContainer();
        vfxCheck = new CheckBox { Text = "VFX & Screen Shaders (Sharpen / Chroma)" };
        vfxCheck.ButtonPressed = true;
        vfxCheck.Toggled += (toggled) => {
            VfxEnabled = toggled;
            ApplyVfx();
            presetOption.Selected = (int)QualityPreset.Custom;
        };
        vfxRow.AddChild(vfxCheck);
        vbox.AddChild(vfxRow);

        // ======================= KONTROL & KAMERA =======================
        var ctrlHeader = new Label { Text = "KONTROL & KAMERA" };
        ctrlHeader.AddThemeFontSizeOverride("font_size", 18);
        vbox.AddChild(ctrlHeader);

        // Sensitivitas kamera analog (swipe sisi kanan layar)
        var sensRow = new VBoxContainer();
        var sensHeader = new HBoxContainer();
        var sensTitle = new Label { Text = "Camera Sensitivity:" };
        sensTitle.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        var sensValue = new Label { Text = GameSettings.CameraSensitivity.ToString("0.00") + "x" };
        sensHeader.AddChild(sensTitle);
        sensHeader.AddChild(sensValue);
        var sensSlider = new HSlider { MinValue = 0.3, MaxValue = 3.0, Step = 0.05, Value = GameSettings.CameraSensitivity };
        sensSlider.ValueChanged += (val) => {
            GameSettings.CameraSensitivity = (float)val;
            sensValue.Text = GameSettings.CameraSensitivity.ToString("0.00") + "x";
            GameSettings.Save();
        };
        sensRow.AddChild(sensHeader);
        sensRow.AddChild(sensSlider);
        vbox.AddChild(sensRow);

        // Invert sumbu kamera
        var invertXRow = new HBoxContainer();
        var invertXCheck = new CheckBox { Text = "Invert Camera X (geser kanan → kamera kiri)", ButtonPressed = GameSettings.InvertCameraX };
        invertXCheck.Toggled += (on) => { GameSettings.InvertCameraX = on; GameSettings.Save(); };
        invertXRow.AddChild(invertXCheck);
        vbox.AddChild(invertXRow);

        var invertYRow = new HBoxContainer();
        var invertYCheck = new CheckBox { Text = "Invert Camera Y (geser atas → kamera bawah)", ButtonPressed = GameSettings.InvertCameraY };
        invertYCheck.Toggled += (on) => { GameSettings.InvertCameraY = on; GameSettings.Save(); };
        invertYRow.AddChild(invertYCheck);
        vbox.AddChild(invertYRow);

        // Ukuran analog (radius joystick virtual)
        var joyRow = new VBoxContainer();
        var joyHeader = new HBoxContainer();
        var joyTitle = new Label { Text = "Analog Stick Size:" };
        joyTitle.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        var joyValue = new Label { Text = GameSettings.JoystickScale.ToString("0.00") + "x" };
        joyHeader.AddChild(joyTitle);
        joyHeader.AddChild(joyValue);
        var joySlider = new HSlider { MinValue = 0.7, MaxValue = 1.6, Step = 0.05, Value = GameSettings.JoystickScale };
        joySlider.ValueChanged += (val) => {
            GameSettings.JoystickScale = (float)val;
            joyValue.Text = GameSettings.JoystickScale.ToString("0.00") + "x";
            GameSettings.Save();
        };
        joyRow.AddChild(joyHeader);
        joyRow.AddChild(joySlider);
        vbox.AddChild(joyRow);

        // Overlay diagnosa on/off
        var dbgRow = new HBoxContainer();
        var dbgCheck = new CheckBox { Text = "Debug Overlay (status input di layar)", ButtonPressed = GameSettings.DebugOverlay };
        dbgCheck.Toggled += (on) => {
            GameSettings.DebugOverlay = on;
            GameSettings.Save();
            if (debugPanel != null) debugPanel.Visible = on;
        };
        dbgRow.AddChild(dbgCheck);
        vbox.AddChild(dbgRow);
    }

    // Update overlay diagnosa 5x/detik saja (hemat alokasi string di mobile).
    public override void _Process(double delta)
    {
        if (debugPanel == null || !debugPanel.Visible) return;
        _dbgAccum += delta;
        if (_dbgAccum < 0.2) return;
        _dbgAccum = 0;

        var tim = TouchInputManager.ActiveInstance;
        var ch = GameManager.CurrentCharacter;
        string moveV = tim != null ? tim.MoveVector.ToString("0.00") : "-";
        string camV = tim != null ? tim.CameraRotationAxis.ToString("0.00") : "-";
        bool init = ch != null && ch.Initialized;
        Vector3 pos = ch != null ? ch.GlobalPosition : Vector3.Zero;
        string terrain = Bouncerock.Terrain.TerrainManager.Instance != null
            ? Bouncerock.Terrain.TerrainManager.Instance.CurrentLoadStatus.ToString()
            : "null";
        string phys = ch != null ? ch.PhysicsTicks.ToString() : "-";
        string act = ch != null ? ch.CurrentAction.ToString() : "-";
        string spd = ch != null ? ch.DebugSpeed.ToString("0.0") : "-";
        string vel = ch != null ? $"{ch.Velocity.X:0.00},{ch.Velocity.Y:0.00},{ch.Velocity.Z:0.00}" : "-";
        debugLabel.Text =
            $"FPS {(int)Engine.GetFramesPerSecond()}  |  touch {TouchInputManager.LiveTouchCount}  |  " +
            $"joy {(tim != null && tim.IsJoystickActive ? "ON" : "off")}  |  physics {phys}\n" +
            $"move {moveV}  |  cam {camV}  |  speed {spd}\n" +
            $"char init {init}  |  act {act}  |  vel ({vel})\n" +
            $"terrain {terrain}  |  pos ({pos.X:0.0}, {pos.Y:0.1}, {pos.Z:0.0})";
    }

    private void OnToggleSettingsPressed()
    {
        settingsPanel.Visible = !settingsPanel.Visible;
    }

    public void ApplyPreset(QualityPreset preset)
    {
        CurrentPreset = preset;
        switch (preset)
        {
            case QualityPreset.Low:
                RenderScale = 0.70f;
                ViewDistanceChunks = 2; // ~240m
                FogEnabled = true;
                ShadowEnabled = false;
                ShadowFilterQuality = 0;
                VfxEnabled = false;
                break;

            case QualityPreset.Medium:
                RenderScale = 0.85f;
                ViewDistanceChunks = 3; // ~360m
                FogEnabled = true;
                ShadowEnabled = true;
                ShadowFilterQuality = 1;
                VfxEnabled = true;
                break;

            case QualityPreset.High:
                RenderScale = 1.0f;
                ViewDistanceChunks = 4; // ~480m
                FogEnabled = true;
                ShadowEnabled = true;
                ShadowFilterQuality = 2;
                VfxEnabled = true;
                break;

            case QualityPreset.Ultra:
                RenderScale = 1.0f;
                ViewDistanceChunks = 5; // ~600m
                FogEnabled = true;
                ShadowEnabled = true;
                ShadowFilterQuality = 2;
                VfxEnabled = true;
                break;

            case QualityPreset.Custom:
                return;
        }

        // Sync UI widgets
        if (resSlider != null)
        {
            resSlider.Value = RenderScale;
            resValueLabel.Text = $"{(int)(RenderScale * 100)}%";
        }
        if (viewDistSlider != null)
        {
            viewDistSlider.Value = ViewDistanceChunks;
            viewDistValueLabel.Text = $"{ViewDistanceChunks} Chunks (~{ViewDistanceChunks * 120}m)";
        }
        if (fogCheck != null) fogCheck.ButtonPressed = FogEnabled;
        if (shadowCheck != null) shadowCheck.ButtonPressed = ShadowEnabled;
        if (shadowQualityOption != null) shadowQualityOption.Selected = ShadowFilterQuality;
        if (vfxCheck != null) vfxCheck.ButtonPressed = VfxEnabled;
        if (presetOption != null) presetOption.Selected = (int)preset;

        // Apply to engines
        GetViewport().Scaling3DScale = RenderScale;
        ApplyViewDistance();
        ApplyFog();
        ApplyShadows();
        ApplyVfx();
    }

    private void ApplyViewDistance()
    {
        if (TerrainManager.Instance != null)
        {
            TerrainManager.Instance.ViewingDistance = ViewDistanceChunks;
        }
    }

    private void ApplyFog()
    {
        if (EnvironmentManager.Instance != null && EnvironmentManager.Instance.Environment != null)
        {
            EnvironmentManager.Instance.Environment.FogEnabled = FogEnabled;
            if (FogEnabled)
            {
                // Set dense atmospheric fog limit outside viewing distance
                float maxDistMeters = ViewDistanceChunks * 120f;
                EnvironmentManager.Instance.Environment.FogDensity = 0.005f;
                EnvironmentManager.Instance.Environment.FogAerialPerspective = 0.78f;
            }
        }
    }

    private void ApplyShadows()
    {
        if (EnvironmentManager.Instance != null && EnvironmentManager.Instance.SunLight != null)
        {
            EnvironmentManager.Instance.SunLight.ShadowEnabled = ShadowEnabled;
            RenderingServer.DirectionalShadowAtlasSetSize(ShadowEnabled ? (ShadowFilterQuality == 2 ? 4096 : 2048) : 512, true);
        }
    }

    private void ApplyVfx()
    {
        var mainChar = GameManager.Instance?.GetMainCharacter();
        if (mainChar != null && mainChar.PlayerCamera != null)
        {
            var camera = mainChar.PlayerCamera as MainCharacterCamera;
            if (camera != null && camera.SharpenEffect != null)
            {
                camera.SharpenEffect.Visible = VfxEnabled;
            }
        }
    }
}
