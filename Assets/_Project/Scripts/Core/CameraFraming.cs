using System;

namespace RPG.Core
{
    /* ============================================================
       CAMERA FRAMING — jarak & orbit orang ketiga ala Genshin.

       GameSettings.CameraDistance TETAP 3..8 default 5 (paritas JS).
       Angka itu adalah tingkat zoom di menu, BUKAN meter di dunia:
       di HP, 5 m membuat karakter sebesar semut (lihat screenshot
       CI lama: offset 8 m, karakter ~10% tinggi layar). Genshin
       menaruh kamera ~3 m di belakang bahu, karakter mengisi
       sepertiga bawah layar.

       Pemetaan (linear, diuji):
         settings 3 -> 2,35 m   (paling dekat)
         settings 5 -> 3,17 m   (default)
         settings 8 -> 4,40 m   (paling jauh yang masih "di belakang")
       ============================================================ */
    public static class CameraFraming
    {
        public const double SettingsMin = 3;
        public const double SettingsMax = 8;
        public const double SettingsDefault = 5;

        public const double MetersMin = 2.35;
        public const double MetersMax = 4.40;
        public const double DefaultFocusHeight = 1.18;
        public const double DefaultPitchDeg = 16;
        public const double DefaultShoulder = 0.28;

        public static double DefaultMeters => MetersFromSettings(SettingsDefault);

        /* settings di luar 3..8 dijepit; NaN/Inf jatuh ke default. */
        public static double MetersFromSettings(double cameraDistance)
        {
            if (double.IsNaN(cameraDistance) || double.IsInfinity(cameraDistance))
                cameraDistance = SettingsDefault;
            var t = (cameraDistance - SettingsMin) / (SettingsMax - SettingsMin);
            if (t < 0) t = 0;
            else if (t > 1) t = 1;
            return MetersMin + t * (MetersMax - MetersMin);
        }

        /* Offset kamera dari titik fokus. Sama dengan
           Quaternion.Euler(pitch, yaw, 0) * Vector3.back * dist
           di Unity (ZXY intrinsik): pitch positif = kamera DI ATAS
           menghadap turun, yaw 0 = di belakang karakter (-Z). */
        public static void OrbitOffset(double yawDeg, double pitchDeg, double dist,
                                       out double x, out double y, out double z)
        {
            var pitch = pitchDeg * Math.PI / 180.0;
            var yaw = yawDeg * Math.PI / 180.0;
            var cp = Math.Cos(pitch);
            var sp = Math.Sin(pitch);
            var cy = Math.Cos(yaw);
            var sy = Math.Sin(yaw);
            x = -sy * cp * dist;
            y =  sp * dist;
            z = -cy * cp * dist;
        }
    }
}
