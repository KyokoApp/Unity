using Godot;

/// <summary>
/// GameSettings: penyimpanan setting pemain (kamera & analog) ke
/// user://game_settings.cfg. Semua komponen (TouchInputManager, kamera dsb.)
/// membaca nilai lewat properti statis ini — tanpa kopling antar-scene.
/// </summary>
public static class GameSettings
{
    private const string ConfigPath = "user://game_settings.cfg";

    // Kamera
    public static float CameraSensitivity { get; set; } = 1.0f;   // pengali 0.3 - 3.0
    public static bool InvertCameraX { get; set; } = false;
    public static bool InvertCameraY { get; set; } = false;

    // Analog / sentuh
    public static float JoystickScale { get; set; } = 1.0f;       // pengali 0.7 - 1.6

    // Debug
    public static bool DebugOverlay { get; set; } = true;         // sementara default ON untuk diagnosa

    private static bool _loaded;

    public static void EnsureLoaded()
    {
        if (_loaded) return;
        _loaded = true;

        var cfg = new ConfigFile();
        Error err = cfg.Load(ConfigPath);
        if (err != Error.Ok) return;

        CameraSensitivity = (float)cfg.GetValue("camera", "sensitivity", CameraSensitivity).AsDouble();
        InvertCameraX = cfg.GetValue("camera", "invert_x", InvertCameraX).AsBool();
        InvertCameraY = cfg.GetValue("camera", "invert_y", InvertCameraY).AsBool();
        JoystickScale = (float)cfg.GetValue("input", "joystick_scale", JoystickScale).AsDouble();
        DebugOverlay = cfg.GetValue("debug", "overlay", DebugOverlay).AsBool();
    }

    public static void Save()
    {
        EnsureLoaded();

        var cfg = new ConfigFile();
        cfg.SetValue("camera", "sensitivity", CameraSensitivity);
        cfg.SetValue("camera", "invert_x", InvertCameraX);
        cfg.SetValue("camera", "invert_y", InvertCameraY);
        cfg.SetValue("input", "joystick_scale", JoystickScale);
        cfg.SetValue("debug", "overlay", DebugOverlay);
        cfg.Save(ConfigPath);
    }
}
