using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace RPG.Runtime
{
    /* ============================================================
       STYLIZED VOLUME — post-processing URP untuk gaya Genshin.

       Dibangun SAAT RUNTIME (bukan aset .profile di repo) supaya
       selamat dari scene-rebuild builder dan selalu konsisten
       dengan kode. Isinya TIGA efek murah yang ramah HP:
         * Bloom HALUS (threshold tinggi — hanya memendar di
           langit cerah, kilau air, dan VFX; bukan seluruh layar)
         * Color Adjustments (saturasi +6, kontras +4 — "pop"
           lembut khas anime, bukan LUT sinematik)
         * Vignette tipis (bingkai lembut, bukan lorong gelap)

       Motion blur & volumetrik SENGAJA tidak ada: keduanya mahal
       di tile-GPU HP dan bukan bagian tampilan Genshin.
       ============================================================ */
    [DisallowMultipleComponent]
    public class StylizedVolume : MonoBehaviour
    {
        public Volume Volume { get; private set; }
        Bloom _bloom;

        static readonly float[] BloomIntensity = { 0f, 0.22f, 0.38f, 0.55f };

        void Awake()
        {
            Volume = gameObject.AddComponent<Volume>();
            Volume.isGlobal = true;
            Volume.priority = 1f;

            var profile = ScriptableObject.CreateInstance<VolumeProfile>();

            // overrides: true = semua parameter langsung aktif (kalau
            // false, overrideState-nya mati dan efeknya DIABAIKAN —
            // jebakan umum yang membuat volume "tidak berpengaruh").
            _bloom = profile.Add<Bloom>(true);
            _bloom.threshold.value = 0.9f;
            _bloom.intensity.value = BloomIntensity[1];
            _bloom.scatter.value = 0.55f;
            _bloom.tint.value = new Color(1f, 0.98f, 0.94f);

            var grade = profile.Add<ColorAdjustments>(true);
            grade.saturation.value = 6f;
            grade.contrast.value = 4f;
            grade.colorFilter.value = new Color(1f, 0.99f, 0.97f);

            var vig = profile.Add<Vignette>(true);
            vig.color.value = new Color(0f, 0f, 0f);
            vig.intensity.value = 0.16f;
            vig.smoothness.value = 0.7f;

            Volume.profile = profile;
        }

        /* Tingkat 0..3 dari GfxResolver (0 = bloom mati total). */
        public void SetBloomLevel(int level)
        {
            level = Mathf.Clamp(level, 0, 3);
            if (_bloom == null) return;
            _bloom.active = level > 0;
            _bloom.intensity.value = BloomIntensity[level];
        }
    }
}
