using System;

namespace RPG.Core
{
    /* ============================================================
       WORLD LOOK POLICY — angka yang membuat dunia terlihat di HP.

       Screenshot user 2026-09-16: HUD hidup, 49 chunk, lampu ada,
       fog nyala, kamera di atas tanah — tapi dunia HITAM PEKAT.
       Dua penyebab yang sama muncul di build CI ke-5:

         1. Shader lit memakai SampleSH (sering 0 di URP mobile +
            ambient Flat) × shadowAttenuation (0 kalau peta bayangan
            gagal di driver Adreno/Mali) = albedo × 0.
         2. Skybox custom (LightMode SRPDefaultUnlit) tidak digambar
            URP sebagai langit di GLES/Vulkan → clear Skybox = hitam.

       Angka di bawah HARUS sama dengan AureliaLitFill.hlsl /
       AureliaToonLighting.hlsl. Tes murni menjaga keduanya tidak
       drift. Runtime (WorldLook) memakai UseSolidSky /
       IsNoisyLog / AmbientTooDark.
       ============================================================ */
    public static class WorldLookPolicy
    {
        /* Lantai bayangan toon: Genshin tidak pernah menaruh
           permukaan di hitam 0. 0,45 = masih ada bentuk, bukan
           malam total. */
        public const double MinShadowAtten = 0.45;

        /* Fill light: albedo × ini, SELALU, bahkan tanpa matahari. */
        public const double FillLight = 0.32;

        /* Kalau SH ~0, pakai abu-abu langit siang ini. */
        public const double AmbientFloor = 0.28;

        /* Fog/MixFog tidak boleh menelan albedo di bawah ini. */
        public const double KeepVisible = 0.40;

        public static bool UseSolidSky(bool mobilePlayer) => mobilePlayer;

        public static bool AmbientTooDark(double r, double g, double b) =>
            r + g + b < 0.15;

        /* DrawMeshInstanced tanpa enableInstancing melempar setiap
           frame. Itu BUKAN alasan loading menampilkan kotak merah
           atau dianggap fatal. */
        public static bool IsNoisyLog(string msg)
        {
            if (string.IsNullOrEmpty(msg)) return false;
            return msg.IndexOf("enable instancing", StringComparison.OrdinalIgnoreCase) >= 0
                || msg.IndexOf("DrawMeshInstanced", StringComparison.OrdinalIgnoreCase) >= 0;
        }
    }
}
