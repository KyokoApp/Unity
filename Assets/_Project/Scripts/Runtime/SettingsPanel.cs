using UnityEngine;
using RPG.Core;

namespace RPG.Runtime
{
    // ============================================================
    // SettingsPanel — UI setting grafik ala Genshin
    //
    // Pakai OnGUI supaya tidak perlu Canvas/UGUI (project ini memang
    // OnGUI untuk semua HUD). Tampilkan di kiri-atas, bisa dibuka/tutup
    // via tombol.
    //
    // Fitur:
    // - Pilih preset: Rendah, Sedang, Tinggi, Ultra, Custom
    // - Toggle bayangan, rumput, FPS, dll
    // - Slider sensitivitas & jarak kamera
    // - Tombol reset
    // - Cel-shading intensity (feather) bisa diatur via preset
    // ============================================================
    [DisallowMultipleComponent]
    public class SettingsPanel : MonoBehaviour
    {
        [Header("Rujukan")]
        public GfxApplier Applier;
        public TerrainChunkStreamer Streamer;
        public GrassField Grass;

        public bool Visible = false;
        GameSettings _settings;

        GUIStyle _boxStyle;
        GUIStyle _btnStyle;
        GUIStyle _labelStyle;
        GUIStyle _toggleStyle;

        Vector2 _scroll;

        void Awake()
        {
            _settings = SettingsStore.Load();
            if (Applier == null) Applier = FindFirstObjectByType<GfxApplier>();
            if (Streamer == null) Streamer = FindFirstObjectByType<TerrainChunkStreamer>();
            if (Grass == null) Grass = FindFirstObjectByType<GrassField>();
        }

        void Update()
        {
            if (Input.GetKeyDown(KeyCode.Escape))
                Visible = !Visible;
        }

        void OnGUI()
        {
            EnsureStyles();

            // Tombol buka setting di kiri-atas (selalu visible)
            if (!Visible)
            {
                if (GUI.Button(new Rect(12, 12, 110, 44), "Setting", _btnStyle))
                    Visible = true;
                return;
            }

            // Panel besar
            var w = Mathf.Min(Screen.width - 24, 520);
            var h = Mathf.Min(Screen.height - 24, 720);
            var rect = new Rect(12, 12, w, h);
            GUI.Box(rect, "", _boxStyle);

            GUILayout.BeginArea(rect);
            _scroll = GUILayout.BeginScrollView(_scroll);

            GUILayout.Label("GRAFIK - Cel Shading Genshin", _labelStyle);
            GUILayout.Space(8);

            // Preset buttons
            GUILayout.Label("Preset Kualitas:", _labelStyle);
            GUILayout.BeginHorizontal();
            foreach (var id in QualityPresets.PresetIds)
            {
                var label = QualityPresets.PresetLabel.ContainsKey(id) ? QualityPresets.PresetLabel[id] : id;
                var isActive = _settings.Quality == id;
                var prevColor = GUI.backgroundColor;
                if (isActive) GUI.backgroundColor = Color.green;
                if (GUILayout.Button(label, _btnStyle, GUILayout.Height(36)))
                {
                    _settings = QualityPresets.ApplyPreset(_settings, id);
                    ApplyAndSave();
                }
                GUI.backgroundColor = prevColor;
            }
            GUILayout.EndHorizontal();

            if (_settings.Quality == "custom")
                GUILayout.Label("Mode: Custom (ubah opsi di bawah)", _labelStyle);

            GUILayout.Space(12);

            // Gfx options
            GUILayout.Label("Detail Grafik:", _labelStyle);
            foreach (var opt in QualityPresets.GfxOptions)
            {
                GUILayout.BeginHorizontal();
                GUILayout.Label($"{opt.Label} ({opt.Hint})", _labelStyle, GUILayout.Width(220));
                int cur = GetGfxLevel(opt.Key);
                string[] labels = opt.Key == "texture" ? QualityPresets.TextureLevelLabel : QualityPresets.LevelLabel;
                for (int lvl = 0; lvl <= opt.Max; lvl++)
                {
                    var isCur = cur == lvl;
                    var prev = GUI.backgroundColor;
                    if (isCur) GUI.backgroundColor = new Color(0.6f, 0.9f, 1f);
                    if (GUILayout.Button(labels[lvl], _btnStyle, GUILayout.Width(68), GUILayout.Height(28)))
                    {
                        _settings = QualityPresets.SetGfx(_settings, opt.Key, lvl);
                        ApplyAndSave();
                    }
                    GUI.backgroundColor = prev;
                }
                GUILayout.EndHorizontal();
            }

            GUILayout.Space(8);
            // Adaptive
            bool adaptive = _settings.Gfx.Adaptive;
            bool newAdaptive = GUILayout.Toggle(adaptive, " Adaptive Resolution (turunkan resolusi saat lag)", _toggleStyle);
            if (newAdaptive != adaptive)
            {
                _settings = QualityPresets.SetGfx(_settings, "adaptive", newAdaptive);
                ApplyAndSave();
            }

            GUILayout.Space(12);
            // RenderScale
            GUILayout.Label($"Render Scale: {_settings.Gfx.RenderScale:F2}", _labelStyle);
            float newScale = GUILayout.HorizontalSlider((float)_settings.Gfx.RenderScale, 0.5f, 1.5f);
            if (Mathf.Abs(newScale - (float)_settings.Gfx.RenderScale) > 0.01f)
            {
                _settings = QualityPresets.SetGfx(_settings, "renderScale", newScale);
                ApplyAndSave();
            }

            GUILayout.Space(12);
            // Kamera
            GUILayout.Label($"Jarak Kamera: {_settings.CameraDistance:F1} m", _labelStyle);
            float newDist = GUILayout.HorizontalSlider((float)_settings.CameraDistance, 3f, 8f);
            if (Mathf.Abs(newDist - (float)_settings.CameraDistance) > 0.01f)
            {
                _settings = SettingsStore.WithCameraDistance(_settings, newDist);
                SettingsStore.Save(_settings);
                // Update camera rig langsung
                var rig = FindFirstObjectByType<CameraRig>();
                if (rig != null) rig.SetDistance(newDist);
            }

            GUILayout.Label($"Sensitivitas: {_settings.Sensitivity:F2}", _labelStyle);
            float newSens = GUILayout.HorizontalSlider((float)_settings.Sensitivity, 0.4f, 2f);
            if (Mathf.Abs(newSens - (float)_settings.Sensitivity) > 0.01f)
            {
                _settings = SettingsStore.WithSensitivity(_settings, newSens);
                SettingsStore.Save(_settings);
            }

            GUILayout.Space(12);
            // Toggles
            bool shadows = _settings.Shadows;
            bool newShadows = GUILayout.Toggle(shadows, " Bayangan (butuh restart area)", _toggleStyle);
            if (newShadows != shadows)
            {
                var raw = new RawSettings
                {
                    Sensitivity = _settings.Sensitivity,
                    CameraDistance = _settings.CameraDistance,
                    Quality = _settings.Quality,
                    Shadows = newShadows,
                    Sound = _settings.Sound,
                    Fps = _settings.Fps,
                    Custom = _settings.Custom,
                    ShowFps = _settings.ShowFps,
                    StickShape = _settings.StickShape,
                    ButtonTheme = _settings.ButtonTheme,
                    ButtonScale = _settings.ButtonScale,
                    Gfx = new RawGfx
                    {
                        RenderScale = _settings.Gfx.RenderScale,
                        Shadows = _settings.Gfx.Shadows,
                        Grass = _settings.Gfx.Grass,
                        Particles = _settings.Gfx.Particles,
                        Water = _settings.Gfx.Water,
                        View = _settings.Gfx.View,
                        Detail = _settings.Gfx.Detail,
                        Texture = _settings.Gfx.Texture,
                        Bloom = _settings.Gfx.Bloom,
                        MotionBlur = _settings.Gfx.MotionBlur,
                        Volumetric = _settings.Gfx.Volumetric,
                        Adaptive = _settings.Gfx.Adaptive
                    }
                };
                _settings = SettingsNormalizer.Normalize(raw);
                ApplyAndSave();
            }

            bool showFps = _settings.ShowFps;
            bool newShowFps = GUILayout.Toggle(showFps, " Tampilkan FPS", _toggleStyle);
            if (newShowFps != showFps)
            {
                var raw = new RawSettings
                {
                    Sensitivity = _settings.Sensitivity,
                    CameraDistance = _settings.CameraDistance,
                    Quality = _settings.Quality,
                    Shadows = _settings.Shadows,
                    Sound = _settings.Sound,
                    Fps = _settings.Fps,
                    Custom = _settings.Custom,
                    ShowFps = newShowFps,
                    StickShape = _settings.StickShape,
                    ButtonTheme = _settings.ButtonTheme,
                    ButtonScale = _settings.ButtonScale,
                    Gfx = new RawGfx
                    {
                        RenderScale = _settings.Gfx.RenderScale,
                        Shadows = _settings.Gfx.Shadows,
                        Grass = _settings.Gfx.Grass,
                        Particles = _settings.Gfx.Particles,
                        Water = _settings.Gfx.Water,
                        View = _settings.Gfx.View,
                        Detail = _settings.Gfx.Detail,
                        Texture = _settings.Gfx.Texture,
                        Bloom = _settings.Gfx.Bloom,
                        MotionBlur = _settings.Gfx.MotionBlur,
                        Volumetric = _settings.Gfx.Volumetric,
                        Adaptive = _settings.Gfx.Adaptive
                    }
                };
                _settings = SettingsNormalizer.Normalize(raw);
                ApplyAndSave();
            }

            GUILayout.Space(12);
            if (GUILayout.Button("Reset ke Default (Sedang)", _btnStyle, GUILayout.Height(36)))
            {
                _settings = QualityPresets.DefaultSettings();
                ApplyAndSave();
            }

            GUILayout.Space(8);
            if (GUILayout.Button("Tutup Setting", _btnStyle, GUILayout.Height(40)))
                Visible = false;

            GUILayout.Space(8);
            GUILayout.Label("Cel-Shading: Aktif (Genshin-style)\n- Terrain: 3-tone ramp\n- Grass: 2-tone + wind\n- Char: 3-tone + rim + outline\n- Feather kecil = garis tegas", _labelStyle);

            GUILayout.EndScrollView();
            GUILayout.EndArea();
        }

        int GetGfxLevel(string key)
        {
            switch (key)
            {
                case "shadows": return _settings.Gfx.Shadows;
                case "grass": return _settings.Gfx.Grass;
                case "particles": return _settings.Gfx.Particles;
                case "water": return _settings.Gfx.Water;
                case "view": return _settings.Gfx.View;
                case "detail": return _settings.Gfx.Detail;
                case "texture": return _settings.Gfx.Texture;
                case "bloom": return _settings.Gfx.Bloom;
                case "motionBlur": return _settings.Gfx.MotionBlur;
                case "volumetric": return _settings.Gfx.Volumetric;
                default: return 0;
            }
        }

        void ApplyAndSave()
        {
            SettingsStore.Save(_settings);
            if (Applier != null) Applier.Apply(_settings);
            else
            {
                // fallback: cari applier
                var ap = FindFirstObjectByType<GfxApplier>();
                if (ap != null) ap.Apply(_settings);
            }
        }

        void EnsureStyles()
        {
            if (_boxStyle != null) return;
            _boxStyle = new GUIStyle(GUI.skin.box);
            _boxStyle.normal.background = MakeTex(2, 2, new Color(0.08f, 0.09f, 0.12f, 0.92f));
            _boxStyle.padding = new RectOffset(12, 12, 12, 12);

            _btnStyle = new GUIStyle(GUI.skin.button);
            _btnStyle.fontSize = Mathf.Max(12, Screen.height / 48);
            _btnStyle.margin = new RectOffset(4, 4, 4, 4);

            _labelStyle = new GUIStyle(GUI.skin.label);
            _labelStyle.fontSize = Mathf.Max(12, Screen.height / 50);
            _labelStyle.normal.textColor = Color.white;
            _labelStyle.wordWrap = true;

            _toggleStyle = new GUIStyle(GUI.skin.toggle);
            _toggleStyle.fontSize = _labelStyle.fontSize;
            _toggleStyle.normal.textColor = Color.white;
        }

        Texture2D MakeTex(int w, int h, Color col)
        {
            var pix = new Color[w * h];
            for (int i = 0; i < pix.Length; i++) pix[i] = col;
            var tex = new Texture2D(w, h);
            tex.SetPixels(pix);
            tex.Apply();
            return tex;
        }
    }
}
